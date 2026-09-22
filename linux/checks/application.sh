#!/usr/bin/env bash

check_systemd_services() {
    local service

    for service in "${HEALTH_SYSTEMD_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            ok "Service ${service} is active"
        else
            crit "Service ${service} is not active"
        fi
    done
}

check_http_endpoints() {
    local entry name url response status elapsed

    if [ "${#HEALTH_HTTP_ENDPOINTS[@]}" -eq 0 ]; then
        return
    fi
    if ! command -v curl >/dev/null 2>&1; then
        skip "curl missing; cannot check HTTP endpoints"
        return
    fi

    for entry in "${HEALTH_HTTP_ENDPOINTS[@]}"; do
        IFS='|' read -r name url <<< "$entry"
        response="$(curl --silent --show-error --location --max-time "$HEALTH_HTTP_CRIT_SECONDS" --output /dev/null --write-out '%{http_code}|%{time_total}' "$url" 2>&1)"

        if [[ "$response" != *"|"* ]]; then
            crit "HTTP ${name}: request failed (${response})"
            continue
        fi

        status="${response%%|*}"
        elapsed="${response##*|}"
        if [ "$status" -lt 200 ] || [ "$status" -ge 400 ]; then
            crit "HTTP ${name}: status=${status}, response=${elapsed}s"
        elif float_ge "$elapsed" "$HEALTH_HTTP_CRIT_SECONDS"; then
            crit "HTTP ${name}: slow response=${elapsed}s"
        elif float_ge "$elapsed" "$HEALTH_HTTP_WARN_SECONDS"; then
            warn "HTTP ${name}: slow response=${elapsed}s"
        else
            ok "HTTP ${name}: status=${status}, response=${elapsed}s"
        fi
    done
}

check_tcp_dependencies() {
    local entry name host port

    [ "${#HEALTH_TCP_TARGETS[@]}" -eq 0 ] && return
    if ! command -v nc >/dev/null 2>&1; then
        skip "nc missing; cannot check TCP dependencies"
        return
    fi

    for entry in "${HEALTH_TCP_TARGETS[@]}"; do
        IFS='|' read -r name host port <<< "$entry"
        if nc -z -w 5 "$host" "$port" >/dev/null 2>&1; then
            ok "TCP ${name}: ${host}:${port} reachable"
        else
            crit "TCP ${name}: ${host}:${port} unreachable"
        fi
    done
}

check_backup_freshness() {
    local entry name path max_age_hours modified_at current_time age_seconds max_age_seconds

    for entry in "${HEALTH_BACKUP_FILES[@]}"; do
        IFS='|' read -r name path max_age_hours <<< "$entry"
        if [ ! -e "$path" ]; then
            crit "Backup ${name}: success marker is missing (${path})"
            continue
        fi

        modified_at="$(stat -c '%Y' "$path" 2>/dev/null || true)"
        if [ -z "$modified_at" ]; then
            crit "Backup ${name}: cannot read timestamp (${path})"
            continue
        fi

        current_time="$(date +%s)"
        age_seconds=$((current_time - modified_at))
        max_age_seconds=$((max_age_hours * 3600))
        if [ "$age_seconds" -gt "$max_age_seconds" ]; then
            crit "Backup ${name}: last success is $(($age_seconds / 3600))h old (limit ${max_age_hours}h)"
        else
            ok "Backup ${name}: current"
        fi
    done
}

check_application_services() {
    section "APPLICATION & BACKUP"

    if [ "${#HEALTH_SYSTEMD_SERVICES[@]}" -eq 0 ] && [ "${#HEALTH_HTTP_ENDPOINTS[@]}" -eq 0 ] && [ "${#HEALTH_TCP_TARGETS[@]}" -eq 0 ] && [ "${#HEALTH_BACKUP_FILES[@]}" -eq 0 ]; then
        skip "No targets configured; edit config/targets.conf"
        return
    fi

    if [ -d /run/systemd/system ]; then
        check_systemd_services
    elif [ "${#HEALTH_SYSTEMD_SERVICES[@]}" -gt 0 ]; then
        skip "systemd is not available; cannot check configured services"
    fi
    check_http_endpoints
    check_tcp_dependencies
    check_backup_freshness
}
