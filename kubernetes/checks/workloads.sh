#!/usr/bin/env bash

check_deployments() {
    local namespace name desired available
    while IFS='|' read -r namespace name desired available; do
        [ -n "$name" ] || continue
        is_ignored_namespace "$namespace" && continue
        desired="${desired:-1}"; available="${available:-0}"
        [ "$desired" -eq 0 ] && continue
        if [ "$available" -lt "$desired" ]; then
            warn "Deployment ${namespace}/${name}: available=${available}/${desired}"
        else
            ok "Deployment ${namespace}/${name}: available=${available}/${desired}"
        fi
    done < <("$KUBECTL_BIN" get deployments -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.spec.replicas}{"|"}{.status.availableReplicas}{"\n"}{end}' 2>/dev/null)
}

check_statefulsets() {
    local namespace name desired ready
    while IFS='|' read -r namespace name desired ready; do
        [ -n "$name" ] || continue
        is_ignored_namespace "$namespace" && continue
        desired="${desired:-1}"; ready="${ready:-0}"
        [ "$desired" -eq 0 ] && continue
        if [ "$ready" -lt "$desired" ]; then warn "StatefulSet ${namespace}/${name}: ready=${ready}/${desired}"
        else ok "StatefulSet ${namespace}/${name}: ready=${ready}/${desired}"; fi
    done < <("$KUBECTL_BIN" get statefulsets -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.spec.replicas}{"|"}{.status.readyReplicas}{"\n"}{end}' 2>/dev/null)
}

check_daemonsets() {
    local namespace name desired available
    while IFS='|' read -r namespace name desired available; do
        [ -n "$name" ] || continue
        is_ignored_namespace "$namespace" && continue
        desired="${desired:-0}"; available="${available:-0}"
        [ "$desired" -eq 0 ] && continue
        if [ "$available" -lt "$desired" ]; then warn "DaemonSet ${namespace}/${name}: available=${available}/${desired}"
        else ok "DaemonSet ${namespace}/${name}: available=${available}/${desired}"; fi
    done < <("$KUBECTL_BIN" get daemonsets -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.status.desiredNumberScheduled}{"|"}{.status.numberAvailable}{"\n"}{end}' 2>/dev/null)
}

check_pods() {
    local namespace name phase waiting restarts restart_count
    while IFS='|' read -r namespace name phase waiting restarts; do
        [ -n "$name" ] || continue
        is_ignored_namespace "$namespace" && continue
        restart_count="$(awk '{ total=0; for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+$/) total += $i; print total }' <<< "${restarts//,/ }")"
        case "$phase" in
            Failed|Unknown) crit "Pod ${namespace}/${name}: phase=${phase}" ;;
            Pending) warn "Pod ${namespace}/${name}: Pending" ;;
            *) ok "Pod ${namespace}/${name}: ${phase}" ;;
        esac
        case "$waiting" in
            *CrashLoopBackOff*|*ImagePullBackOff*|*ErrImagePull*|*CreateContainerConfigError*|*OOMKilled*) crit "Pod ${namespace}/${name}: ${waiting}" ;;
        esac
        if [ "$restart_count" -ge "$K8S_RESTART_WARN" ]; then
            warn "Pod ${namespace}/${name}: restart count=${restart_count}"
        fi
    done < <("$KUBECTL_BIN" get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.status.phase}{"|"}{.status.containerStatuses[*].state.waiting.reason}{"|"}{.status.containerStatuses[*].restartCount}{"\n"}{end}' 2>/dev/null)
}

check_workloads() {
    section "WORKLOADS"
    if [ "$K8S_API_AVAILABLE" -ne 1 ]; then
        skip "Kubernetes API unavailable; workload check not run"
        return
    fi
    check_deployments
    check_statefulsets
    check_daemonsets
    check_pods
}
