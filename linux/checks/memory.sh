#!/usr/bin/env bash

check_memory() {
    local mem_total_kb mem_available_kb swap_total_kb swap_free_kb swap_used_kb
    local mem_available_pct swap_used_pct active_swap_samples

    section "3. MEMORY AND ACTIVE SWAPPING"

    mem_total_kb="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
    mem_available_kb="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"
    swap_total_kb="$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)"
    swap_free_kb="$(awk '/^SwapFree:/ { print $2 }' /proc/meminfo)"
    swap_used_kb=$((swap_total_kb - swap_free_kb))
    mem_available_pct="$(percent "$mem_available_kb" "$mem_total_kb")"
    swap_used_pct="$(percent "$swap_used_kb" "$swap_total_kb")"

    info "MemAvailable=$(human_kib "$mem_available_kb") / $(human_kib "$mem_total_kb") (${mem_available_pct}%)"
    info "SwapUsed=$(human_kib "$swap_used_kb") / $(human_kib "$swap_total_kb") (${swap_used_pct}%)"

    if awk -v value="$mem_available_pct" -v limit="$MEM_AVAILABLE_CRIT_PCT" 'BEGIN { exit !(value <= limit) }'; then
        crit "MemAvailable low: ${mem_available_pct}%"
    elif awk -v value="$mem_available_pct" -v limit="$MEM_AVAILABLE_WARN_PCT" 'BEGIN { exit !(value <= limit) }'; then
        warn "MemAvailable low: ${mem_available_pct}%"
    else
        ok "MemAvailable=${mem_available_pct}%"
    fi

    if ! command -v vmstat >/dev/null 2>&1; then
        skip "vmstat missing; skipping active swap paging (install procps/procps-ng)"
        return
    fi

    # si/so > 0 cho biết kernel đang đọc/ghi swap tại thời điểm lấy mẫu.
    active_swap_samples="$(vmstat 1 "$SWAP_SAMPLE_COUNT" 2>/dev/null | awk '
        NR > 3 && $1 ~ /^[0-9]+$/ {
            if ($7 > 0 || $8 > 0) active++
        }
        END { print active + 0 }
    ')"

    if [ "$active_swap_samples" -ge "$SWAP_CRIT_ACTIVE_SAMPLES" ]; then
        crit "Active swapping (si/so > 0) in ${active_swap_samples} samples"
    elif [ "$active_swap_samples" -ge "$SWAP_WARN_ACTIVE_SAMPLES" ]; then
        warn "Active swapping (si/so > 0) in ${active_swap_samples} samples"
    else
        ok "No sustained active swapping (${active_swap_samples} samples with si/so > 0)"
    fi
}
