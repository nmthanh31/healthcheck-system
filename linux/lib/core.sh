#!/usr/bin/env bash

# Shared runtime, logging and numerical helpers. This file is sourced by the
# entry point; it is not intended to be executed directly.

WARN_COUNT=0
CRIT_COUNT=0
SKIP_COUNT=0

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

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }
ok() { log "[OK]       $*"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); log "[WARNING]  $*"; }
crit() { CRIT_COUNT=$((CRIT_COUNT + 1)); log "[CRITICAL] $*"; }
skip() { SKIP_COUNT=$((SKIP_COUNT + 1)); log "[SKIP]     $*"; }
info() { log "[INFO]     $*"; }

section() {
    printf '\n' | tee -a "$LOG_FILE" >/dev/null
    log "===================================================================="
    log "$1"
    log "===================================================================="
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
    section "HEALTH CHECK SUMMARY"
    log "Host      : $HOST"
    log "Warnings  : $WARN_COUNT"
    log "Criticals : $CRIT_COUNT"
    log "Skipped   : $SKIP_COUNT"
    log "Log file  : $LOG_FILE"
    if [ "$CRIT_COUNT" -gt 0 ]; then log "RESULT    : CRITICAL"; return 2; fi
    if [ "$WARN_COUNT" -gt 0 ]; then log "RESULT    : WARNING"; return 1; fi
    log "RESULT    : HEALTHY"
    return 0
}
