#!/usr/bin/env bash
set -euo pipefail

TRIVY_VERSION="${TRIVY_VERSION:-0.73.0}"
TRIVY_ARCHIVE_SHA256="${TRIVY_ARCHIVE_SHA256:-2edd39da482bb4e9831962487b68f68e3928ec3137794757f54d00383d79547b}"
TRIVY_INSTALL_DIR="${TRIVY_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/trivy}"
TRIVY_BASE_URL="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
ARCHIVE="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
ARCHIVE_PATH="${TRIVY_INSTALL_DIR}/${ARCHIVE}"

mkdir -p "${TRIVY_INSTALL_DIR}"

curl -fsSL "${TRIVY_BASE_URL}/${ARCHIVE}" -o "${ARCHIVE_PATH}"
printf '%s  %s\n' "${TRIVY_ARCHIVE_SHA256}" "${ARCHIVE_PATH}" | sha256sum -c -

tar -xzf "${ARCHIVE_PATH}" -C "${TRIVY_INSTALL_DIR}" trivy
chmod 755 "${TRIVY_INSTALL_DIR}/trivy"

installed="$("${TRIVY_INSTALL_DIR}/trivy" version | awk '/^Version:/{print $2}')"
if [ "${installed}" != "${TRIVY_VERSION}" ]; then
  echo "expected trivy ${TRIVY_VERSION}, got ${installed}" >&2
  exit 1
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${TRIVY_INSTALL_DIR}" >> "${GITHUB_PATH}"
fi

echo "trivy ${installed} installed to ${TRIVY_INSTALL_DIR}"
