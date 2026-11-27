#!/usr/bin/env python3
"""Run on the control server: let domains that apps need pass before the ad block on every node.

  python3 node-allowlist.py [--dry-run]

The ad lists are kept as they are; this rule only goes in front of them, in routing and in DNS.
Idempotent: the rule is replaced, not duplicated.
"""

from __future__ import annotations

import json
import subprocess
import sys

CONFIG_PATH = "/etc/k-pax/config.json"
TAG = "k-pax-allow"
ALLOW = [
    # TikTok: settings (tnc*), API, video and images. Blocking tnc* leaves the app with "no connection".
    "byteoversea.com",
    "isnssdk.com",
    "snssdk.com",
    "sgsnssdk.com",
    "tiktokv.com",
    "tiktokv.us",
    "tiktokcdn.com",
    "tiktokcdn-us.com",
    "ibytedtos.com",
    "ibyteimg.com",
    "ttwstatic.com",
    # Push notifications and in-app links of many apps, not tracking.
    "onesignal.com",
    "branch.io",
    "app.link",
]

REMOTE = r'''
set -e
C=/etc/sing-box/config.json
cp -a $C $C.bak-allow
python3 - "$1" <<'PY'
import json, sys
allow = [item for item in sys.argv[1].split(",") if item]
path = "/etc/sing-box/config.json"
cfg = json.load(open(path))
route = cfg["route"]
rules = [r for r in route["rules"] if r.get("_k") != "allow" and r.get("domain_suffix") != allow]
at = next((i for i, r in enumerate(rules) if r.get("action") == "reject" and r.get("rule_set")), len(rules))
rules.insert(at, {"domain_suffix": allow, "action": "route", "outbound": "direct"})
route["rules"] = rules
dns = cfg.get("dns", {})
drules = [r for r in dns.get("rules", []) if r.get("domain_suffix") != allow]
at = next((i for i, r in enumerate(drules) if r.get("action") == "reject"), len(drules))
local = next((r.get("server") for r in drules if r.get("action") == "route" and r.get("server")), "dns-local")
drules.insert(at, {"domain_suffix": allow, "action": "route", "server": local, "strategy": "ipv4_only"})
dns["rules"] = drules
json.dump(cfg, open(path + ".new", "w"), indent=2)
PY
if ! sing-box check -c $C.new; then rm -f $C.new; exit 1; fi
if [ "$2" = dry ]; then rm -f $C.new; echo dry-ok; exit 0; fi
chown --reference=$C $C.new; chmod --reference=$C $C.new
mv $C.new $C
systemctl restart sing-box
sleep 1
systemctl is-active sing-box
'''


# Xray (WS and XHTTP lines) gets the same blocking as sing-box, built from the same sources:
# the ads rule-set, the manual suffix list of the sing-box reject rule and the lists behind ads-extra.
XRAY_REMOTE = r'''
set -e
X=/usr/local/etc/xray/config.json
CACHE=/var/lib/k-pax-adblock
mkdir -p $CACHE
for pair in "https://raw.githubusercontent.com/AdguardTeam/HostlistsRegistry/main/assets/filter_27.txt oisd.txt" \
            "https://raw.githubusercontent.com/Zalexanninev15/NoADS_RU/main/hosts/blocker.txt noads.txt"; do
  set -- $pair
  curl -fsSL -m 60 "$1" -o $CACHE/$2.new && mv $CACHE/$2.new $CACHE/$2 || rm -f $CACHE/$2.new
  [ -s $CACHE/$2 ] || { echo "no list $2"; exit 1; }
done
sing-box rule-set decompile /var/lib/sing-box/rules/ads.srs -o $CACHE/ads.json
cp -a $X $X.bak-adblock
python3 - "$ALLOW" <<'PY'
import json, re, sys, os
allow = [item for item in sys.argv[1].split(",") if item]
cache = "/var/lib/k-pax-adblock"
block = set()
def values(rule, key):
    # A rule-set field is a list, or a single string when it has one value.
    item = rule.get(key) or []
    return [item] if isinstance(item, str) else list(item)
for rule in json.load(open(cache + "/ads.json")).get("rules", []):
    block.update("full:" + d for d in values(rule, "domain"))
    block.update("domain:" + d.lstrip(".") for d in values(rule, "domain_suffix"))
    block.update("regexp:" + d for d in values(rule, "domain_regex") if len(d) > 8)
sb = json.load(open("/etc/sing-box/config.json"))
for rule in sb["route"]["rules"]:
    if rule.get("action") == "reject" and rule.get("domain_suffix"):
        block.update("domain:" + d.lstrip(".") for d in rule["domain_suffix"])
name = re.compile(r"^[a-z0-9.-]+\.[a-z]{2,}$")
for path in ("oisd.txt", "noads.txt"):
    for raw in open(os.path.join(cache, path), encoding="utf-8", errors="ignore"):
        line = raw.strip().lower()
        if not line or line[0] in "!#@[":
            continue
        if line.startswith("||") and line.endswith("^"):
            host = line[2:-1]
            if name.match(host):
                block.add("domain:" + host)
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("0.0.0.0", "127.0.0.1") and name.match(parts[1]) and parts[1] != "localhost":
            block.add("full:" + parts[1])
regexes = [re.compile(e[7:]) for e in block if e.startswith("regexp:")]
def blocked(host):
    labels = host.split(".")
    if "full:" + host in block or any("domain:" + ".".join(labels[i:]) in block for i in range(len(labels))):
        return True
    return any(r.search(host) for r in regexes)
canaries = ["www.youtube.com", "www.google.com", "yandex.ru", "vk.com", "www.tiktok.com", "telegram.org",
            "www.wildberries.ru", "www.ozon.ru", "i.instagram.com", "web.whatsapp.com", "chatgpt.com", "apple.com"]
bad = [h for h in canaries if blocked(h)]
if bad:
    raise SystemExit("refusing: the list would block " + ", ".join(bad))
path = "/usr/local/etc/xray/config.json"
cfg = json.load(open(path))
outs = [o for o in cfg.get("outbounds", []) if o.get("tag") not in ("direct", "block")]
cfg["outbounds"] = [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "block"}] + outs
cfg["routing"] = {"domainStrategy": "AsIs", "rules": [
    {"type": "field", "domain": ["domain:" + d for d in allow], "outboundTag": "direct"},
    {"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"},
    {"type": "field", "port": "25,465,587", "network": "tcp", "outboundTag": "block"},
    {"type": "field", "domain": sorted(block), "outboundTag": "block"},
]}
for inbound in cfg.get("inbounds", []):
    if inbound.get("protocol") == "vless":
        inbound["sniffing"] = {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True}
json.dump(cfg, open("/usr/local/etc/xray/config.new.json", "w"))
print("xray block entries:", len(block))
PY
chmod 600 /usr/local/etc/xray/config.new.json
if ! xray run -test -config /usr/local/etc/xray/config.new.json >/tmp/xab.log 2>&1; then tail -3 /tmp/xab.log; rm -f /usr/local/etc/xray/config.new.json; exit 1; fi
if [ "$DRY" = dry ]; then rm -f /usr/local/etc/xray/config.new.json; echo dry-ok; exit 0; fi
mv /usr/local/etc/xray/config.new.json $X
systemctl restart xray
sleep 3
echo "xray $(systemctl is-active xray) rss $(ps -o rss= -C xray | awk '{s+=$1} END {print int(s/1024)}') MB"
'''


def run_remote(cfg: dict, node: dict, script: str, args: list[str], env: str = "") -> None:
    cmd = [
        "ssh", "-i", cfg["ssh_key"], "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", "UserKnownHostsFile=" + cfg["known_hosts"], "-o", "ConnectTimeout=15", "root@" + node["host"],
        env + "bash", "-s", "--", *args,
    ]
    result = subprocess.run(cmd, input=script.encode(), capture_output=True, timeout=300)
    lines = result.stdout.decode().strip().splitlines()
    print(node["id"], "OK" if result.returncode == 0 else "FAILED", " | ".join(lines[-2:]), result.stderr.decode()[-300:] if result.returncode else "")
    if result.returncode != 0:
        sys.exit(1)


def main() -> None:
    dry = "--dry-run" in sys.argv
    cfg = json.load(open(CONFIG_PATH))
    allow = ",".join(ALLOW)
    only = sys.argv[sys.argv.index("--node") + 1] if "--node" in sys.argv else ""
    for node in cfg["nodes"]:
        if only and node["id"] != only:
            continue
        if "--xray-only" not in sys.argv:
            run_remote(cfg, node, REMOTE, [allow, "dry" if dry else "apply"])
        if "--sing-box-only" not in sys.argv:
            run_remote(cfg, node, XRAY_REMOTE, [], "ALLOW=%s DRY=%s " % (allow, "dry" if dry else "apply"))


if __name__ == "__main__":
    main()
