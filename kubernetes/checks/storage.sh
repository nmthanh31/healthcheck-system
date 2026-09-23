#!/usr/bin/env bash

check_pvcs() {
    local namespace name phase
    while IFS='|' read -r namespace name phase; do
        [ -n "$name" ] || continue
        is_ignored_namespace "$namespace" && continue
        case "$phase" in
            Bound) ok "PVC ${namespace}/${name}: Bound" ;;
            Lost) crit "PVC ${namespace}/${name}: Lost" ;;
            *) warn "PVC ${namespace}/${name}: status=${phase:-Unknown}" ;;
        esac
    done < <("$KUBECTL_BIN" get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.status.phase}{"\n"}{end}' 2>/dev/null)
}

check_longhorn() {
    local name robustness state
    [ "$K8S_CHECK_LONGHORN" = "true" ] || return
    "$KUBECTL_BIN" get crd volumes.longhorn.io >/dev/null 2>&1 || return

    while IFS='|' read -r name robustness state; do
        [ -n "$name" ] || continue
        case "$robustness" in
            healthy|Healthy) ok "Longhorn ${name}: healthy (${state})" ;;
            faulted|Faulted) crit "Longhorn ${name}: faulted (${state})" ;;
            *) warn "Longhorn ${name}: robustness=${robustness:-Unknown} (${state})" ;;
        esac
    done < <("$KUBECTL_BIN" -n longhorn-system get volumes.longhorn.io -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.robustness}{"|"}{.status.state}{"\n"}{end}' 2>/dev/null)
}

check_etcd_snapshot_age() {
    local latest current age_hours
    if [ -z "$K8S_ETCD_SNAPSHOT_DIR" ]; then
        skip "No etcd snapshot directory configured; edit config/targets.conf"
        return
    fi
    if [ ! -d "$K8S_ETCD_SNAPSHOT_DIR" ]; then
        warn "etcd snapshot directory not found: ${K8S_ETCD_SNAPSHOT_DIR}"
        return
    fi
    latest="$(find "$K8S_ETCD_SNAPSHOT_DIR" -type f -printf '%T@\n' 2>/dev/null | sort -nr | head -n 1)"
    if [ -z "$latest" ]; then
        crit "No etcd snapshot found in ${K8S_ETCD_SNAPSHOT_DIR}"
        return
    fi
    current="$(date +%s)"
    age_hours="$(awk -v now="$current" -v then="$latest" 'BEGIN { printf "%d", (now-then)/3600 }')"
    if [ "$age_hours" -gt "$K8S_ETCD_SNAPSHOT_MAX_AGE_HOURS" ]; then
        crit "Latest etcd snapshot is ${age_hours}h old (limit ${K8S_ETCD_SNAPSHOT_MAX_AGE_HOURS}h)"
    else
        ok "Latest etcd snapshot is ${age_hours}h old"
    fi
}

check_storage() {
    section "STORAGE"
    if [ "$K8S_API_AVAILABLE" -ne 1 ]; then
        skip "Kubernetes API unavailable; storage check not run"
        section "ETCD BACKUP"
        skip "Kubernetes API unavailable; backup check not run"
        return
    fi
    check_pvcs
    check_longhorn
    section "ETCD BACKUP"
    check_etcd_snapshot_age
}
