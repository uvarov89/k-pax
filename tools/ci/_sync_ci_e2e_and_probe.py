#!/usr/bin/env python3
from __future__ import annotations

import json
import secrets
import sqlite3
import subprocess
from pathlib import Path

cfg = json.loads(Path("/etc/k-pax/config.json").read_text(encoding="utf-8"))
conn = sqlite3.connect("/var/lib/k-pax/k-pax.db")
conn.row_factory = sqlite3.Row
cols = {r[1] for r in conn.execute("PRAGMA table_info(users)")}
row = conn.execute("SELECT * FROM users WHERE public_id='CI-E2E'").fetchone()
if row is None:
    raise SystemExit("STATUS=FAIL missing CI-E2E")
uid = row["uuid"]
hy2 = (row["hy2_password"] or "").strip() if "hy2_password" in cols else ""
if len(hy2) < 16:
    hy2 = secrets.token_hex(16)
    if "hy2_password" in cols:
        conn.execute(
            "UPDATE users SET hy2_password=? WHERE public_id=?",
            (hy2, "CI-E2E"),
        )
        conn.commit()
        print("STATUS=OK refreshed hy2_password")
print("STATUS=OK CI-E2E uuid_len", len(uid), "hy2_len", len(hy2))
key = cfg["ssh_key"]
kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"
for n in cfg.get("nodes") or []:
    if n.get("enabled", True) is False:
        print("skip", n.get("id"))
        continue
    host = n["host"]
    nid = n.get("id")
    cmd = "python3 /usr/local/sbin/k-pax-user.py add %s %s" % (uid, hy2)
    try:
        out = subprocess.check_output(
            [
                "ssh",
                "-i",
                key,
                "-o",
                "BatchMode=yes",
                "-o",
                "UserKnownHostsFile=%s" % kh,
                "root@%s" % host,
                cmd,
            ],
            text=True,
            stderr=subprocess.STDOUT,
            timeout=90,
        )
        print("sync", nid, out.strip().replace(uid, "<uuid>"))
    except subprocess.CalledProcessError as e:
        err = (e.output or str(e)).replace(uid, "<uuid>")[-400:]
        print("sync", nid, "FAIL", err)
print("DONE")
