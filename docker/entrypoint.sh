#!/bin/bash
set -euo pipefail

APP_UID="${APP_UID:-65532}"
APP_GID="${APP_GID:-65532}"
VS_DATA_PATH="${VS_DATA_PATH:-/data}"
VS_MODS_PATH="${VS_MODS_PATH:-/mods}"
VS_BACKUP_PATH="${VS_BACKUP_PATH:-/backups}"
VS_PORT="${VS_PORT:-42420}"
VS_MAX_CLIENTS="${VS_MAX_CLIENTS:-16}"
VS_BACKUP_ENABLED="${VS_BACKUP_ENABLED:-true}"
VS_BACKUP_ON_SHUTDOWN="${VS_BACKUP_ON_SHUTDOWN:-true}"
SERVER_DIR="/opt/vintagestory"

if [ "$(id -u)" = "0" ]; then
  mkdir -p "${VS_DATA_PATH}" "${VS_MODS_PATH}" "${VS_BACKUP_PATH}" /tmp/vs
  chown -R "${APP_UID}:${APP_GID}" "${VS_DATA_PATH}" "${VS_BACKUP_PATH}" /tmp/vs
  # Mods may be bind-mounted read-only. Own only when writable.
  if [ -w "${VS_MODS_PATH}" ]; then
    chown -R "${APP_UID}:${APP_GID}" "${VS_MODS_PATH}" || true
  fi
  exec setpriv \
    --reuid="${APP_UID}" \
    --regid="${APP_GID}" \
    --init-groups \
    --inh-caps=-all \
    --no-new-privs \
    -- "$0" "$@"
fi

mkdir -p \
  "${VS_DATA_PATH}/Saves" \
  "${VS_DATA_PATH}/Playerdata" \
  "${VS_DATA_PATH}/Mods" \
  "${VS_DATA_PATH}/Logs" \
  "${VS_BACKUP_PATH}" \
  /tmp/vs

BACKUP_PID=""
SERVER_PID=""

shutdown_handler() {
  trap - TERM INT
  if [ -n "${SERVER_PID}" ] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -TERM "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  if [ -n "${BACKUP_PID}" ] && kill -0 "${BACKUP_PID}" 2>/dev/null; then
    kill -TERM "${BACKUP_PID}" 2>/dev/null || true
    wait "${BACKUP_PID}" 2>/dev/null || true
  fi
  case "${VS_BACKUP_ON_SHUTDOWN}" in
    1|true|TRUE|yes|YES)
      /usr/local/bin/backup.sh || true
      ;;
  esac
  exit 0
}

trap shutdown_handler TERM INT

case "${VS_BACKUP_ENABLED}" in
  1|true|TRUE|yes|YES)
    (
      # Stagger the first timed backup so startup is not competing for disk.
      sleep "${VS_BACKUP_INTERVAL_SEC:-3600}"
      while true; do
        /usr/local/bin/backup.sh || true
        sleep "${VS_BACKUP_INTERVAL_SEC:-3600}"
      done
    ) &
    BACKUP_PID=$!
    ;;
esac

ARGS=(
  --dataPath "${VS_DATA_PATH}"
  --addModPath "${VS_MODS_PATH}"
  --port "${VS_PORT}"
  --maxclients "${VS_MAX_CLIENTS}"
)

# shellcheck disable=SC2206
if [ -n "${VS_EXTRA_ARGS:-}" ]; then
  EXTRA=( ${VS_EXTRA_ARGS} )
  ARGS+=("${EXTRA[@]}")
fi

if [ "$#" -gt 0 ]; then
  ARGS+=("$@")
fi

cd "${SERVER_DIR}"
dotnet "${SERVER_DIR}/VintagestoryServer.dll" "${ARGS[@]}" &
SERVER_PID=$!
wait "${SERVER_PID}"
EXIT_CODE=$?

if [ -n "${BACKUP_PID}" ] && kill -0 "${BACKUP_PID}" 2>/dev/null; then
  kill -TERM "${BACKUP_PID}" 2>/dev/null || true
  wait "${BACKUP_PID}" 2>/dev/null || true
fi

case "${VS_BACKUP_ON_SHUTDOWN}" in
  1|true|TRUE|yes|YES)
    /usr/local/bin/backup.sh || true
    ;;
esac

exit "${EXIT_CODE}"
