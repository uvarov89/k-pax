#!/usr/bin/env python3
"""Push /usr/local/lib/kpax-ci + tight sudoers to enabled nodes. Run on panel as root."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

cfg = json.loads(Path("/etc/k-pax/config.json").read_text(encoding="utf-8"))
key = cfg["ssh_key"]
kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"
DEST = "/usr/local/lib/kpax-ci"


def run(host: str, cmd: list[str]) -> None:
    subprocess.check_call(cmd)


for n in cfg.get("nodes") or []:
    if n.get("enabled", True) is False:
        print("skip", n.get("id"))
        continue
    host = n["host"]
    nid = n.get("id")
    print("===", nid, host)
    try:
        # Prefer scp: some nodes lack rsync in PATH.
        subprocess.check_call(
            [
                "ssh",
                "-i",
                key,
                "-o",
                "BatchMode=yes",
                "-o",
                f"UserKnownHostsFile={kh}",
                f"root@{host}",
                f"mkdir -p {DEST}/scripts",
            ]
        )
        subprocess.check_call(
            [
                "scp",
                "-i",
                key,
                "-o",
                "BatchMode=yes",
                "-o",
                f"UserKnownHostsFile={kh}",
                "-r",
                f"{DEST}/kpax-ci",
                f"{DEST}/scripts",
                f"root@{host}:{DEST}/",
            ]
        )
        subprocess.check_call(
            [
                "scp",
                "-i",
                key,
                "-o",
                "BatchMode=yes",
                "-o",
                f"UserKnownHostsFile={kh}",
                "/etc/sudoers.d/kpax-gha",
                f"root@{host}:/etc/sudoers.d/kpax-gha",
            ]
        )
        subprocess.check_output(
            [
                "ssh",
                "-i",
                key,
                "-o",
                "BatchMode=yes",
                "-o",
                f"UserKnownHostsFile={kh}",
                f"root@{host}",
                f"chmod 755 {DEST}/kpax-ci; chmod 755 {DEST}/scripts/*.sh; "
                f"chmod 440 /etc/sudoers.d/kpax-gha; visudo -cf /etc/sudoers.d/kpax-gha; "
                f"id gha >/dev/null",
            ],
            text=True,
        )
        print("OK", nid)
    except Exception as e:
        print("FAIL", nid, e)

print("DONE")
