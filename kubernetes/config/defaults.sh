#!/usr/bin/env bash

# Có thể ghi đè bằng biến môi trường khi cần.
K8S_LOG_DIR="${K8S_LOG_DIR:-/var/log/kubernetes-healthcheck}"
K8S_API_TIMEOUT_SECONDS="${K8S_API_TIMEOUT_SECONDS:-15}"
K8S_RESTART_WARN="${K8S_RESTART_WARN:-5}"
K8S_EVENT_MAX_AGE_HOURS="${K8S_EVENT_MAX_AGE_HOURS:-24}"
K8S_EVENT_WARN_LIMIT="${K8S_EVENT_WARN_LIMIT:-0}"
K8S_ETCDCTL_BIN="${K8S_ETCDCTL_BIN:-/usr/local/bin/etcdctl}"
K8S_ETCD_JOURNAL_TAG="${K8S_ETCD_JOURNAL_TAG:-etcd_backup}"

# RKE2 đặt kubectl và kubeconfig ở các vị trí này. Nếu không phải RKE2,
# truyền KUBECONFIG và KUBECTL_BIN từ môi trường hoặc sửa targets.conf.
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
