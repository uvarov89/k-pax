#!/usr/bin/env bash
set -euo pipefail
cfg=""
for p in /etc/sing-box/config.json /usr/local/etc/sing-box/config.json; do
  if [[ -f "$p" ]]; then cfg="$p"; break; fi
done
if [[ -z "$cfg" ]]; then
  echo "STATUS=FAIL no sing-box config"
  exit 1
fi
if ! command -v sing-box >/dev/null; then
  echo "STATUS=FAIL sing-box binary missing"
  exit 1
fi
if sing-box check -c "$cfg"; then
  echo "validate ok $cfg"
  echo "STATUS=OK"
else
  echo "STATUS=FAIL sing-box check"
  exit 1
fi
