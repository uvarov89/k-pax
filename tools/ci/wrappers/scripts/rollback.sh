#!/usr/bin/env bash
# Usage: kpax-ci rollback [backup_dirname]
set -euo pipefail
panel=$(bash "$(dirname "$0")/panel_locate.sh" | head -1)
dir=$(dirname "$panel")
name="${1:-}"
if [[ -n "$name" ]]; then
  src="/var/backups/k-pax-ci/$name"
else
  src=$(ls -1dt /var/backups/k-pax-ci/pre-deploy-* 2>/dev/null | head -1 || true)
fi
[[ -n "$src" && -d "$src" ]] || { echo "STATUS=FAIL no backup"; exit 1; }
stamp=$(date -u +%Y%m%dT%H%MZ)
mkdir -p /var/backups/k-pax-ci
cp -a "$dir" "/var/backups/k-pax-ci/pre-rollback-${stamp}"
rsync -a --delete "$src/" "$dir/"
systemctl restart k-pax
sleep 2
systemctl is-active k-pax
echo "STATUS=OK rollback from=$src"
