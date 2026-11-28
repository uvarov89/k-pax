#!/usr/bin/env bash
# DNS reachability + resolve checks for ChatGPT phone RCA.
# Usage: kpax-ci dns-check
set -euo pipefail
echo "=== dns-check host=$(hostname -f 2>/dev/null || hostname) $(date -u +%Y-%m-%dT%H:%MZ) ==="
FAIL=0

echo "--- listeners :53 ---"
ss -ulnp 2>/dev/null | grep -E ':53\s' | head -10 || echo "(none)"

probe_resolve() {
  local server="$1" name="${2:-www.gstatic.com}"
  local out err
  if command -v dig >/dev/null 2>&1; then
    # +short prints only answer RRs; stderr discarded so connection-refused text cannot false-OK
    out=$(dig +time=2 +tries=1 +short @"$server" "$name" A 2>/dev/null | head -5 || true)
    err=$(dig +time=2 +tries=1 @"$server" "$name" A 2>&1 >/dev/null | head -2 || true)
  elif command -v nslookup >/dev/null 2>&1; then
    out=$(nslookup -timeout=2 "$name" "$server" 2>/dev/null | awk '/^Address: /{print $2}' | tail -n +2 | head -5 || true)
    err=""
  else
    out=$(getent ahostsv4 "$name" 2>/dev/null | awk '{print $1}' | head -3 || true)
    server="system"
    err=""
  fi
  if echo "$out" | grep -Eoq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    echo "RESOLVE_OK @$server $name -> $(echo "$out" | tr '\n' ' ' | head -c 120)"
    return 0
  fi
  echo "RESOLVE_FAIL @$server $name :: ${err:-no-answer} $(echo "$out" | tr '\n' ' ' | head -c 80)"
  return 1
}

echo "--- resolve probes ---"
for s in 127.0.0.1 127.0.0.53 1.1.1.1 8.8.8.8; do
  if ! probe_resolve "$s"; then
    if [[ "$s" == "1.1.1.1" ]]; then
      FAIL=1
    fi
    # 127.0.0.1 failure is expected on hosts without local recursive DNS;
    # escalate only when sing-box dns-local points there (HINT below).
  fi
done

echo "--- sing-box dns summary (no secrets) ---"
MISMATCH=0
if [[ -f /etc/sing-box/config.json ]]; then
  set +e
  python3 - <<'PY'
import json, subprocess, sys
from pathlib import Path
c=json.loads(Path("/etc/sing-box/config.json").read_text())
dns=c.get("dns") or {}
servers=[]
points_local=False
for s in dns.get("servers") or []:
    if isinstance(s,str):
        servers.append(s)
        if s.startswith("127.0.0.1"):
            points_local=True
    elif isinstance(s,dict):
        addr=str(s.get("address") or s.get("server") or "")
        servers.append("%s=%s" % (s.get("tag") or "?", addr))
        if addr.startswith("127.0.0.1"):
            points_local=True
print("dns_servers", ", ".join(servers) or "(none)")
print("dns_final", dns.get("final"))
print("dns_strategy", dns.get("strategy") or dns.get("domain_strategy"))
if points_local:
    ss=subprocess.check_output(["ss","-ulnp"], text=True, stderr=subprocess.DEVNULL)
    has_local=any(("127.0.0.1" in line and ":53" in line) for line in ss.splitlines())
    if not has_local:
        print("FAIL root_cause=singbox_dns_to_127.0.0.1_without_listener")
        print("HINT patch set:dns.server.dns-local.address=1.1.1.1  OR  address=127.0.0.53")
        sys.exit(9)
PY
  py_rc=$?
  set -e
  if [[ "$py_rc" -eq 9 ]]; then
    MISMATCH=1
    FAIL=1
  elif [[ "$py_rc" -ne 0 ]]; then
    FAIL=1
  fi
else
  echo "(no /etc/sing-box/config.json)"
fi

echo "--- system resolvers ---"
(resolvectl status 2>/dev/null || cat /etc/resolv.conf 2>/dev/null) | head -25 || true

if [[ "$FAIL" -ne 0 ]]; then
  echo "STATUS=FAIL"
  [[ "$MISMATCH" -eq 1 ]] && echo "CLASS=DNS_MISMATCH"
  exit 1
fi
echo "STATUS=OK"
