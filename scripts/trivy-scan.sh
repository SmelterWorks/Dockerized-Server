#!/usr/bin/env bash
set -euo pipefail

IMAGE="${SMOKE_IMAGE:?SMOKE_IMAGE is required}"
TRIVY_CACHE_DIR="${TRIVY_CACHE_DIR:-${RUNNER_TEMP:-/tmp}/trivy-cache}"
REPORT_PATH="${TRIVY_REPORT_PATH:-trivy-report.json}"

mkdir -p "${TRIVY_CACHE_DIR}"

trivy image \
  --cache-dir "${TRIVY_CACHE_DIR}" \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 0 \
  --format json \
  --output "${REPORT_PATH}" \
  "${IMAGE}"

count="$(jq '[.Results[]? | .Vulnerabilities[]?] | length' "${REPORT_PATH}")"
if [ "${count}" -eq 0 ]; then
  summary="clean"
else
  summary="${count} HIGH/CRITICAL"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "count=${count}"
    echo "summary=${summary}"
  } >> "${GITHUB_OUTPUT}"
fi

trivy image \
  --cache-dir "${TRIVY_CACHE_DIR}" \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 0 \
  --format table \
  "${IMAGE}"

echo "trivy report written to ${REPORT_PATH} (${summary})"

if [ "${count}" -gt 0 ]; then
  exit 1
fi
