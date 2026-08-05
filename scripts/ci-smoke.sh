#!/usr/bin/env bash
set -euo pipefail

IMAGE="${SMOKE_IMAGE:?SMOKE_IMAGE is required}"
NAME="vs-smoke-$$"
WORKDIR="$(mktemp -d)"
cleanup() {
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
  # Data is owned by uid 65532 inside the bind mount.
  docker run --rm -v "${WORKDIR}:/work" alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce \
    rm -rf /work/data /work/mods /work/backups >/dev/null 2>&1 || true
  rm -rf "${WORKDIR}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${WORKDIR}/data" "${WORKDIR}/mods" "${WORKDIR}/backups"

docker run -d --name "${NAME}" --init \
  --read-only \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add SETUID \
  --cap-add SETGID \
  --cap-add DAC_OVERRIDE \
  --cap-add FOWNER \
  --tmpfs /tmp:mode=1777,size=64m \
  -e VS_BACKUP_ENABLED=false \
  -e VS_BACKUP_ON_SHUTDOWN=false \
  -e VS_MAX_CLIENTS=4 \
  -v "${WORKDIR}/data:/data" \
  -v "${WORKDIR}/mods:/mods:ro" \
  -v "${WORKDIR}/backups:/backups" \
  "${IMAGE}"

echo "waiting for healthcheck"
ok=0
for _ in $(seq 1 60); do
  if docker exec "${NAME}" /usr/local/bin/healthcheck.sh >/dev/null 2>&1; then
    ok=1
    break
  fi
  if ! docker ps -q -f "name=^/${NAME}$" | grep -q .; then
    echo "container exited before becoming healthy" >&2
    docker logs "${NAME}" >&2 || true
    exit 1
  fi
  sleep 3
done

if [ "${ok}" != "1" ]; then
  echo "healthcheck timed out" >&2
  docker logs "${NAME}" >&2 || true
  exit 1
fi

echo "checking process uid"
uid="$(docker exec "${NAME}" bash -c 'awk "/^Uid:/{print \$2; exit}" /proc/$(pgrep -n dotnet)/status')"
if [ "${uid}" != "65532" ]; then
  echo "expected dotnet uid 65532, got ${uid}" >&2
  exit 1
fi

echo "running backup"
docker exec "${NAME}" /usr/local/bin/backup.sh
backup_count="$(find "${WORKDIR}/backups" -name 'vs-backup-*.tar.gz' | wc -l)"
if [ "${backup_count}" -lt 1 ]; then
  echo "expected at least one backup archive" >&2
  exit 1
fi

echo "stopping"
docker stop -t 60 "${NAME}" >/dev/null

echo "smoke ok"
