#!/usr/bin/env bash
# Apply staged candidate for an allowlisted kind.
# Usage: kpax-ci config-apply <kind> [--dry-run] [--deadman <minutes>]
set -euo pipefail
source "$(dirname "$0")/config_paths.sh"
kind="${1:?kind}"
shift
dry=0
deadman=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --deadman)
      deadman="${2:?}"
      shift 2
      ;;
    *) echo "STATUS=FAIL unknown arg $1"; exit 2 ;;
  esac
done

config_resolve "$kind" || exit $?
[[ -n "$CONFIG_PATH" ]] || { echo "STATUS=FAIL kind not applyable"; exit 2; }
cand="/tmp/kpax-ci-stage/$kind"
[[ -f "$cand" ]] || { echo "STATUS=FAIL missing candidate $cand"; exit 1; }

echo "=== config-apply kind=$kind dry=$dry deadman=$deadman ==="
if ! config_validate_file "$CONFIG_VALIDATOR" "$cand"; then
  echo "STATUS=FAIL validation"
  exit 1
fi
echo "validation=OK"

# Always show sanitized diff first
bash "$(dirname "$0")/config_diff.sh" "$kind" || true

if [[ "$dry" -eq 1 ]]; then
  echo "DRY_RUN=1 — no files written"
  echo "STATUS=OK"
  exit 0
fi

stamp=$(date -u +%Y%m%dT%H%MZ)
mkdir -p /var/backups/k-pax-ci
bak="/var/backups/k-pax-ci/config-${kind}-pre-${stamp}"
if [[ -f "$CONFIG_PATH" ]]; then
  cp -a "$CONFIG_PATH" "$bak"
  echo "backup=$bak"
else
  mkdir -p "$(dirname "$CONFIG_PATH")"
  # Sentinel so deadman/rollback can undo a first-time create
  printf '%s\n' '# kpax-ci-absent' >"$bak"
  echo "backup=$bak (was-absent)"
fi

# Atomic install
install -m 644 "$cand" "${CONFIG_PATH}.kpax-new"
mv -f "${CONFIG_PATH}.kpax-new" "$CONFIG_PATH"
rm -f "$cand"
echo "installed $CONFIG_PATH"

# Reload/restart only needed service
if [[ -n "$CONFIG_SERVICE" ]]; then
  if [[ "$CONFIG_VALIDATOR" == "unit" ]]; then
    systemctl daemon-reload
  fi
  systemctl restart "$CONFIG_SERVICE"
  systemctl is-active "$CONFIG_SERVICE"
  echo "restarted=$CONFIG_SERVICE"
fi

# Arm deadman for network-sensitive kinds (or explicit --deadman)
if [[ "$deadman" -eq 0 && "$CONFIG_DEADMAN_DEFAULT" -eq 1 ]]; then
  deadman=5
fi
if [[ "$deadman" -gt 0 ]]; then
  bash "$(dirname "$0")/deadman.sh" arm "$stamp" "$deadman" "$kind"
fi

echo "APPLY_STAMP=$stamp"
echo "STATUS=OK"
