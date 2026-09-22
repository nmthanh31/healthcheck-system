#!/usr/bin/env bash

# Shared runtime, logging and numerical helpers. This file is sourced by the
# entry point; it is not intended to be executed directly.

WARN_COUNT=0
CRIT_COUNT=0
SKIP_COUNT=0
ALERT_LINES=()
SKIP_LINES=()
CATEGORY_ORDER=()
CURRENT_SECTION="General"
declare -A CATEGORY_SEEN=()
declare -A CATEGORY_LEVEL=()

register_category() {
    local category="$1"
    if [ -z "${CATEGORY_SEEN[$category]+present}" ]; then
        CATEGORY_SEEN["$category"]=1
        CATEGORY_LEVEL["$category"]="OK"
        CATEGORY_ORDER+=("$category")
    fi
}

mark_category() {
    local level="$1" category="$CURRENT_SECTION"
    register_category "$category"
    # CRITICAL luôn được ưu tiên hơn WARNING cho cùng một nhóm.
    if [ "$level" = "CRITICAL" ] || [ "${CATEGORY_LEVEL[$category]}" = "OK" ]; then
        CATEGORY_LEVEL["$category"]="$level"
    fi
}

mkdir_safe() {
    mkdir -p "$1" 2>/dev/null
}

initialize_runtime() {
    if ! mkdir_safe "$HC_LOG_DIR" || ! mkdir_safe "$HC_STATE_DIR"; then
        echo "ERROR: cannot create ${HC_LOG_DIR} or ${HC_STATE_DIR}. Run as root or override HC_LOG_DIR/HC_STATE_DIR." >&2
        return 2
    fi

    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: cannot write log file: $LOG_FILE" >&2
        return 2
    }
}

# Thu thập kết quả trong lúc chạy để file log cuối cùng ngắn, dễ đọc.
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }
ok() {
    register_category "$CURRENT_SECTION"
    # Nếu một phần tùy chọn bị bỏ qua nhưng một phần khác của nhóm chạy tốt,
    # nhóm đó vẫn được xem là OK.
    [ "${CATEGORY_LEVEL[$CURRENT_SECTION]}" = "SKIPPED" ] && CATEGORY_LEVEL["$CURRENT_SECTION"]="OK"
}
info() { register_category "$CURRENT_SECTION"; }
section() {
    CURRENT_SECTION="$1"
    register_category "$CURRENT_SECTION"
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

float_ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }
float_gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }
percent() { awk -v n="$1" -v d="$2" 'BEGIN { if (d <= 0) print "0.00"; else printf "%.2f", (n/d)*100 }'; }

human_kib() {
    awk -v k="$1" 'BEGIN {
        if (k >= 1073741824) printf "%.2f TiB", k/1073741824;
        else if (k >= 1048576) printf "%.2f GiB", k/1048576;
        else if (k >= 1024) printf "%.2f MiB", k/1024;
        else printf "%.0f KiB", k;
    }'
}

history_average() {
    local col="$1"
    [ -f "$HISTORY_FILE" ] || return 1
    tail -n "$BASELINE_DAYS" "$HISTORY_FILE" 2>/dev/null | awk -F, -v c="$col" '
        $c ~ /^[0-9]+([.][0-9]+)?$/ { sum += $c; n++ }
        END { if (n > 0) printf "%.2f %d", sum/n, n; else exit 1 }
    '
}

baseline_check() {
    local label="$1" current="$2" col="$3" result avg samples warn_limit crit_limit

    if ! result="$(history_average "$col" 2>/dev/null)"; then
        info "$label=$current (baseline not ready)"
        return
    fi
    avg="${result%% *}"
    samples="${result##* }"
    if [ "$samples" -lt "$BASELINE_MIN_SAMPLES" ]; then
        info "$label=$current; baseline=${avg} from ${samples} samples (need >= ${BASELINE_MIN_SAMPLES})"
        return
    fi
    warn_limit="$(awk -v a="$avg" -v f="$BASELINE_WARN_FACTOR" 'BEGIN { printf "%.2f", a*f }')"
    crit_limit="$(awk -v a="$avg" -v f="$BASELINE_CRIT_FACTOR" 'BEGIN { printf "%.2f", a*f }')"
    if float_ge "$current" "$crit_limit" && float_gt "$current" 0; then
        crit "$label=$current, >= ${BASELINE_CRIT_FACTOR}x baseline ${avg} (${samples} samples)"
    elif float_ge "$current" "$warn_limit" && float_gt "$current" 0; then
        warn "$label=$current, >= ${BASELINE_WARN_FACTOR}x baseline ${avg} (${samples} samples)"
    else
        ok "$label=$current; baseline=${avg} (${samples} samples)"
    fi
}

persist_history() {
    local tmp_history
    [ -f "$HISTORY_FILE" ] || : > "$HISTORY_FILE"
    tmp_history="$(mktemp)"
    grep -v "^${TODAY}," "$HISTORY_FILE" 2>/dev/null > "$tmp_history" || true
    printf '%s,%s,%s,%s\n' "$TODAY" "$PROCESS_COUNT" "$THREAD_COUNT" "$LOG_ERRORS" >> "$tmp_history"
    tail -n 30 "$tmp_history" > "$HISTORY_FILE"
    rm -f "$tmp_history"
}

print_summary_and_exit() {
    local result exit_code=0 item category level

    if [ "$CRIT_COUNT" -gt 0 ]; then
        result="CRITICAL"
        exit_code=2
    elif [ "$WARN_COUNT" -gt 0 ]; then
        result="WARNING"
        exit_code=1
    else
        result="HEALTHY"
    fi

    printf '\n' >> "$LOG_FILE"
    log "===================================================================="
    log "LINUX HEALTH CHECK REPORT"
    log "===================================================================="
    log "Host      : $HOST"
    log "Checked at: $NOW"
    log "Result    : $result"
    log "Warnings  : $WARN_COUNT"
    log "Criticals : $CRIT_COUNT"
    log "Skipped   : $SKIP_COUNT"

    log ""
    log "CHECK STATUS:"
    for category in "${CATEGORY_ORDER[@]}"; do
        level="${CATEGORY_LEVEL[$category]}"
        printf '[%s] %-10s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$category" | tee -a "$LOG_FILE"
    done

    if [ "${#ALERT_LINES[@]}" -gt 0 ]; then
        log ""
        log "ISSUES REQUIRING ATTENTION:"
        for item in "${ALERT_LINES[@]}"; do
            log "  ${item}"
        done
    else
        log ""
        log "No warnings or critical issues detected."
    fi

    if [ "${#SKIP_LINES[@]}" -gt 0 ]; then
        log ""
        log "OPTIONAL CHECKS SKIPPED:"
        for item in "${SKIP_LINES[@]}"; do
            log "  - ${item}"
        done
    fi

    log "Log file  : $LOG_FILE"
    return "$exit_code"
}
