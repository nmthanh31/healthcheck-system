#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TODAY="$(date '+%Y-%m-%d')"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

source "${SCRIPT_DIR}/config/defaults.sh"
source "${SCRIPT_DIR}/config/targets.conf"

# Tự nhận RKE2 nếu cron chạy bằng root trên control-plane node.
if [ -z "${KUBECONFIG:-}" ] && [ -r /etc/rancher/rke2/rke2.yaml ]; then
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
fi
if ! command -v "$KUBECTL_BIN" >/dev/null 2>&1 && [ -x /var/lib/rancher/rke2/bin/kubectl ]; then
    KUBECTL_BIN=/var/lib/rancher/rke2/bin/kubectl
fi

LOG_FILE="${K8S_LOG_DIR}/kubernetes-healthcheck-${TODAY}.log"
K8S_CLUSTER_NAME="${K8S_CLUSTER_NAME:-$(hostname -s)}"
K8S_API_AVAILABLE=0

source "${SCRIPT_DIR}/lib/core.sh"
for module in "${SCRIPT_DIR}"/checks/*.sh; do source "$module"; done

main() {
    initialize_runtime || return $?
    check_api_server || true
    check_nodes || true
    check_workloads || true
    check_storage || true
    check_batch_and_events || true
    print_summary_and_exit
}

main
