#!/usr/bin/env bash

save_network_state() {
    local counters_file="$1" tcp_outsegs="$2" tcp_retrans="$3"

    {
        cat "$counters_file"
        printf '__TCP__ %s %s\n' "${tcp_outsegs:-0}" "${tcp_retrans:-0}"
    } > "${NET_STATE_FILE}.tmp"
    mv "${NET_STATE_FILE}.tmp" "$NET_STATE_FILE"
}

check_network() {
    local current_counters iface rx_bytes rx_err rx_drop tx_bytes tx_err tx_drop
    local previous previous_rx_bytes previous_rx_err previous_rx_drop
    local previous_tx_bytes previous_tx_err previous_tx_drop
    local delta_rx_bytes delta_tx_bytes delta_rx_err delta_rx_drop delta_tx_err delta_tx_drop
    local tcp_outsegs tcp_retrans previous_tcp previous_outsegs previous_retrans
    local delta_outsegs delta_retrans retrans_pct

    section "6. NETWORK ERRORS, DROPS AND TCP RETRANSMISSIONS"
    current_counters="$(mktemp)"

    # Lưu counter tuyệt đối; phần dưới sẽ so với lần chạy trước.
    awk 'NR > 2 {
        iface = $1
        sub(/:$/, "", iface)
        print iface, $2, $4, $5, $10, $12, $13
    }' /proc/net/dev > "$current_counters"

    if [ -f "$NET_STATE_FILE" ]; then
        while read -r iface rx_bytes rx_err rx_drop tx_bytes tx_err tx_drop; do
            [ "$iface" = "lo" ] && continue
            previous="$(awk -v name="$iface" '$1 == name { print; exit }' "$NET_STATE_FILE" 2>/dev/null || true)"

            if [ -z "$previous" ]; then
                info "NIC ${iface}: no baseline counter; saving state for next run"
                continue
            fi

            read -r _ previous_rx_bytes previous_rx_err previous_rx_drop previous_tx_bytes previous_tx_err previous_tx_drop <<< "$previous"
            delta_rx_bytes=$((rx_bytes - previous_rx_bytes))
            delta_tx_bytes=$((tx_bytes - previous_tx_bytes))
            delta_rx_err=$((rx_err - previous_rx_err))
            delta_rx_drop=$((rx_drop - previous_rx_drop))
            delta_tx_err=$((tx_err - previous_tx_err))
            delta_tx_drop=$((tx_drop - previous_tx_drop))

            # Counter có thể reset sau reboot hoặc khi NIC được tạo lại.
            for value in delta_rx_bytes delta_tx_bytes delta_rx_err delta_rx_drop delta_tx_err delta_tx_drop; do
                [ "${!value}" -lt 0 ] && printf -v "$value" 0
            done

            info "NIC ${iface}: traffic delta RX=${delta_rx_bytes}B TX=${delta_tx_bytes}B"
            if [ "$delta_rx_err" -gt 0 ] || [ "$delta_rx_drop" -gt 0 ] || [ "$delta_tx_err" -gt 0 ] || [ "$delta_tx_drop" -gt 0 ]; then
                warn "NIC ${iface}: delta RX(err=${delta_rx_err},drop=${delta_rx_drop}) TX(err=${delta_tx_err},drop=${delta_tx_drop})"
            else
                ok "NIC ${iface}: no new errors/drops since prior check"
            fi
        done < "$current_counters"
    else
        info "No network baseline; saving current counters for next run"
    fi

    read -r tcp_outsegs tcp_retrans <<< "$(awk '
        /^Tcp:/ {
            if (!header) {
                for (i = 1; i <= NF; i++) {
                    if ($i == "OutSegs") out_column = i
                    if ($i == "RetransSegs") retrans_column = i
                }
                header = 1
                next
            }
            if (out_column && retrans_column) { print $out_column, $retrans_column; exit }
        }
    ' /proc/net/snmp)"

    previous_tcp="$(grep '^__TCP__ ' "$NET_STATE_FILE" 2>/dev/null || true)"
    if [ -n "$previous_tcp" ] && [ -n "${tcp_outsegs:-}" ] && [ -n "${tcp_retrans:-}" ]; then
        read -r _ previous_outsegs previous_retrans <<< "$previous_tcp"
        delta_outsegs=$((tcp_outsegs - previous_outsegs))
        delta_retrans=$((tcp_retrans - previous_retrans))
        [ "$delta_outsegs" -lt 0 ] && delta_outsegs=0
        [ "$delta_retrans" -lt 0 ] && delta_retrans=0
        retrans_pct="$(percent "$delta_retrans" "$delta_outsegs")"

        if float_ge "$retrans_pct" "$TCP_RETRANS_CRIT_PCT"; then
            crit "TCP retransmission=${retrans_pct}% (${delta_retrans}/${delta_outsegs})"
        elif float_ge "$retrans_pct" "$TCP_RETRANS_WARN_PCT"; then
            warn "TCP retransmission=${retrans_pct}% (${delta_retrans}/${delta_outsegs})"
        else
            ok "TCP retransmission=${retrans_pct}% (${delta_retrans}/${delta_outsegs})"
        fi
    else
        info "TCP retransmission: no baseline counter"
    fi

    save_network_state "$current_counters" "${tcp_outsegs:-0}" "${tcp_retrans:-0}"
    rm -f "$current_counters"
}
