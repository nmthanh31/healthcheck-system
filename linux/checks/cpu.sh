#!/usr/bin/env bash

# Trả về tổng CPU ticks và số ticks iowait từ /proc/stat.
read_cpu_stat() {
    awk '/^cpu / {
        total = 0
        for (i = 2; i <= NF; i++) total += $i
        print total, $6
        exit
    }' /proc/stat
}

check_cpu_iowait() {
    local total_before iowait_before total_after iowait_after
    local total_delta iowait_delta iowait_pct

    section "1. CPU IOWAIT"

    # Cần hai lần đọc để tính iowait trong đúng khoảng sample.
    read -r total_before iowait_before < <(read_cpu_stat)
    sleep "$CPU_SAMPLE_SECONDS"
    read -r total_after iowait_after < <(read_cpu_stat)

    total_delta=$((total_after - total_before))
    iowait_delta=$((iowait_after - iowait_before))
    iowait_pct="$(percent "$iowait_delta" "$total_delta")"

    if float_ge "$iowait_pct" "$IOWAIT_CRIT"; then
        crit "CPU iowait=${iowait_pct}% (critical >= ${IOWAIT_CRIT}%)"
    elif float_ge "$iowait_pct" "$IOWAIT_WARN"; then
        warn "CPU iowait=${iowait_pct}% (warning >= ${IOWAIT_WARN}%)"
    else
        ok "CPU iowait=${iowait_pct}%"
    fi
}

check_load_average() {
    local cpu_cores load1 load5 load15 ignored
    local load1_per_core load15_per_core

    section "2. LOAD AVERAGE VS CPU CORES"

    cpu_cores="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
    read -r load1 load5 load15 ignored < /proc/loadavg
    # `load` là tên builtin của GNU awk mới; dùng tên khác để tương thích.
    load1_per_core="$(awk -v load_value="$load1" -v cores="$cpu_cores" 'BEGIN { printf "%.2f", load_value / cores }')"
    load15_per_core="$(awk -v load_value="$load15" -v cores="$cpu_cores" 'BEGIN { printf "%.2f", load_value / cores }')"

    info "cores=${cpu_cores}; load1=${load1}; load5=${load5}; load15=${load15}"

    if float_ge "$load15_per_core" "$LOAD_CRIT_PER_CORE"; then
        crit "15m load/core=${load15_per_core} (critical >= ${LOAD_CRIT_PER_CORE})"
    elif float_ge "$load15_per_core" "$LOAD_WARN_PER_CORE"; then
        warn "15m load/core=${load15_per_core} (warning >= ${LOAD_WARN_PER_CORE})"
    else
        ok "15m load/core=${load15_per_core}"
    fi

    # 1m > 5m > 15m nghĩa là load đang có xu hướng tăng.
    if float_gt "$load1" "$load5" && float_gt "$load5" "$load15"; then
        if float_ge "$load1_per_core" "$LOAD_WARN_PER_CORE"; then
            warn "Load rising; ${load15} -> ${load5} -> ${load1} (1m/core=${load1_per_core})"
        else
            info "Load rising but remains low per core: ${load15} -> ${load5} -> ${load1}"
        fi
    else
        ok "No rising load sequence (1m > 5m > 15m)"
    fi
}
