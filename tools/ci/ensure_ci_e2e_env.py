#!/usr/bin/env python3
"""Create /etc/k-pax/ci-e2e.env from an active user + node Reality params.

Writes root:root 0600 file. Prints only STATUS=OK / FAIL — never UUID.
Run on panel as root.
"""
from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path

CFG = Path("/etc/k-pax/config.json")
DB = Path("/var/lib/k-pax/k-pax.db")
OUT = Path("/etc/k-pax/ci-e2e.env")

cfg = json.loads(CFG.read_text(encoding="utf-8"))
now = int(time.time())
conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
row = conn.execute(
    "SELECT uuid FROM users WHERE active=1 AND expires_at>? ORDER BY id DESC LIMIT 1",
    (now,),
).fetchone()
if not row:
    raise SystemExit("STATUS=FAIL no active user")
uuid = row[0]

by_id = {n["id"]: n for n in cfg.get("nodes") or []}
ru = by_id.get("ru") or {}
de = by_id.get("de") or {}
fi = by_id.get("fi") or {}
pl = by_id.get("pl") or {}

lines = [
    f"E2E_UUID={uuid}",
    f"E2E_PBK={ru.get('pbk') or ''}",
    f"E2E_SID={ru.get('sid') or ''}",
    f"E2E_FRONT_HOST={ru.get('self_domain') or ru.get('host') or ''}",
    f"E2E_FRONT_SNI={ru.get('reality_sni') or ru.get('self_domain') or ru.get('host') or ''}",
    f"E2E_DE_HOST={de.get('host') or ''}",
    f"E2E_DE_SNI={de.get('reality_sni') or de.get('self_domain') or ''}",
    f"E2E_DE_PBK={de.get('pbk') or ''}",
    f"E2E_DE_SID={de.get('sid') or ''}",
    f"E2E_FI_HOST={fi.get('host') or ''}",
    f"E2E_FI_SNI={fi.get('reality_sni') or fi.get('self_domain') or ''}",
    f"E2E_PL_HOST={pl.get('host') or ''}",
    f"E2E_PL_SNI={pl.get('reality_sni') or pl.get('self_domain') or 'pl.k-pax.space'}",
    f"E2E_PL_PBK={pl.get('pbk') or ''}",
    f"E2E_PL_SID={pl.get('sid') or ''}",
]
# Front Reality uses front pbk/sid; direct exits need their own — e2e script currently
# uses E2E_PBK/SID for all. Prefer front keys for front probes; for direct we should
# switch keys. Keep front keys as primary (required path).
OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
OUT.chmod(0o600)
print("STATUS=OK wrote", OUT, "mode=0600")
