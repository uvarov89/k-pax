#!/usr/bin/env python3
"""Ensure dedicated CI E2E diagnostic account + /etc/k-pax/ci-e2e.env.

- Never uses a random paying customer's UUID.
- Creates/refreshes public_id=CI-E2E if missing (long-lived, active).
- Writes per-exit Reality params; omits keys rather than inventing substitutes.
- Prints only STATUS lines (no UUID).
Run on panel as root.
"""
from __future__ import annotations

import json
import secrets
import sqlite3
import time
import uuid as uuidlib
from pathlib import Path

CFG = Path("/etc/k-pax/config.json")
DB = Path("/var/lib/k-pax/k-pax.db")
OUT = Path("/etc/k-pax/ci-e2e.env")
PUBLIC_ID = "CI-E2E"
# ~10 years
EXPIRE_YEARS = 10


def main() -> None:
    cfg = json.loads(CFG.read_text(encoding="utf-8"))
    now = int(time.time())
    expires = now + EXPIRE_YEARS * 365 * 86400
    conn = sqlite3.connect(str(DB))
    conn.row_factory = sqlite3.Row
    cols = {r[1] for r in conn.execute("PRAGMA table_info(users)")}
    row = conn.execute(
        "SELECT * FROM users WHERE public_id=? LIMIT 1", (PUBLIC_ID,)
    ).fetchone()
    if row is None:
        uid = str(uuidlib.uuid4())
        token = secrets.token_urlsafe(24)
        fields = {
            "public_id": PUBLIC_ID,
            "token": token,
            "uuid": uid,
            "created_at": now,
            "expires_at": expires,
            "active": 1,
        }
        if "hy2_password" in cols:
            fields["hy2_password"] = secrets.token_hex(16)
        if "verified" in cols:
            fields["verified"] = 1
        if "brand" in cols:
            fields["brand"] = "kpax"
        if "contact" in cols:
            fields["contact"] = "ci-e2e@localhost"
        keys = ", ".join(fields)
        q = ", ".join("?" for _ in fields)
        conn.execute(
            f"INSERT INTO users ({keys}) VALUES ({q})", tuple(fields.values())
        )
        conn.commit()
        print("STATUS=OK created diagnostic user", PUBLIC_ID)
    else:
        conn.execute(
            "UPDATE users SET active=1, expires_at=? WHERE public_id=?",
            (expires, PUBLIC_ID),
        )
        conn.commit()
        uid = row["uuid"]
        print("STATUS=OK refreshed diagnostic user", PUBLIC_ID)

    by_id = {n["id"]: n for n in cfg.get("nodes") or []}
    ru = by_id.get("ru") or {}
    de = by_id.get("de") or {}
    fi = by_id.get("fi") or {}
    pl = by_id.get("pl") or {}

    def req(node: dict, *keys: str) -> str:
        for k in keys:
            v = str(node.get(k) or "").strip()
            if v:
                return v
        return ""

    lines = [
        f"E2E_PUBLIC_ID={PUBLIC_ID}",
        f"E2E_UUID={uid}",
        # Front Reality (required for RF path)
        f"E2E_FRONT_HOST={req(ru, 'self_domain', 'host')}",
        f"E2E_FRONT_SNI={req(ru, 'reality_sni', 'self_domain', 'host')}",
        f"E2E_FRONT_PBK={req(ru, 'pbk')}",
        f"E2E_FRONT_SID={req(ru, 'sid')}",
        # Direct exits — individual keys only (empty = skip, never borrow front keys)
        f"E2E_DE_HOST={req(de, 'host')}",
        f"E2E_DE_SNI={req(de, 'reality_sni', 'self_domain')}",
        f"E2E_DE_PBK={req(de, 'pbk')}",
        f"E2E_DE_SID={req(de, 'sid')}",
        f"E2E_FI_HOST={req(fi, 'host')}",
        f"E2E_FI_SNI={req(fi, 'reality_sni', 'self_domain')}",
        f"E2E_FI_PBK={req(fi, 'pbk')}",
        f"E2E_FI_SID={req(fi, 'sid')}",
        f"E2E_PL_HOST={req(pl, 'host')}",
        f"E2E_PL_SNI={req(pl, 'reality_sni', 'self_domain') or 'pl.k-pax.space'}",
        f"E2E_PL_PBK={req(pl, 'pbk')}",
        f"E2E_PL_SID={req(pl, 'sid')}",
        # Expected egress IPs for SoftProbe validation
        f"E2E_EXPECT_DE_IP={req(de, 'host')}",
        f"E2E_EXPECT_FI_IP={req(fi, 'host')}",
        f"E2E_EXPECT_PL_IP={req(pl, 'host')}",
    ]
    missing = [ln.split("=", 1)[0] for ln in lines if ln.endswith("=") and ln.startswith("E2E_FRONT_")]
    if missing:
        print("STATUS=FAIL missing front Reality fields", ",".join(missing))
        raise SystemExit(1)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    OUT.chmod(0o600)
    print("STATUS=OK wrote", OUT)

    # Best-effort: remind operator to sync UUID onto fronts/exits
    print("STATUS=OK next: sync CI-E2E uuid onto enabled nodes (kpax-ci sync-users / panel user sync)")


if __name__ == "__main__":
    main()
