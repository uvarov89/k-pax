#!/usr/bin/env python3
"""Run on the control server: add XHTTP inbounds to Xray on one node, next to the existing WebSocket one.

  python3 xhttp-node-setup.py <node-id> [--rollback]

Adds two VLESS inbounds with the same clients as the WebSocket inbound:
  xhttp-cdn  — plain, port 10087, only the K-Pax server may connect (Caddy terminates TLS on k-pax.space)
  xhttp-tls  — TLS with the node's Let's Encrypt certificate, port 8444, open to everyone
The Let's Encrypt deploy hook also restarts Xray after renewal.
"""

from __future__ import annotations

import json
import subprocess
import sys

CONFIG_PATH = "/etc/k-pax/config.json"
CDN_PORT = 10087
TLS_PORT = 8444
CONTROL_IP = "77.221.154.107"

REMOTE = r'''
set -e
NODE="$1"; SECRET="$2"; ACTION="$3"
X=/usr/local/etc/xray/config.json
HOOK=/etc/letsencrypt/renewal-hooks/deploy/k-pax-sing-box
if [ "$ACTION" = rollback ]; then
  cp -a $X.xhttp-bak $X && systemctl restart xray && systemctl is-active xray
  ufw delete allow from 77.221.154.107 to any port 10087 proto tcp >/dev/null 2>&1 || true
  ufw delete allow 8444/tcp >/dev/null 2>&1 || true
  echo rolled-back; exit 0
fi
[ -f $X.xhttp-bak ] || cp -a $X $X.xhttp-bak
python3 - "$NODE" "$SECRET" <<'PY'
import json, sys
node, secret = sys.argv[1], sys.argv[2]
path = "/usr/local/etc/xray/config.json"
cfg = json.load(open(path))
ws = next(i for i in cfg["inbounds"] if i.get("protocol") == "vless" and (i.get("streamSettings") or {}).get("network") == "ws")
clients = ws["settings"]["clients"]
cfg["inbounds"] = [i for i in cfg["inbounds"] if i.get("tag") not in ("xhttp-cdn", "xhttp-tls")]
cfg["inbounds"].append({
    "tag": "xhttp-cdn", "listen": "0.0.0.0", "port": 10087, "protocol": "vless",
    "settings": {"clients": clients, "decryption": "none"},
    "streamSettings": {"network": "xhttp", "xhttpSettings": {"path": "/x/%s/%s" % (node, secret), "mode": "auto"}},
})
live = "/etc/letsencrypt/live/%s.k-pax.space/" % node
cfg["inbounds"].append({
    "tag": "xhttp-tls", "listen": "0.0.0.0", "port": 8444, "protocol": "vless",
    "settings": {"clients": clients, "decryption": "none"},
    "streamSettings": {
        "network": "xhttp", "security": "tls",
        "tlsSettings": {"alpn": ["h2", "http/1.1"], "certificates": [{"certificateFile": live + "fullchain.pem", "keyFile": live + "privkey.pem"}]},
        "xhttpSettings": {"path": "/xh/%s" % secret, "mode": "auto"},
    },
})
json.dump(cfg, open(path.replace(".json", ".new.json"), "w"), indent=2)
print("inbounds:", [(i.get("tag") or i["streamSettings"]["network"], i["port"], len(i["settings"]["clients"])) for i in cfg["inbounds"]])
PY
XN=/usr/local/etc/xray/config.new.json; chmod 600 $XN
xray run -test -config $XN >/tmp/xhttp-test.log 2>&1 || { tail -3 /tmp/xhttp-test.log; rm -f $XN; exit 1; }
mv $XN $X
ufw allow from 77.221.154.107 to any port 10087 proto tcp >/dev/null
ufw allow 8444/tcp >/dev/null
grep -q "restart xray" $HOOK || sed -i 's/  systemctl restart sing-box/  systemctl restart sing-box\n  systemctl restart xray/' $HOOK
systemctl restart xray
sleep 1
systemctl is-active xray
ss -tlnp | grep -E ':(10086|10087|8444) ' | awk '{print $4}'
'''


def main() -> None:
    node_id = sys.argv[1]
    action = "rollback" if "--rollback" in sys.argv else "apply"
    cfg = json.load(open(CONFIG_PATH))
    node = next(n for n in cfg["nodes"] if n["id"] == node_id)
    secret = str(cfg["ss_ws_secret"])
    cmd = [
        "ssh", "-i", cfg["ssh_key"], "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", "UserKnownHostsFile=" + cfg["known_hosts"], "-o", "ConnectTimeout=15", "root@" + node["host"],
        "bash", "-s", "--", node_id, secret, action,
    ]
    result = subprocess.run(cmd, input=REMOTE.encode(), capture_output=True, timeout=180)
    print(result.stdout.decode("utf-8", "replace").replace(secret, "<secret>"))
    if result.returncode != 0:
        print("FAILED", result.stderr.decode("utf-8", "replace")[-600:].replace(secret, "<secret>"))
        sys.exit(1)


if __name__ == "__main__":
    main()
