#!/usr/bin/env bash

# Linux Server Health Check
#
# File này chỉ điều phối các bước kiểm tra. Cấu hình nằm tại
# config/defaults.sh; mỗi nhóm kiểm tra nằm trong checks/.

set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Thông tin của lần chạy hiện tại.
HOST="$(hostname -f 2>/dev/null || hostname)"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"
TODAY="$(date '+%Y-%m-%d')"

# shellcheck source=config/defaults.sh
source "${SCRIPT_DIR}/config/defaults.sh"
# shellcheck source=config/targets.conf
source "${SCRIPT_DIR}/config/targets.conf"
LOG_FILE="${HC_LOG_DIR}/healthcheck-${TODAY}.log"
HISTORY_FILE="${HC_STATE_DIR}/history.csv"
NET_STATE_FILE="${HC_STATE_DIR}/network.state"

# Values populated by checks and written to the daily baseline.
PROCESS_COUNT=0
THREAD_COUNT=0
LOG_ERRORS=0

# shellcheck source=lib/core.sh
source "${SCRIPT_DIR}/lib/core.sh"
for module in "${SCRIPT_DIR}"/checks/*.sh; do
    # shellcheck source=/dev/null
    source "$module"
done

main() {
    initialize_runtime || return $?

    check_cpu_iowait
    check_load_average
    check_memory
    check_filesystem
    check_disk_io
    check_network
    check_file_descriptors
    check_processes
    check_hardware
    check_system_logs
    check_platform_operations
    check_application_services

    persist_history
    print_summary_and_exit
}

main
