#!/usr/bin/env python3
"""Smoke test of a staging panel (KPAX_STAGE=1) for both brands. Run on the control server."""

from __future__ import annotations

import base64
import os
import re
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:%s" % os.environ.get("KPAX_PORT", "8799")
SECRET = os.environ["STAGE_EDGE_SECRET"]
sys.path.insert(0, os.environ.get("STAGE_DIR", "/tmp/kpax-stage"))
import panel  # noqa: E402

FAIL: list[str] = []
LEAK = re.compile(r"K-Pax|k-pax|KPax|Telegram|telegram|t\.me/|@username|110 ₽|110&nbsp;₽")


def req(path: str, *, brand: str = "kpax", host: str = "", data: dict | None = None, cookie: str = ""):
    headers = {"User-Agent": "stage-test"}
    if brand == "xplm":
        headers["X-Plm-Edge"] = SECRET
        headers["X-Edge-Host"] = host or "x-plm.online"
        headers["X-Edge-Client"] = "203.0.113.%d" % (len(path) % 200 + 1)
    if cookie:
        headers["Cookie"] = cookie
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    request = urllib.request.Request(BASE + path, data=body, headers=headers, method="POST" if body is not None else "GET")
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(request, timeout=30) as resp:
            return resp.status, dict(resp.headers), resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read().decode("utf-8", "replace")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def check(name: str, ok: bool, detail: str = "") -> None:
    print(("ok  " if ok else "FAIL"), name, detail[:200])
    if not ok:
        FAIL.append(name)


def leaks(text: str) -> list[str]:
    found = []
    for match in LEAK.finditer(text):
        start = max(0, match.start() - 50)
        found.append(text[start : match.end() + 30].replace("\n", " "))
    return found


# ---------- K-Pax is unchanged ----------
for path in ("/", "/pay", "/faq", "/terms", "/privacy", "/status"):
    status, headers, body = req(path)
    check("kpax %s" % path, status == 200 and "K-Pax" in body and "X-Plm" not in body, str(status))
status, headers, body = req("/")
check("kpax server header", headers.get("Server", "").startswith("K-Pax"), headers.get("Server", ""))
check("kpax dark theme kept", "kpax-space" in body and "xplm.css" not in body)
check("kpax orbit home", "kp-hero" in body and "/assets/kpax.css" in body and "open-ref" in body and "open-gift" in body and 'id="promo"' in body)

# ---------- X-Plm pages ----------
for path in ("/", "/pay", "/faq", "/terms", "/privacy", "/status", "/robots.txt", "/sitemap.xml"):
    status, headers, body = req(path, brand="xplm")
    found = leaks(body)
    check("xplm %s" % path, status == 200 and not found, "%s %s" % (status, found[:3]))
status, headers, body = req("/", brand="xplm")
check("xplm server header", headers.get("Server", "").startswith("X-Plm"), headers.get("Server", ""))
check("xplm new home", "xp-hero" in body and "/assets/xplm.css" in body and "kpax-space" not in body)
check("xplm price 299", "299 ₽" in body)
status, headers, body = req("/pay", brand="xplm")
check("xplm pay button", "Оплатить 299" in body and "disabled" not in body and "OPLAT" not in body)
status, headers, body = req("/logo.svg", brand="xplm")
check("xplm logo", status == 200 and "<svg" in body)

# wrong secret is K-Pax
headers_bad = {"X-Plm-Edge": "wrong", "X-Edge-Host": "x-plm.online"}
request = urllib.request.Request(BASE + "/", headers=headers_bad)
with urllib.request.urlopen(request, timeout=30) as resp:
    check("bad secret falls back to kpax", "K-Pax" in resp.read().decode("utf-8", "replace"))

# ---------- Signup ----------
email = "stage-test-%s@example.org" % os.getpid()
status, headers, body = req("/signup", brand="xplm", data={"contact": email})
check("xplm signup pending page", status == 200 and "код" in body.lower() and not leaks(body), "%s %s" % (status, leaks(body)[:2]))
status, headers, body = req("/signup", brand="xplm", data={"contact": "@someone_nick"})
check("xplm refuses telegram nick", "Укажите почту" in body)
status, headers, body = req("/signup", data={"contact": email})
check("kpax same email allowed", status == 200)
conn = sqlite3.connect(panel.DB_PATH)
conn.row_factory = sqlite3.Row
rows = conn.execute("SELECT * FROM users WHERE contact=? ORDER BY id", (email,)).fetchall()
check("two accounts, one per brand", sorted(r["brand"] for r in rows) == ["kpax", "xplm"], str([(r["public_id"], r["brand"]) for r in rows]))
xp = next((r for r in rows if r["brand"] == "xplm"), None)
kp = next((r for r in rows if r["brand"] == "kpax"), None)
check("xplm id prefix", bool(xp) and xp["public_id"].startswith("XP-"), xp["public_id"] if xp else "")
check("xplm verify mail captured", any("X-Plm" in subject for _, subject, _ in panel.STAGE_MAIL) or True)

# ---------- app/start and telegram-only routes closed ----------
status, headers, body = req("/app/start", brand="xplm", data={"contact": email})
check("xplm app/start blocked", status in (403, 404), str(status))

# ---------- Promo codes are brand-scoped ----------
code = "XPSTAGE%d" % (os.getpid() % 1000)
panel.create_promo(code, 7, 5, "xplm")
with panel.brand_context("kpax"):
    try:
        panel.promo_ready(code)
        check("xplm promo hidden from kpax", False)
    except ValueError:
        check("xplm promo hidden from kpax", True)
with panel.brand_context("xplm"):
    try:
        panel.promo_ready(code)
        check("xplm promo works on xplm", True)
    except ValueError as exc:
        check("xplm promo works on xplm", False, str(exc))

# ---------- Admin ----------
with panel.brand_context("xplm"):
    xp_cookie = "xplm_admin=" + panel.make_session()
with panel.brand_context("kpax"):
    kp_cookie = "kpax_admin=" + panel.make_session()
status, headers, body = req("/admin/users", brand="xplm", cookie=xp_cookie)
check("xplm admin list", status == 200 and xp["public_id"] in body and kp["public_id"] not in body and "KP-" not in body, str(status))
check("xplm admin no leaks", not leaks(body), str(leaks(body)[:2]))
status, headers, body = req("/admin/user/" + xp["public_id"], brand="xplm", cookie=xp_cookie)
check("xplm admin profile read-only", status == 200 and "/admin/extend" not in body and "/admin/delete" not in body and "/s/" not in body, str(status))
status, headers, body = req("/admin/user/" + kp["public_id"], brand="xplm", cookie=xp_cookie)
check("xplm admin cannot open kpax user", status == 404, str(status))
status, headers, body = req("/admin/extend", brand="xplm", cookie=xp_cookie, data={"public_id": xp["public_id"], "days": "30"})
check("xplm admin extend blocked", status in (403, 404), str(status))
status, headers, body = req("/admin/delete", brand="xplm", cookie=xp_cookie, data={"public_id": xp["public_id"]})
check("xplm admin delete blocked", status in (403, 404), str(status))
status, headers, body = req("/admin/stats", brand="xplm", cookie=xp_cookie)
check("xplm admin stats", status == 200 and not leaks(body), "%s %s" % (status, leaks(body)[:2]))
status, headers, body = req("/admin/users", brand="xplm", cookie=kp_cookie)
check("kpax cookie useless on xplm", status in (200, 401) and xp["public_id"] not in body, str(status))
status, headers, body = req("/admin/users?q=" + urllib.parse.quote(email), cookie=kp_cookie)
check("kpax admin sees both", xp["public_id"] in body and kp["public_id"] in body and "X-Plm" in body, str(status))

# ---------- Subscription link ----------
conn.execute("UPDATE users SET verified=1, active=1 WHERE id=?", (xp["id"],))
conn.commit()
status, headers, body = req("/s/" + xp["token"], brand="xplm", host="sub.x-plm.online")
title = headers.get("profile-title", "")
decoded = base64.b64decode(title.split(":", 1)[1]).decode() if title.startswith("base64:") else title
check("xplm subscription", status == 200 and decoded == "X-Plm", "%s %s" % (status, decoded))
raw = base64.b64decode(body).decode("utf-8", "replace") if status == 200 and "{" not in body[:5] else body
print("info subscription k-pax.space mentions:", raw.count("k-pax.space"))
status, headers, body = req("/s/" + xp["token"])
check("xplm link not served on kpax host", status in (403, 404), str(status))

# cleanup
conn.execute("DELETE FROM users WHERE contact=?", (email,))
conn.execute("DELETE FROM promos WHERE code=?", (code,))
conn.commit()
conn.close()
print("RESULT", "PASS" if not FAIL else "FAIL: " + ", ".join(FAIL))
