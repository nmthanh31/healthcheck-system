#!/usr/bin/env bash

check_disk_io() {
    local iostat_output device await_ms utilization rotation_file rotational
    local await_warn await_crit media_type

    section "5. DISK I/O LATENCY AND UTILIZATION"

    if ! command -v iostat >/dev/null 2>&1; then
        skip "iostat missing; skipping disk latency (install sysstat)"
        return
    fi

    # Report đầu là số liệu từ lúc boot. Report thứ hai đo trong một giây.
    iostat_output="$(mktemp)"
    iostat -dx 1 2 > "$iostat_output" 2>/dev/null || true

    while IFS='|' read -r device await_ms utilization; do
        [ -n "$device" ] || continue
        case "$device" in loop*|ram*|zram*|sr*|fd*) continue ;; esac

        rotation_file="/sys/class/block/${device}/queue/rotational"
        rotational="unknown"
        [ -r "$rotation_file" ] && rotational="$(<"$rotation_file")"

        if [ "$rotational" = "1" ]; then
            media_type="HDD"
            await_warn="$HDD_AWAIT_WARN_MS"
            await_crit="$HDD_AWAIT_CRIT_MS"
        else
            media_type="SSD/NVMe/virtual"
            await_warn="$SSD_AWAIT_WARN_MS"
            await_crit="$SSD_AWAIT_CRIT_MS"
        fi

        if float_ge "$await_ms" "$await_crit"; then
            crit "I/O ${device}: await=${await_ms}ms (${media_type})"
        elif float_ge "$await_ms" "$await_warn"; then
            warn "I/O ${device}: await=${await_ms}ms (${media_type})"
        else
            ok "I/O ${device}: await=${await_ms}ms (${media_type})"
        fi

        # %util gần 100% là tín hiệu đáng tin chủ yếu trên HDD/SATA.
        if [ "$rotational" != "1" ]; then
            info "I/O ${device}: util=${utilization}% (informational for NVMe/virtual disk)"
        elif float_ge "$utilization" "$DISK_UTIL_CRIT"; then
            crit "I/O ${device}: util=${utilization}%"
        elif float_ge "$utilization" "$DISK_UTIL_WARN"; then
            warn "I/O ${device}: util=${utilization}%"
        else
            ok "I/O ${device}: util=${utilization}%"
        fi
    done < <(awk '
        # sysstat phiên bản khác nhau dùng await hoặc r_await/w_await.
        /^Device/ {
            report++
            if (report == 2) {
                for (i = 1; i <= NF; i++) {
                    if ($i == "await") await_column = i
                    if ($i == "r_await") read_await_column = i
                    if ($i == "w_await") write_await_column = i
                    if ($i == "%util") utilization_column = i
                }
            }
            next
        }
        report == 2 && NF > 1 && utilization_column > 0 {
            if (await_column > 0) latency = $await_column
            else if (read_await_column > 0 && write_await_column > 0) {
                latency = ( $read_await_column > $write_await_column ? $read_await_column : $write_await_column )
            } else next
            printf "%s|%s|%s\n", $1, latency, $utilization_column
        }
    ' "$iostat_output")

    rm -f "$iostat_output"
}
