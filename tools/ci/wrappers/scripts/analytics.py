#!/usr/bin/env python3
"""Anonymized panel analytics. No tokens, emails, or full UUIDs.

Usage: analytics.py [days]
  days — lookback window for dynamics (default 7, max 90).
"""
from __future__ import annotations

import sqlite3
import sys
import time

DB = "/var/lib/k-pax/k-pax.db"
now = int(time.time())
day = 86400
try:
    lookback = int(sys.argv[1]) if len(sys.argv) > 1 else 7
except ValueError:
    lookback = 7
lookback = max(1, min(lookback, 90))
since = now - lookback * day

conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)

print(f"# analytics {time.strftime('%Y-%m-%dT%H:%MZ', time.gmtime())} lookback={lookback}d")
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
    "expiring_7d",
    conn.execute(
        "SELECT COUNT(*) FROM users WHERE active=1 AND expires_at>? AND expires_at<=?",
        (now, now + 7 * day),
    ).fetchone()[0],
)

has_created = conn.execute(
    "SELECT 1 FROM pragma_table_info('users') WHERE name='created_at'"
).fetchone()
if has_created:
    print(
        f"signups_{lookback}d",
        conn.execute(
            "SELECT COUNT(*) FROM users WHERE created_at>?", (since,)
        ).fetchone()[0],
    )
    print("signups_by_day")
    for row in conn.execute(
        """
        SELECT date(created_at,'unixepoch'), COUNT(*) FROM users
        WHERE created_at>? GROUP BY 1 ORDER BY 1
        """,
        (since,),
    ):
        print(" ", row[0], row[1])
else:
    print(f"signups_{lookback}d n/a")

# churn proxy: became expired in window
print(
    f"churn_proxy_{lookback}d",
    conn.execute(
        "SELECT COUNT(*) FROM users WHERE expires_at>? AND expires_at<=?",
        (since, now),
    ).fetchone()[0],
)

try:
    print(
        f"payments_{lookback}d",
        conn.execute(
            "SELECT COUNT(*) FROM payments WHERE created_at>?", (since,)
        ).fetchone()[0],
    )
except sqlite3.Error as e:
    print("payments err", type(e).__name__)

try:
    print(f"platega_{lookback}d")
    for row in conn.execute(
        """
        SELECT status, COUNT(*) FROM platega_invoices
        WHERE created_at>? GROUP BY 1 ORDER BY 2 DESC
        """,
        (since,),
    ):
        print(" ", row[0], row[1])
except sqlite3.Error as e:
    print("platega err", type(e).__name__)

print(f"client_events_{lookback}d")
try:
    for row in conn.execute(
        """
        SELECT event, COUNT(*) FROM client_events
        WHERE created_at>? GROUP BY 1 ORDER BY 2 DESC LIMIT 30
        """,
        (since,),
    ):
        print(" ", row[0], row[1])

    # Distinguish connect / tunnel / traffic-confirmed if events exist
    for label, events in (
        ("connect_attempt_events", ("connect_start", "connect_attempt", "vpn_connect")),
        ("tunnel_ok_events", ("connect_ok", "tunnel_up", "vpn_connected")),
        ("traffic_confirmed_events", ("softprobe_ok", "traffic_ok", "egress_ok")),
    ):
        q = ",".join("?" for _ in events)
        n = conn.execute(
            f"SELECT COUNT(*) FROM client_events WHERE event IN ({q}) AND created_at>?",
            (*events, since),
        ).fetchone()[0]
        print(label, n)

    print("by_platform_version")
    for row in conn.execute(
        """
        SELECT COALESCE(platform,'?'), COALESCE(brand,'?'), COALESCE(app_version,'?'), COUNT(*)
        FROM client_events WHERE created_at>?
        GROUP BY 1,2,3 ORDER BY 4 DESC LIMIT 30
        """,
        (since,),
    ):
        print(" ", row)

    print("connect_ok_by_country")
    for row in conn.execute(
        """
        SELECT COALESCE(country_id,'?'), COUNT(*) FROM client_events
        WHERE event='connect_ok' AND created_at>? GROUP BY 1 ORDER BY 2 DESC
        """,
        (since,),
    ):
        print(" ", row[0], row[1])

    print("errors_by_event")
    for row in conn.execute(
        """
        SELECT event, COUNT(*) FROM client_events
        WHERE created_at>? AND (event LIKE '%fail%' OR event LIKE '%error%' OR event LIKE '%timeout%')
        GROUP BY 1 ORDER BY 2 DESC LIMIT 20
        """,
        (since,),
    ):
        print(" ", row[0], row[1])
except sqlite3.Error as e:
    print("events err", type(e).__name__)

# Diagnostic account presence (no UUID printed)
try:
    row = conn.execute(
        "SELECT active, expires_at FROM users WHERE public_id='CI-E2E' LIMIT 1"
    ).fetchone()
    if row:
        print(
            "ci_e2e_account",
            "active=" + str(row[0]),
            "expires_ok=" + str(row[1] > now),
        )
    else:
        print("ci_e2e_account MISSING")
except sqlite3.Error:
    print("ci_e2e_account n/a")

print("STATUS=OK")
print("DONE")
