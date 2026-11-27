#!/usr/bin/env python3
"""Anonymized panel analytics. No tokens, emails, or full UUIDs."""
from __future__ import annotations

import sqlite3
import time

DB = "/var/lib/k-pax/k-pax.db"
now = int(time.time())
day = 86400
conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)

print(f"# analytics {time.strftime('%Y-%m-%dT%H:%MZ', time.gmtime())}")
print(
    "active_subs",
    conn.execute(
        "SELECT COUNT(*) FROM users WHERE active=1 AND expires_at>?", (now,)
    ).fetchone()[0],
)
print(
    "expired_flagged_active",
    conn.execute(
        "SELECT COUNT(*) FROM users WHERE active=1 AND expires_at<=?", (now,)
    ).fetchone()[0],
)
print(
    "signups_7d",
    conn.execute(
        "SELECT COUNT(*) FROM users WHERE created_at>?", (now - 7 * day,)
    ).fetchone()[0]
    if conn.execute(
        "SELECT 1 FROM pragma_table_info('users') WHERE name='created_at'"
    ).fetchone()
    else "n/a",
)

# payments
try:
    print(
        "payments_30d",
        conn.execute(
            "SELECT COUNT(*) FROM payments WHERE created_at>?", (now - 30 * day,)
        ).fetchone()[0],
    )
except sqlite3.Error as e:
    print("payments_30d err", type(e).__name__)

try:
    print("platega_30d")
    for row in conn.execute(
        """
        SELECT status, COUNT(*) FROM platega_invoices
        WHERE created_at>? GROUP BY 1 ORDER BY 2 DESC
        """,
        (now - 30 * day,),
    ):
        print(" ", row[0], row[1])
except sqlite3.Error as e:
    print("platega err", type(e).__name__)

print("client_events_24h")
try:
    for row in conn.execute(
        """
        SELECT event, COUNT(*) FROM client_events
        WHERE created_at>? GROUP BY 1 ORDER BY 2 DESC LIMIT 20
        """,
        (now - day,),
    ):
        print(" ", row[0], row[1])
    print("by_platform_version_24h")
    for row in conn.execute(
        """
        SELECT COALESCE(platform,'?'), COALESCE(brand,'?'), COALESCE(app_version,'?'), COUNT(*)
        FROM client_events WHERE created_at>?
        GROUP BY 1,2,3 ORDER BY 4 DESC LIMIT 25
        """,
        (now - day,),
    ):
        print(" ", row)
    print("connect_ok_by_country_24h")
    for row in conn.execute(
        """
        SELECT COALESCE(country_id,'?'), COUNT(*) FROM client_events
        WHERE event='connect_ok' AND created_at>? GROUP BY 1 ORDER BY 2 DESC
        """,
        (now - day,),
    ):
        print(" ", row[0], row[1])
except sqlite3.Error as e:
    print("events err", type(e).__name__)

print("DONE")
