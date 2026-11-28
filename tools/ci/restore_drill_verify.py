#!/usr/bin/env python3
"""Offline verify of extracted backup under ./drill — no secrets printed."""
from __future__ import annotations

import json
import sqlite3
import subprocess
import sys
from pathlib import Path

drill = Path("drill")
out = Path("out")
out.mkdir(parents=True, exist_ok=True)

manifest = drill / "meta" / "MANIFEST.txt"
if manifest.is_file():
    print("=== MANIFEST ===")
    print(manifest.read_text(encoding="utf-8", errors="replace")[:4000])
else:
    print("=== tree ===")
    for p in sorted(drill.rglob("*"))[:80]:
        print(p)

db = None
for cand in (drill / "db" / "k-pax.backup.db", drill / "db" / "k-pax.db"):
    if cand.is_file():
        db = cand
        break
if db is None:
    print("STATUS=FAIL no sqlite in backup")
    sys.exit(1)

integrity = subprocess.check_output(
    ["sqlite3", str(db), "PRAGMA integrity_check;"], text=True
).strip()
(out / "DB_INTEGRITY.txt").write_text(integrity + "\n", encoding="utf-8")
print("integrity", integrity)
if integrity != "ok":
    sys.exit(1)

conn = sqlite3.connect(str(db))
users = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
active = conn.execute(
    "SELECT COUNT(*) FROM users WHERE active=1"
).fetchone()[0]
lines = [f"users_count={users}", f"active_users={active}"]
print("\n".join(lines))

cfg_path = drill / "cfg" / "config.json"
if not cfg_path.is_file():
    print("STATUS=FAIL missing config.json")
    sys.exit(1)
cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
nodes = cfg.get("nodes") or []
print("nodes", len(nodes), [n.get("id") for n in nodes])
secret_keys = [
    k
    for k in cfg
    if any(x in k.lower() for x in ("key", "pass", "secret", "token"))
]
print("secret_fields_present", len(secret_keys))

node_files = list((drill / "nodes").glob("*.sing-box.json")) if (drill / "nodes").is_dir() else []
print(f"node_singbox_files={len(node_files)}")
for f in node_files:
    json.loads(f.read_text(encoding="utf-8"))
    print("ok", f.name)

lines.append(f"node_singbox_files={len(node_files)}")
lines.append("STATUS=OK isolated restore drill")
(out / "DRILL.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
