#!/usr/bin/env bash

check_failed_systemd_units() {
    local failed_units unit

    [ -d /run/systemd/system ] || return
    failed_units="$(systemctl --failed --no-legend --plain 2>/dev/null | awk 'NF { print $1 }')"

    if [ -z "$failed_units" ]; then
        ok "No failed systemd units"
        return
    fi

    while IFS= read -r unit; do
        [ -n "$unit" ] && warn "Failed systemd unit: ${unit}"
    done <<< "$failed_units"
}

check_time_synchronization() {
    local synchronized

    if ! command -v timedatectl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
        skip "timedatectl/systemd unavailable; cannot verify time synchronization"
        return
    fi

    synchronized="$(timedatectl show --property=NTPSynchronized --value 2>/dev/null || true)"
    if [ "$synchronized" = "yes" ]; then
        ok "NTP time synchronization is active"
    else
        warn "NTP is not synchronized"
    fi
}

check_platform_operations() {
    section "PLATFORM OPERATIONS"
    check_failed_systemd_units
    check_time_synchronization
}
