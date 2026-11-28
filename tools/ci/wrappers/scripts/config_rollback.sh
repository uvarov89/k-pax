#!/usr/bin/env bash
# Restore previous config for a kind.
# Usage: kpax-ci config-rollback <kind> [backup_basename]
set -euo pipefail
source "$(dirname "$0")/config_paths.sh"
kind="${1:?kind}"
name="${2:-}"
config_resolve "$kind" || exit $?
[[ -n "$CONFIG_PATH" ]] || { echo "STATUS=FAIL kind not rollbackable"; exit 2; }

if [[ -n "$name" ]]; then
  case "$name" in
    *[!a-zA-Z0-9._-]*) echo "STATUS=FAIL bad backup name"; exit 2 ;;
  esac
  bak="/var/backups/k-pax-ci/$name"
else
  bak=$(ls -1dt /var/backups/k-pax-ci/config-${kind}-pre-* 2>/dev/null | head -1 || true)
fi
[[ -n "$bak" && -f "$bak" ]] || { echo "STATUS=FAIL no config backup for $kind"; exit 1; }

echo "=== config-rollback kind=$kind from=$(basename "$bak") ==="
stamp=$(date -u +%Y%m%dT%H%MZ)
if [[ -f "$CONFIG_PATH" ]]; then
  cp -a "$CONFIG_PATH" "/var/backups/k-pax-ci/config-${kind}-pre-rollback-${stamp}"
fi

# Absent sentinel from first-create backup → remove live file
if [[ "$(head -1 "$bak" 2>/dev/null || true)" == "# kpax-ci-absent" ]]; then
  rm -f "$CONFIG_PATH"
  echo "restored-absent removed $CONFIG_PATH"
else
  if ! config_validate_file "$CONFIG_VALIDATOR" "$bak"; then
    echo "STATUS=FAIL backup failed validation — refuse restore"
    exit 1
  fi
  install -m 644 "$bak" "${CONFIG_PATH}.kpax-new"
  mv -f "${CONFIG_PATH}.kpax-new" "$CONFIG_PATH"
fi

if [[ -n "$CONFIG_SERVICE" ]]; then
  if [[ "$CONFIG_VALIDATOR" == "unit" ]]; then
    systemctl daemon-reload
  fi
  systemctl restart "$CONFIG_SERVICE"
  systemctl is-active "$CONFIG_SERVICE"
fi
echo "STATUS=OK rollback kind=$kind"
