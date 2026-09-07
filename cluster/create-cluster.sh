#!/usr/bin/env bash
# Create the local multi-node kind cluster for this exercise.
# Idempotent: re-running it when the cluster already exists is a no-op.
set -euo pipefail

CLUSTER_NAME="w3w-exercise"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/kind-config.yaml"

for bin in docker kind kubectl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is not installed or not on PATH" >&2; exit 1; }
done

docker info >/dev/null 2>&1 || { echo "error: Docker daemon is not reachable" >&2; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "cluster '${CLUSTER_NAME}' already exists — nothing to do"
else
  echo "creating cluster '${CLUSTER_NAME}' from ${CONFIG#"${SCRIPT_DIR}/"} ..."
  kind create cluster --config "${CONFIG}"
fi

echo "waiting for all nodes to be Ready ..."
kubectl --context "kind-${CLUSTER_NAME}" wait --for=condition=Ready nodes --all --timeout=120s

echo
kubectl --context "kind-${CLUSTER_NAME}" get nodes -o wide
echo
echo "kubectl context is now 'kind-${CLUSTER_NAME}'."
echo "Load the app image after building it:  kind load docker-image greeter:<tag> --name ${CLUSTER_NAME}"
