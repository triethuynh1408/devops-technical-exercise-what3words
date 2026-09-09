#!/usr/bin/env bash
# Continuous request load against a URL. One line per request:
#   <ISO8601> seq=<n> code=<http_status> t=<seconds> <OK|FAIL>
# Prints a summary (totals, breakdown by code, every non-2xx line) when it
# finishes: either after <max_requests>, or on SIGINT/SIGTERM.
#
# Portable to macOS's stock bash 3.2 — no associative arrays.
#
# Usage: scripts/soak.sh <url> [interval_seconds] [max_requests]
#   scripts/soak.sh 'http://localhost:8080/' 0.1 600
set -uo pipefail

URL="${1:?usage: soak.sh <url> [interval_seconds] [max_requests]}"
INTERVAL="${2:-0.1}"
MAX="${3:-0}" # 0 = run until signalled

TMP="$(mktemp -t soak.XXXXXX)"
trap 'rm -f "${TMP}"' EXIT

total=0

summary() {
  echo
  echo "==== soak summary: ${URL} ===="
  echo "requests: ${total}"
  echo "by code:"
  awk '{ for (i=1;i<=NF;i++) if ($i ~ /^code=/) { split($i,a,"="); c[a[2]]++ } }
       END { for (k in c) printf "  %s: %d\n", k, c[k] }' "${TMP}" | sort
  n=$(grep -c ' FAIL$' "${TMP}" || true)
  if [ "${n}" -eq 0 ]; then
    echo "non-2xx: none"
  else
    echo "non-2xx (${n}):"
    grep ' FAIL$' "${TMP}" | sed 's/^/  /'
  fi
}
trap 'summary; exit 0' INT TERM

while true; do
  total=$((total + 1))
  read -r code t < <(curl -s -o /dev/null -m 5 -w '%{http_code} %{time_total}' "${URL}" 2>/dev/null || echo "000 0")
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ "${code}" =~ ^2 ]]; then verdict="OK"; else verdict="FAIL"; fi
  line="${ts} seq=${total} code=${code} t=${t} ${verdict}"
  echo "${line}"
  echo "${line}" >> "${TMP}"
  if [ "${MAX}" -gt 0 ] && [ "${total}" -ge "${MAX}" ]; then
    summary
    exit 0
  fi
  sleep "${INTERVAL}"
done
