#!/usr/bin/env bash

check_temperatures() {
    local found=0 sensor_path raw_temp sensor_type_file sensor_name temp_c

    for sensor_path in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$sensor_path" ] || continue
        found=1
        raw_temp="$(<"$sensor_path")"
        sensor_type_file="${sensor_path%/temp}/type"
        sensor_name="$(cat "$sensor_type_file" 2>/dev/null || basename "${sensor_path%/temp}")"

        if [ "$raw_temp" -gt 1000 ] 2>/dev/null; then
            temp_c="$(awk -v temp="$raw_temp" 'BEGIN { printf "%.1f", temp / 1000 }')"
        else
            temp_c="$raw_temp"
        fi

        if float_ge "$temp_c" "$TEMP_CRIT"; then
            crit "Temperature ${sensor_name}=${temp_c}C"
        elif float_ge "$temp_c" "$TEMP_WARN"; then
            warn "Temperature ${sensor_name}=${temp_c}C"
        else
            ok "Temperature ${sensor_name}=${temp_c}C"
        fi
    done

    [ "$found" -eq 0 ] && skip "No thermal sensor found in /sys (common on VMs)"
}

check_smart() {
    local found=0 device_path device smart_output

    if ! command -v smartctl >/dev/null 2>&1; then
        skip "smartctl missing; skipping SMART (install smartmontools)"
        return
    fi

    for device_path in /sys/block/*; do
        device="$(basename "$device_path")"
        case "$device" in loop*|ram*|zram*|dm-*|md*|sr*|fd*) continue ;; esac
        [ -b "/dev/$device" ] || continue
        found=1
        smart_output="$(smartctl -H "/dev/$device" 2>/dev/null || true)"

        if grep -Eqi 'PASSED|OK' <<< "$smart_output"; then
            ok "SMART /dev/${device}: PASSED/OK"
        elif grep -Eqi 'FAILED|BAD|FAIL' <<< "$smart_output"; then
            crit "SMART /dev/${device}: FAILED/BAD"
        else
            info "SMART /dev/${device}: no clear health status"
        fi
    done

    [ "$found" -eq 0 ] && skip "No eligible block device found for SMART check"
}

check_ipmi_temperature() {
    local bad_sensor_count

    command -v ipmitool >/dev/null 2>&1 || return
    bad_sensor_count="$(ipmitool sdr type Temperature 2>/dev/null | grep -Eic 'Critical|Non-Recoverable|Failure' || true)"

    if [ "$bad_sensor_count" -gt 0 ]; then
        crit "IPMI reports ${bad_sensor_count} failed temperature sensor(s)"
    else
        ok "IPMI temperature sensors report no Critical/Failure"
    fi
}

check_hardware() {
    section "9. TEMPERATURE AND HARDWARE HEALTH"
    check_temperatures
    check_smart
    check_ipmi_temperature
}
