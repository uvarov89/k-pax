#!/usr/bin/env bash
# Read-only host diagnostics. No secrets printed. Runs as root via kpax-ci.
# Optional: kpax-ci diag [hours]  — journal window (default 2).
set -euo pipefail
HOURS="${1:-2}"
[[ "$HOURS" =~ ^[0-9]+$ ]] || HOURS=2
echo "=== host $(hostname -f 2>/dev/null || hostname) $(date -u +%Y-%m-%dT%H:%MZ) window=${HOURS}h ==="
echo "--- uptime / load ---"
uptime || true
echo "--- memory ---"
free -m 2>/dev/null || true
echo "--- disk ---"
df -h / /var /tmp 2>/dev/null | head -20 || true
echo "--- cpu top ---"
ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -8 || true
echo "--- listening (sanitized ports) ---"
ss -lntu 2>/dev/null \
  | grep -E ':(22|80|443|2053|2443|2444|2445|28443|28444|28445|8787|8446)\s' || true
echo "--- established sample (counts by local port) ---"
ss -nt 2>/dev/null | awk 'NR>1{split($4,a,":"); p=a[length(a)]; c[p]++} END{for(p in c) if(p+0>0) print p,c[p]}' \
  | sort -k2 -nr | head -15 || true
echo "--- services ---"
for u in k-pax kpax-front-relay caddy sing-box xray nginx; do
  if systemctl list-unit-files "${u}.service" &>/dev/null || systemctl status "$u" &>/dev/null; then
    echo -n "$u: "
    systemctl is-active "$u" 2>/dev/null || echo n/a
  fi
done
echo "--- firewall (ufw/nft summary) ---"
if command -v ufw >/dev/null 2>&1; then
  ufw status numbered 2>/dev/null | head -40 || true
elif command -v nft >/dev/null 2>&1; then
  nft list ruleset 2>/dev/null | head -60 || true
else
  iptables -L -n 2>/dev/null | head -40 || true
fi
echo "--- routing ---"
ip route 2>/dev/null | head -20 || true
echo "--- DNS resolvers ---"
(resolvectl status 2>/dev/null || cat /etc/resolv.conf 2>/dev/null) | head -30 || true
echo "--- cert expiry (paths only, no keys) ---"
for p in /etc/letsencrypt/live/*/cert.pem /etc/ssl/media/fullchain.pem /var/lib/caddy/*.crt; do
  for f in $p; do
    [[ -f "$f" ]] || continue
    end=$(openssl x509 -in "$f" -noout -enddate 2>/dev/null | cut -d= -f2 || true)
    subj=$(openssl x509 -in "$f" -noout -subject 2>/dev/null | sed 's/subject=//' || true)
    echo "$f | $subj | ends $end"
  done
done 2>/dev/null | head -20 || true
echo "--- sing-box config check (no dump of secrets) ---"
if [[ -f /etc/sing-box/config.json ]]; then
  if command -v sing-box >/dev/null 2>&1; then
    if sing-box check -c /etc/sing-box/config.json >/tmp/sb-check.out 2>&1; then
      echo "sing-box check: OK"
    else
      echo "sing-box check: FAIL"
      sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/gi' /tmp/sb-check.out | tail -20
    fi
  fi
  # Structure-only summary (no keys/uuids)
  python3 - <<'PY' 2>/dev/null || true
import json
from pathlib import Path
p=Path("/etc/sing-box/config.json")
cfg=json.loads(p.read_text())
ins=cfg.get("inbounds") or []
outs=cfg.get("outbounds") or []
print("inbounds", len(ins), "types", sorted({i.get("type") for i in ins}))
print("outbounds", len(outs), "tags", [o.get("tag") for o in outs][:20])
for i in ins:
    t=i.get("type"); port=i.get("listen_port") or i.get("port")
    tls=(i.get("tls") or {})
    reality=bool((tls.get("reality") or {}).get("enabled"))
    print(f"  in {t} port={port} reality={reality} users={len(i.get('users') or [])}")
PY
fi
echo "--- latency sample (ICMP optional) ---"
for h in 1.1.1.1 8.8.8.8; do
  ping -c 2 -W 2 "$h" 2>/dev/null | tail -2 || echo "ping $h n/a"
done
echo "--- sing-box / xray recent errors (redacted) ---"
(journalctl -u sing-box -u xray --since "${HOURS} hours ago" --no-pager -p err..alert 2>/dev/null || true) \
  | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/gi' \
  | sed -E 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g' \
  | tail -60 || true
echo "--- k-pax recent (redacted) ---"
(journalctl -u k-pax --since "${HOURS} hours ago" --no-pager 2>/dev/null || true) \
  | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/gi' \
  | grep -Ei 'error|alert|fail|probe|relay|health|sync' \
  | tail -60 || true
echo "--- wrapper integrity ---"
ls -la /usr/local/lib/kpax-ci/kpax-ci /etc/sudoers.d/kpax-gha 2>/dev/null || true
stat -c '%U:%G %a %n' /usr/local/lib/kpax-ci/kpax-ci /usr/local/lib/kpax-ci/scripts 2>/dev/null || true
echo "STATUS=OK"
echo "DONE"
