#!/usr/bin/env bash
# Build the greeter image(s) and load them into the kind cluster.
#
# A prerequisite for deploying, whether with `helm` (Task 3) or `terraform`
# (Task 4): neither builds the image, and the kind cluster has no registry.
#
# Usage:
#   scripts/build-and-load.sh              # builds greeter:dev and greeter:1.0.0
#   scripts/build-and-load.sh 1.2.3        # builds only greeter:1.2.3
set -euo pipefail

CLUSTER_NAME="w3w-exercise"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$#" -gt 0 ]; then
  TAGS=("$@")
else
  TAGS=(dev 1.0.0)
fi

for bin in docker kind; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' not found" >&2; exit 1; }
done

IMAGES=()
for tag in "${TAGS[@]}"; do
  echo ">> building greeter:${tag}"
  # --provenance=false: a plain single-manifest image. The attestation manifest
  # BuildKit adds by default confuses `kind load docker-image`.
  docker build \
    --provenance=false --sbom=false \
    --build-arg "VERSION=${tag}" \
    -t "greeter:${tag}" \
    "${REPO_ROOT}"
  IMAGES+=("greeter:${tag}")
done

echo ">> loading into kind cluster '${CLUSTER_NAME}': ${IMAGES[*]}"
kind load docker-image "${IMAGES[@]}" --name "${CLUSTER_NAME}"
echo ">> done"
