#!/usr/bin/env bash
# Tear the cluster down. Safe to run when it doesn't exist.
set -euo pipefail

CLUSTER_NAME="w3w-exercise"
command -v kind >/dev/null 2>&1 || { echo "error: 'kind' is not installed" >&2; exit 1; }

kind delete cluster --name "${CLUSTER_NAME}"
