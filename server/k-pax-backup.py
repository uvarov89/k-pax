#!/usr/bin/env python3
"""Consistent encrypted backup of the account database onto both exit nodes."""

from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

CONFIG_PATH = "/etc/k-pax/config.json"
DB_PATH = "/var/lib/k-pax/k-pax.db"
PASS_PATH = "/etc/k-pax/backup.pass"
REMOTE_DIR = "/var/backups/k-pax"
KEEP = 7


def ssh_base(cfg: dict) -> list[str]:
    return [
        "ssh",
        "-i",
        cfg["ssh_key"],
        "-o",
        "BatchMode=yes",
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        "UserKnownHostsFile=" + cfg["known_hosts"],
        "-o",
        "ConnectTimeout=15",
    ]


def run(cmd: list[str], stdin: bytes | None = None) -> str:
    result = subprocess.run(
        cmd,
        input=stdin,
        capture_output=True,
        timeout=60,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or b"command failed").decode("utf-8", "replace").strip()
        line = detail.splitlines()[-1] if detail else "command failed"
        raise RuntimeError(line[:240])
    return result.stdout.decode("utf-8", "replace")


def openssl(mode: str, source: str, target: str) -> None:
    run(
        [
            "openssl",
            "enc",
            mode,
            "-aes-256-cbc",
            "-pbkdf2",
            "-iter",
            "200000",
            "-salt",
            "-in",
            source,
            "-out",
            target,
            "-pass",
            "file:" + PASS_PATH,
        ]
    )


def main() -> None:
    cfg = json.load(open(CONFIG_PATH, encoding="utf-8"))
    if not os.path.isfile(PASS_PATH):
        raise SystemExit("missing backup password file")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    name = "k-pax-%s.db.enc" % stamp
    os.umask(0o077)
    with tempfile.TemporaryDirectory(dir="/var/lib/k-pax", prefix="backup-") as folder:
        plain = os.path.join(folder, "k-pax.db")
        enc = os.path.join(folder, name)
        check = os.path.join(folder, "check.db")
        source = sqlite3.connect(DB_PATH, timeout=30)
        copied = sqlite3.connect(plain)
        try:
            source.backup(copied)
        finally:
            copied.close()
            source.close()
        openssl("-e", plain, enc)
        os.remove(plain)
        openssl("-d", enc, check)
        conn = sqlite3.connect(check)
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        count = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        conn.close()
        os.remove(check)
        if integrity != "ok" or count < 1:
            raise SystemExit("backup integrity failed")
        payload = open(enc, "rb").read()
        if payload.startswith(b"SQLite format 3"):
            raise SystemExit("backup left the database unencrypted")
        hosts = [node["host"] for node in cfg["nodes"]]
        for host in hosts:
            remote = REMOTE_DIR + "/" + name
            run(ssh_base(cfg) + ["root@" + host, "mkdir -p %s && chmod 700 %s" % (REMOTE_DIR, REMOTE_DIR)])
            run(ssh_base(cfg) + ["root@" + host, "cat > %s && chmod 600 %s" % (remote, remote)], stdin=payload)
            listing = run(ssh_base(cfg) + ["root@" + host, "ls -1 %s" % REMOTE_DIR])
            names = sorted(
                item.strip()
                for item in listing.splitlines()
                if item.startswith("k-pax-") and item.endswith(".db.enc")
            )
            stale = names[:-KEEP]
            if stale:
                quoted = " ".join(REMOTE_DIR + "/" + item for item in stale)
                run(ssh_base(cfg) + ["root@" + host, "rm -f " + quoted])
        print("backup %s users=%d nodes=%d" % (name, count, len(hosts)), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print("backup failed", exc, file=sys.stderr)
        sys.exit(1)
