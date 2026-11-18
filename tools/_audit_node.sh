#!/bin/bash
set -eu
echo "HOST=$(hostname)"
systemctl is-active sing-box 2>/dev/null || true
systemctl is-active nginx 2>/dev/null || true
ss -lnt | head -1
ss -lnt | grep -E ':(443|8443|2087|8446|8447)\s' || true
CFG=""
for p in /etc/sing-box/config.json /usr/local/etc/sing-box/config.json; do
  if [ -f "$p" ]; then CFG="$p"; break; fi
done
echo "CFG=$CFG"
if [ -n "$CFG" ]; then
  python3 -c 'import json,sys; c=json.load(open(sys.argv[1]));
[print("inbound", i.get("type"), i.get("tag"), "port", i.get("listen_port"), "server_name", (i.get("tls") or {}).get("server_name"), "short_id", ((i.get("tls") or {}).get("reality") or {}).get("short_id"), "handshake", ((i.get("tls") or {}).get("reality") or {}).get("handshake")) for i in c.get("inbounds",[])]' "$CFG"
fi
for d in files.nastolkashop.store static.nastolkashop.store img.nastolkashop.store; do
  code=$(curl -k -sS -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "https://127.0.0.1:8446/" -H "Host: $d" || echo fail)
  echo "local8446 Host=$d -> $code"
done