#!/usr/bin/env bash
# Extension D, part 2: roll every pod while the service is under continuous load
# and record that no request was dropped.
#
# Trigger is `kubectl rollout restart` — the same rolling-update path
# (maxUnavailable:0 / maxSurge:1 + readiness + grace period) a config change
# through Terraform would take, without mutating any config. The load generator
# runs for a fixed count and stops itself.
#
# Transcript -> evidence/rolling-update.log
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="greeter-dev"
URL="http://localhost:8080/"
REQUESTS=140         # ~90s at 0.1s + tiny latency; covers the whole rollout
OUT="${REPO_ROOT}/evidence/rolling-update.log"
SOAK_LOG="$(mktemp -t soak.XXXXXX)"
mkdir -p "${REPO_ROOT}/evidence"

{
  echo "### rolling update under load — $(date -u +%FT%TZ)"
  echo

  echo "--- pods before ---"
  kubectl -n "${NS}" get pods -o wide
  echo

  echo "--- load: ${REQUESTS} requests to ${URL}, rollout fires after ~5s ---"
  bash "${REPO_ROOT}/scripts/soak.sh" "${URL}" 0.1 "${REQUESTS}" > "${SOAK_LOG}" 2>&1 &
  SOAK=$!
  sleep 5

  echo "--- rollout start $(date -u +%FT%TZ) ---"
  kubectl -n "${NS}" rollout restart deployment/greeter-dev
  kubectl -n "${NS}" rollout status deployment/greeter-dev --timeout=180s
  echo "--- rollout complete $(date -u +%FT%TZ) ---"
  kubectl -n "${NS}" get pods -o wide
  echo

  echo "--- waiting for the load run to finish ---"
  wait "${SOAK}"

  echo
  echo "================ soak log (every request) ================"
  cat "${SOAK_LOG}"
  echo "### done"
} 2>&1 | tee "${OUT}"

rm -f "${SOAK_LOG}"
