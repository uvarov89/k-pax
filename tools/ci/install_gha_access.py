#!/usr/bin/env python3
"""Install limited `gha` CI user + deploy pubkey on panel and enabled nodes.

Run on the panel host as root:
  cat gha.pub | python3 install_gha_access.py
Or:
  python3 install_gha_access.py /path/to/gha.pub
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

if len(sys.argv) > 1:
    PUBKEY = Path(sys.argv[1]).read_text(encoding="utf-8").strip()
else:
    PUBKEY = sys.stdin.read().strip()
if not PUBKEY.startswith("ssh-") or "PRIVATE" in PUBKEY:
    raise SystemExit("need a single OpenSSH public key")

cfg = json.load(open("/etc/k-pax/config.json", encoding="utf-8"))
admin_key = cfg["ssh_key"]
kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"

SUDOERS = """# K-Pax GitHub Actions (limited)
gha ALL=(root) NOPASSWD: /bin/systemctl, /usr/bin/systemctl, /bin/journalctl, /usr/bin/journalctl, /bin/ss, /usr/bin/ss, /bin/curl, /usr/bin/curl, /usr/bin/free, /bin/df, /usr/bin/df, /usr/bin/uptime, /bin/cp, /bin/mv, /bin/mkdir, /bin/chmod, /bin/rm, /usr/bin/install, /usr/bin/python3, /usr/bin/sqlite3, /bin/cat, /bin/ls, /bin/tar, /usr/bin/openssl, /usr/bin/rsync, /bin/rsync, /bin/systemctl restart k-pax, /bin/systemctl restart kpax-front-relay
"""

Path("/tmp/gha.pub").write_text(PUBKEY + "\n", encoding="utf-8")
Path("/tmp/gha.sudoers").write_text(SUDOERS, encoding="utf-8")

BOOTSTRAP = r"""
set -euo pipefail
id gha >/dev/null 2>&1 || useradd --create-home --shell /bin/bash gha
install -d -m 700 -o gha -g gha /home/gha/.ssh
AUTH=/home/gha/.ssh/authorized_keys
touch "$AUTH"
PUB=$(cat /tmp/gha.pub | head -1)
grep -qxF "$PUB" "$AUTH" 2>/dev/null || echo "$PUB" >> "$AUTH"
grep -v PRIVATE "$AUTH" > "$AUTH.tmp" && mv "$AUTH.tmp" "$AUTH"
chown gha:gha "$AUTH"
chmod 600 "$AUTH"
install -m 440 /tmp/gha.sudoers /etc/sudoers.d/kpax-gha
visudo -cf /etc/sudoers.d/kpax-gha
echo OK $(hostname) $(id -u gha)
"""


def run_local() -> None:
    print(subprocess.check_output(["bash", "-lc", BOOTSTRAP], text=True))


def ssh(host: str, script: str) -> str:
    return subprocess.check_output(
        [
            "ssh",
            "-i",
            admin_key,
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=12",
            "-o",
            f"UserKnownHostsFile={kh}",
            f"root@{host}",
            "bash -s",
        ],
        input=script,
        text=True,
        stderr=subprocess.STDOUT,
        timeout=90,
    )


print("=== panel ===")
run_local()

for n in cfg.get("nodes") or []:
    nid = n.get("id")
    if n.get("enabled", True) is False:
        print("skip", nid)
        continue
    host = n["host"]
    print("===", nid, host)
    try:
        subprocess.check_call(
            [
                "scp",
                "-i",
                admin_key,
                "-o",
                "BatchMode=yes",
                "-o",
                f"UserKnownHostsFile={kh}",
                "/tmp/gha.pub",
                "/tmp/gha.sudoers",
                f"root@{host}:/tmp/",
            ]
        )
        print(ssh(host, BOOTSTRAP))
    except Exception as e:
        print("FAIL", nid, e)

print("DONE")
