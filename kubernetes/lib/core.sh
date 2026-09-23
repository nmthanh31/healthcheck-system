#!/usr/bin/env bash

WARN_COUNT=0
CRIT_COUNT=0
SKIP_COUNT=0
ALERT_LINES=()
SKIP_LINES=()
CATEGORY_ORDER=()
CURRENT_SECTION="General"
declare -A CATEGORY_SEEN=()
declare -A CATEGORY_LEVEL=()

initialize_runtime() {
    mkdir -p "$K8S_LOG_DIR" 2>/dev/null || {
        echo "ERROR: cannot create ${K8S_LOG_DIR}" >&2
        return 2
    }
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: cannot write ${LOG_FILE}" >&2
        return 2
    }
}

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

register_category() {
    local category="$1"
    if [ -z "${CATEGORY_SEEN[$category]+present}" ]; then
        CATEGORY_SEEN["$category"]=1
        CATEGORY_LEVEL["$category"]="OK"
        CATEGORY_ORDER+=("$category")
    fi
}

section() { CURRENT_SECTION="$1"; register_category "$CURRENT_SECTION"; }
ok() {
    register_category "$CURRENT_SECTION"
    [ "${CATEGORY_LEVEL[$CURRENT_SECTION]}" = "SKIPPED" ] && CATEGORY_LEVEL["$CURRENT_SECTION"]="OK"
}
info() { register_category "$CURRENT_SECTION"; }
mark_category() {
    local level="$1"
    register_category "$CURRENT_SECTION"
    if [ "$level" = "CRITICAL" ] || [ "${CATEGORY_LEVEL[$CURRENT_SECTION]}" = "OK" ]; then
        CATEGORY_LEVEL["$CURRENT_SECTION"]="$level"
    fi
}
warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    mark_category "WARNING"
    ALERT_LINES+=("[WARNING]  ${CURRENT_SECTION}: $*")
}
crit() {
    CRIT_COUNT=$((CRIT_COUNT + 1))
    mark_category "CRITICAL"
    ALERT_LINES+=("[CRITICAL] ${CURRENT_SECTION}: $*")
}
skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    register_category "$CURRENT_SECTION"
    [ "${CATEGORY_LEVEL[$CURRENT_SECTION]}" = "OK" ] && CATEGORY_LEVEL["$CURRENT_SECTION"]="SKIPPED"
    SKIP_LINES+=("${CURRENT_SECTION}: $*")
}

is_ignored_namespace() {
    local namespace="$1" ignored
    for ignored in "${K8S_IGNORED_NAMESPACES[@]}"; do
        [ "$namespace" = "$ignored" ] && return 0
    done
    return 1
}

print_summary_and_exit() {
    local result exit_code=0 item category level
    if [ "$CRIT_COUNT" -gt 0 ]; then result="CRITICAL"; exit_code=2
    elif [ "$WARN_COUNT" -gt 0 ]; then result="WARNING"; exit_code=1
    else result="HEALTHY"; fi

    printf '\n' >> "$LOG_FILE"
    log "===================================================================="
    log "KUBERNETES DAILY HEALTH REPORT"
    log "===================================================================="
    log "Cluster   : ${K8S_CLUSTER_NAME}"
    log "Checked at: ${NOW}"
    log "Result    : ${result}"
    log "Warnings  : ${WARN_COUNT}"
    log "Criticals : ${CRIT_COUNT}"
    log "Skipped   : ${SKIP_COUNT}"
    log ""
    log "CHECK STATUS:"
    for category in "${CATEGORY_ORDER[@]}"; do
        level="${CATEGORY_LEVEL[$category]}"
        printf '[%s] %-10s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$category" | tee -a "$LOG_FILE"
    done
    if [ "${#ALERT_LINES[@]}" -gt 0 ]; then
        log ""; log "ISSUES REQUIRING ATTENTION:"
        for item in "${ALERT_LINES[@]}"; do log "  ${item}"; done
    else
        log ""; log "No warnings or critical issues detected."
    fi
    if [ "${#SKIP_LINES[@]}" -gt 0 ]; then
        log ""; log "OPTIONAL CHECKS SKIPPED:"
        for item in "${SKIP_LINES[@]}"; do log "  - ${item}"; done
    fi
    log "Log file  : ${LOG_FILE}"
    return "$exit_code"
}
