#!/usr/bin/env bash

node_condition() {
    local node="$1" condition="$2"
    "$KUBECTL_BIN" get node "$node" -o "jsonpath={.status.conditions[?(@.type==\"${condition}\")].status}" 2>/dev/null
}

check_nodes() {
    local node status ready disk memory pid network
    section "NODES"

    if [ "$K8S_API_AVAILABLE" -ne 1 ]; then
        skip "Kubernetes API unavailable; node check not run"
        return
    fi

    while read -r node status _; do
        [ -n "$node" ] || continue
        ready="$(node_condition "$node" Ready)"
        disk="$(node_condition "$node" DiskPressure)"
        memory="$(node_condition "$node" MemoryPressure)"
        pid="$(node_condition "$node" PIDPressure)"
        network="$(node_condition "$node" NetworkUnavailable)"

        if [ "$ready" != "True" ]; then
            crit "Node ${node}: Ready=${ready:-Unknown}"
        elif [[ "$status" == *SchedulingDisabled* ]]; then
            warn "Node ${node}: cordoned (SchedulingDisabled)"
        else
            ok "Node ${node}: Ready"
        fi
        [ "$disk" = "True" ] && warn "Node ${node}: DiskPressure=True"
        [ "$memory" = "True" ] && warn "Node ${node}: MemoryPressure=True"
        [ "$pid" = "True" ] && warn "Node ${node}: PIDPressure=True"
        [ "$network" = "True" ] && warn "Node ${node}: NetworkUnavailable=True"
    done < <("$KUBECTL_BIN" get nodes --no-headers 2>/dev/null)
}
