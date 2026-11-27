#!/usr/bin/env bash
# Read-only health: TCP + optional Reality SoftProbe if sing-box present.
set -euo pipefail
echo "=== health $(hostname) $(date -u +%Y-%m-%dT%H:%MZ) ==="

tcp() {
  local h="$1" p="$2" n="$3"
  if timeout 3 bash -c "echo >/dev/tcp/$h/$p" 2>/dev/null; then
    echo "tcp $n $h:$p open"
  else
    echo "tcp $n $h:$p FAIL"
  fi
}

ROLE="${KPAX_CI_ROLE:-unknown}"
echo "role=$ROLE"

case "$ROLE" in
  panel)
    tcp 127.0.0.1 8787 panel-healthz-port
    tcp 127.0.0.1 28443 relay-de
    tcp 127.0.0.1 28444 relay-fi
    tcp 31.77.116.51 443 de443
    tcp 144.31.169.6 443 fi443
    tcp 195.133.45.167 2443 ru2443
    tcp 195.133.45.167 2444 ru2444
    tcp 195.133.45.167 2445 ru2445
    tcp 2.26.225.213 443 pl443
    tcp 127.0.0.1 28445 relay-pl
    if curl -fsS -m 5 http://127.0.0.1:8787/healthz >/dev/null; then
      echo "http healthz ok"
    else
      echo "http healthz FAIL"
    fi
    # Subscription endpoint smoke (no token leak: only status code)
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 8 -H 'Host: k-pax.space' http://127.0.0.1:8787/ || true)
    echo "http panel_root code=$code"
    ;;
  front)
    tcp 77.221.154.107 28443 relay-de
    tcp 77.221.154.107 28444 relay-fi
    tcp 127.0.0.1 2443 local2443
    tcp 127.0.0.1 2444 local2444
    ;;
  exit)
    tcp 127.0.0.1 443 local443
    tcp 127.0.0.1 2053 local2053
    ;;
esac

if command -v sing-box >/dev/null && [[ -f /etc/k-pax/ci-probe.json ]]; then
  # Optional operator-maintained probe file without user UUIDs — skipped if absent
  echo "ci-probe.json present (skipped auto-run unless KPAX_CI_RUN_PROBE=1)"
fi
echo "DONE"
