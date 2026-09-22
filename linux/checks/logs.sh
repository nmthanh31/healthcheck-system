#!/usr/bin/env bash

check_system_logs() {
    section "10. SYSTEM LOG ERROR RATE"
    LOG_ERRORS=0

    if command -v journalctl >/dev/null 2>&1; then
        # journalctl trả về các message có priority "err" trong 24 giờ qua.
        LOG_ERRORS="$(journalctl -p err --since '24 hours ago' --no-pager -q 2>/dev/null | wc -l | tr -d ' ')"
        baseline_check "journal errors/24h" "$LOG_ERRORS" 4

        if [ "$LOG_ERRORS" -gt 0 ]; then
            info "Five most recent journal errors:"
            journalctl -p err --since '24 hours ago' --no-pager -q -n 5 2>/dev/null |
                while IFS= read -r line; do
                    log "           ${line}"
                done
        fi
    elif [ -r /var/log/syslog ]; then
        LOG_ERRORS="$(grep -iEc 'error|critical' /var/log/syslog 2>/dev/null || true)"
        baseline_check "syslog error/critical count" "$LOG_ERRORS" 4
    else
        skip "Cannot read journalctl or /var/log/syslog"
    fi
}
