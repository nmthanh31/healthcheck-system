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
    local target tier directory max_age_hours require_marker latest latest_path
    local current age_hours snapshot_dir latest_backup_log
    if [ "${#K8S_ETCD_BACKUP_TARGETS[@]}" -eq 0 ]; then
        skip "No etcd backup target configured; edit config/targets.conf"
        return
    fi

    current="$(date +%s)"
    for target in "${K8S_ETCD_BACKUP_TARGETS[@]}"; do
        IFS='|' read -r tier directory max_age_hours require_marker <<< "$target"
        require_marker="${require_marker:-false}"
        if [ ! -d "$directory" ]; then
            crit "etcd ${tier} backup directory not found: ${directory}"
            continue
        fi
        latest="$(find "$directory" -type f -name snapshot.db -printf '%T@|%p\n' 2>/dev/null | sort -nr | head -n 1)"
        if [ -z "$latest" ]; then
            crit "No etcd ${tier} snapshot.db found in ${directory}"
            continue
        fi
        latest_path="${latest#*|}"
        snapshot_dir="$(dirname "$latest_path")"
        if [ "$require_marker" = "true" ] && [ ! -f "${snapshot_dir}/SUCCESS" ]; then
            crit "Latest etcd ${tier} snapshot has no SUCCESS marker: ${snapshot_dir}"
            continue
        fi
        age_hours="$(awk -v now="$current" -v then="${latest%%|*}" 'BEGIN { printf "%d", (now-then)/3600 }')"
        if [ "$age_hours" -gt "$max_age_hours" ]; then
            crit "Latest etcd ${tier} snapshot is ${age_hours}h old (limit ${max_age_hours}h)"
            continue
        fi

        # The existing backup job uses etcdctl, so validate that its newest
        # snapshot can be read instead of trusting only mtime.
        if [ -x "$K8S_ETCDCTL_BIN" ]; then
            if ! ETCDCTL_API=3 "$K8S_ETCDCTL_BIN" snapshot status "$latest_path" --write-out=json >/dev/null 2>&1; then
                crit "Latest etcd ${tier} snapshot is not readable by etcdctl: ${latest_path}"
                continue
            fi
        else
            warn "etcdctl not found at ${K8S_ETCDCTL_BIN}; ${tier} snapshot freshness is unverified"
        fi

        # backup_logger() writes this exact status through systemd-cat. This
        # gives the daily report the job's own success/failure signal.
        if command -v journalctl >/dev/null 2>&1; then
            latest_backup_log="$(journalctl -t "$K8S_ETCD_JOURNAL_TAG" --since "${max_age_hours} hours ago" --no-pager -o cat 2>/dev/null | grep -E "etcdv3 ${tier} backup (completed successfully|failed)" | tail -n 1 || true)"
            if [[ "$latest_backup_log" == *"backup failed"* ]]; then
                crit "etcd ${tier} backup job reported failure"
                continue
            elif [[ "$latest_backup_log" != *"completed successfully"* ]]; then
                warn "No recent successful etcd ${tier} backup log with tag ${K8S_ETCD_JOURNAL_TAG}"
            fi
        fi
        ok "Latest etcd ${tier} snapshot is ${age_hours}h old"
    done
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
