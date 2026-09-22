#!/usr/bin/env bash

check_file_descriptors() {
    local allocated unused maximum usage_pct

    section "7. OPEN FILE DESCRIPTORS"

    read -r allocated unused < /proc/sys/fs/file-nr
    maximum="$(< /proc/sys/fs/file-max)"
    usage_pct="$(percent "$allocated" "$maximum")"

    if float_ge "$usage_pct" "$FD_CRIT"; then
        crit "Open file descriptors=${allocated}/${maximum} (${usage_pct}%)"
    elif float_ge "$usage_pct" "$FD_WARN"; then
        warn "Open file descriptors=${allocated}/${maximum} (${usage_pct}%)"
    else
        ok "Open file descriptors=${allocated}/${maximum} (${usage_pct}%)"
    fi

    if ! command -v lsof >/dev/null 2>&1; then
        skip "lsof missing; cannot list processes holding the most FDs"
        return
    fi

    info "Top open-file holders (sample):"
    lsof -nP 2>/dev/null |
        awk 'NR > 1 { count[$2]++; command[$2] = $1 } END { for (pid in count) print count[pid], pid, command[pid] }' |
        sort -nr |
        head -n 5 |
        while read -r count pid command; do
            log "           PID=${pid} CMD=${command} FD_COUNT=${count}"
        done
}

check_processes() {
    local threads_max pid_max thread_usage_pct

    section "8. PROCESS AND THREAD COUNTS"

    PROCESS_COUNT="$(ps -e --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    THREAD_COUNT="$(ps -eLf --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    threads_max="$(< /proc/sys/kernel/threads-max)"
    pid_max="$(< /proc/sys/kernel/pid_max)"
    thread_usage_pct="$(percent "$THREAD_COUNT" "$threads_max")"

    info "processes=${PROCESS_COUNT}; threads=${THREAD_COUNT}; threads-max=${threads_max}; pid_max=${pid_max}"

    if float_ge "$thread_usage_pct" 80; then
        crit "Thread count=${THREAD_COUNT}/${threads_max} (${thread_usage_pct}%)"
    elif float_ge "$thread_usage_pct" 70; then
        warn "Thread count=${THREAD_COUNT}/${threads_max} (${thread_usage_pct}%)"
    else
        ok "Thread utilization=${thread_usage_pct}% of threads-max"
    fi

    # So sánh với trung bình lịch sử nếu đã đủ dữ liệu.
    baseline_check "Process count" "$PROCESS_COUNT" 2
    baseline_check "Thread count" "$THREAD_COUNT" 3
}
