#!/usr/bin/env bash

kubectl_ready() {
    command -v "$KUBECTL_BIN" >/dev/null 2>&1 && "$KUBECTL_BIN" version --request-timeout="${K8S_API_TIMEOUT_SECONDS}s" >/dev/null 2>&1
}

check_api_server() {
    section "API SERVER & ETCD"

    if ! command -v "$KUBECTL_BIN" >/dev/null 2>&1; then
        crit "kubectl not found (KUBECTL_BIN=${KUBECTL_BIN})"
        return
    fi
    if ! kubectl_ready; then
        crit "Cannot authenticate to Kubernetes API within ${K8S_API_TIMEOUT_SECONDS}s"
        return
    fi
    if "$KUBECTL_BIN" get --raw='/readyz' --request-timeout="${K8S_API_TIMEOUT_SECONDS}s" >/dev/null 2>&1; then
        K8S_API_AVAILABLE=1
        ok "API server /readyz is healthy"
    else
        crit "API server /readyz failed (API or etcd may be unavailable)"
    fi
}
