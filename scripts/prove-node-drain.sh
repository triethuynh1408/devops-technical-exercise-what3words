#!/usr/bin/env bash
# Extension D, part 1: drain a worker node while the service is under continuous
# load, and record what happened to in-flight and new requests.
#
# Load hits /work?ms=500 so every request is genuinely in flight for 500ms;
# some are mid-request when their pod is evicted. The load generator runs for a
# fixed count and stops itself — nothing to kill.
#
# Transcript -> evidence/node-drain.log
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="greeter-dev"
URL="http://localhost:8080/work?ms=500"
REQUESTS=140          # ~120s at ~0.6s + 0.1s sleep per request
OUT="${REPO_ROOT}/evidence/node-drain.log"
SOAK_LOG="$(mktemp -t soak.XXXXXX)"
mkdir -p "${REPO_ROOT}/evidence"

{
  echo "### node drain under load — $(date -u +%FT%TZ)"
  echo

  echo "--- pods before ---"
  kubectl -n "${NS}" get pods -o wide
  TARGET=$(kubectl -n "${NS}" get pods -o jsonpath='{.items[0].spec.nodeName}')
  echo "target node to drain: ${TARGET}"
  echo

  echo "--- load: ${REQUESTS} requests to ${URL}, drain fires after ~10s ---"
  bash "${REPO_ROOT}/scripts/soak.sh" "${URL}" 0.1 "${REQUESTS}" > "${SOAK_LOG}" 2>&1 &
  SOAK=$!
  sleep 10

  echo "--- drain start $(date -u +%FT%TZ) ---"
  kubectl drain "${TARGET}" --ignore-daemonsets --delete-emptydir-data --timeout=120s
  echo "--- drain returned $(date -u +%FT%TZ) ---"
  kubectl -n "${NS}" get pods -o wide
  echo

  echo "--- wait for the deployment to be fully available again ---"
  kubectl -n "${NS}" rollout status deployment/greeter-dev --timeout=120s
  echo "--- available $(date -u +%FT%TZ) ---"
  kubectl -n "${NS}" get pods -o wide
  echo

  echo "--- waiting for the load run to finish ---"
  wait "${SOAK}"

  echo
  echo "--- uncordon ${TARGET} ---"
  kubectl uncordon "${TARGET}"
  echo

  echo "================ soak log (every request) ================"
  cat "${SOAK_LOG}"
  echo "### done"
} 2>&1 | tee "${OUT}"

rm -f "${SOAK_LOG}"
