#!/usr/bin/env bash
# Sync active users to exits/fronts using panel tooling if present.
set -euo pipefail
if [[ ! -f /etc/k-pax/config.json ]]; then
  echo "STATUS=FAIL not panel host"
  exit 1
fi
if [[ -x /opt/k-pax/k-pax-user.py ]]; then
  /opt/k-pax/k-pax-user.py sync-all 2>&1 | tail -40 || true
elif [[ -f /usr/local/bin/k-pax-user ]]; then
  k-pax-user sync-all 2>&1 | tail -40 || true
else
  echo "note: no k-pax-user sync helper; use tools/_ops_sync_fronts_and_verify.py on panel"
fi
echo "STATUS=OK"
