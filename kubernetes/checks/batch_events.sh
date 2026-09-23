#!/usr/bin/env bash

check_failed_jobs() {
    local namespace name failed
    while IFS='|' read -r namespace name failed; do
        [ -n "$name" ] || continue
        is_ignored_namespace "$namespace" && continue
        failed="${failed:-0}"
        if [ "$failed" -gt 0 ]; then warn "Job ${namespace}/${name}: failed=${failed}"
        else ok "Job ${namespace}/${name}: no failures"; fi
    done < <("$KUBECTL_BIN" get jobs -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.status.failed}{"\n"}{end}' 2>/dev/null)
}

check_recent_warning_events() {
    local timestamp namespace reason object count=0 newest=""
    local now event_epoch age_seconds
    now="$(date +%s)"
    while IFS='|' read -r timestamp namespace reason object; do
        [ -n "$timestamp" ] || continue
        event_epoch="$(date -d "$timestamp" +%s 2>/dev/null || echo 0)"
        age_seconds=$((now - event_epoch))
        [ "$event_epoch" -gt 0 ] && [ "$age_seconds" -le $((K8S_EVENT_MAX_AGE_HOURS * 3600)) ] || continue
        count=$((count + 1))
        [ -z "$newest" ] && newest="${namespace}: ${reason} on ${object}"
    done < <("$KUBECTL_BIN" get events -A --field-selector type=Warning -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"|"}{.metadata.namespace}{"|"}{.reason}{"|"}{.involvedObject.kind}{"/"}{.involvedObject.name}{"\n"}{end}' 2>/dev/null)

    if [ "$count" -gt "$K8S_EVENT_WARN_LIMIT" ]; then
        warn "${count} warning event(s) in last ${K8S_EVENT_MAX_AGE_HOURS}h; newest: ${newest}"
    else
        ok "No warning events above configured threshold"
    fi
}

check_batch_and_events() {
    section "BATCH JOBS & EVENTS"
    if [ "$K8S_API_AVAILABLE" -ne 1 ]; then
        skip "Kubernetes API unavailable; batch/event check not run"
        return
    fi
    check_failed_jobs
    check_recent_warning_events
}
