#!/usr/bin/env bash
set -euo pipefail
for p in /opt/k-pax/panel.py /usr/local/lib/k-pax/panel.py /home/kpax/panel.py; do
  if [[ -f "$p" ]]; then
    echo "$p"
    echo "STATUS=OK"
    exit 0
  fi
done
echo "STATUS=FAIL panel.py not found"
exit 1
