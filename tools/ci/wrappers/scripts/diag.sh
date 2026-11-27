#!/usr/bin/env bash
# Read-only host diagnostics. No secrets printed. Runs as root via kpax-ci.
set -euo pipefail
echo "=== host $(hostname -f 2>/dev/null || hostname) $(date -u +%Y-%m-%dT%H:%MZ) ==="
echo "--- uptime / load ---"
uptime || true
echo "--- memory ---"
free -m 2>/dev/null || true
echo "--- disk ---"
df -h / /var 2>/dev/null | head -20 || true
echo "--- listening (sanitized) ---"
ss -lnt 2>/dev/null \
  | grep -E ':(22|80|443|2053|2443|2444|2445|28443|28444|28445|8787)\s' || true
echo "--- services ---"
for u in k-pax kpax-front-relay caddy sing-box xray nginx; do
  if systemctl list-unit-files "${u}.service" &>/dev/null || systemctl status "$u" &>/dev/null; then
    echo -n "$u: "
    systemctl is-active "$u" 2>/dev/null || echo n/a
  fi
done
echo "--- sing-box / xray recent errors (redacted) ---"
(journalctl -u sing-box -u xray --since '2 hours ago' --no-pager -p err..alert 2>/dev/null || true) \
  | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/gi' \
  | sed -E 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g' \
  | tail -40 || true
echo "--- k-pax recent (redacted) ---"
(journalctl -u k-pax --since '2 hours ago' --no-pager 2>/dev/null || true) \
  | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/gi' \
  | grep -Ei 'error|alert|fail|probe|relay|health' \
  | tail -40 || true
echo "STATUS=OK"
echo "DONE"
