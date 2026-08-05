#!/bin/bash
set -euo pipefail

VS_DATA_PATH="${VS_DATA_PATH:-/data}"
VS_BACKUP_PATH="${VS_BACKUP_PATH:-/backups}"
VS_BACKUP_RETENTION="${VS_BACKUP_RETENTION:-24}"

mkdir -p "${VS_BACKUP_PATH}"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="${VS_BACKUP_PATH}/.vs-backup-${stamp}.tar.gz.partial"
out="${VS_BACKUP_PATH}/vs-backup-${stamp}.tar.gz"

includes=()
for name in Saves Playerdata Mods serverconfig.json; do
  if [ -e "${VS_DATA_PATH}/${name}" ]; then
    includes+=("${name}")
  fi
done

if [ "${#includes[@]}" -eq 0 ]; then
  echo "backup skipped: nothing to archive under ${VS_DATA_PATH}" >&2
  exit 0
fi

# Best-effort filesystem snapshot. Prefer stopping the server or using in-game
# /genbackup when you need a guaranteed consistent world dump.
tar -czf "${tmp}" -C "${VS_DATA_PATH}" "${includes[@]}"

mv "${tmp}" "${out}"
echo "wrote ${out}"

mapfile -t old < <(ls -1t "${VS_BACKUP_PATH}"/vs-backup-*.tar.gz 2>/dev/null | tail -n +"$((VS_BACKUP_RETENTION + 1))" || true)
if [ "${#old[@]}" -gt 0 ]; then
  rm -f "${old[@]}"
fi
