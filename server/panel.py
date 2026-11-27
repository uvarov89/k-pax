#!/usr/bin/env python3
"""K-Pax account panel: signup, personal subscription link, push to exit nodes."""

from __future__ import annotations

import base64
import hashlib
import hmac
import html
import imaplib
import os
import queue
import smtplib
import sys
import uuid
import json
import re
import secrets
import socket
import ssl
import sqlite3
import struct
import subprocess
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from email.parser import BytesParser
from email.policy import default as email_policy
from email.utils import parseaddr
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, urlparse

import qrcodegen
import kpax_templates
import xplm_templates

CONFIG_PATH = os.environ.get("KPAX_CONFIG") if os.environ.get("KPAX_STAGE") == "1" else None
CONFIG_PATH = CONFIG_PATH or "/etc/k-pax/config.json"
LOGO_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logo.png")
DB_PATH = "/var/lib/k-pax/k-pax.db"
HOST = "127.0.0.1"
PORT = 8787
TRIAL_DAYS = 14
REFERRAL_DAYS = 15
HAPP_PROVIDER_ID = "07f8ajp6"
WINDOWS_APP_VERSION = "1.0.81"
# Public site links stay on k-pax.space; GitHub assets are for redirects + updater JSON.
WINDOWS_APP_URL = "https://k-pax.space/download/windows"
WINDOWS_APP_ASSET = (
    "https://github.com/uvarov89/k-pax/releases/download/"
    "v1.0.81-windows/K-Pax-Setup-1.0.81.exe"
)
ANDROID_APP_VERSION = "1.0.83"
ANDROID_APP_URL = "https://k-pax.space/download/android"
ANDROID_APP_ASSET = (
    "https://github.com/uvarov89/k-pax/releases/download/"
    "v1.0.83/K-Pax-1.0.83.apk"
)
XPLM_ANDROID_APP_VERSION = "1.0.83"
# Public download links stay on x-plm.online (no github.com/.../k-pax in UI).
XPLM_ANDROID_APP_URL = "https://x-plm.online/download/android"
XPLM_ANDROID_APP_ASSET = (
    "https://github.com/uvarov89/k-pax/releases/download/"
    "v1.0.83-xplm/X-Plm-1.0.83.apk"
)
XPLM_WINDOWS_APP_VERSION = "1.0.81"
XPLM_WINDOWS_APP_URL = "https://x-plm.online/download/windows"
XPLM_WINDOWS_APP_ASSET = (
    "https://github.com/uvarov89/k-pax/releases/download/"
    "v1.0.81-xplm-windows/X-Plm-Setup-1.0.81.exe"
)
GRPC_PORT = 8443
GRPC_SERVICE = "kpax"
DEVICE_LIMIT = 2
DEVICE_TTL = 45
CLIENT_EVENTS_MAX = 50
CLIENT_EVENTS_BODY_MAX = 64 * 1024
CLIENT_EVENTS_RATE = 120
CLIENT_EVENTS_RATE_WINDOW = 60
CLIENT_EVENTS_RETENTION = 14 * 86400
CLIENT_EVENTS_ERROR_MAX = 200
CLIENT_EVENT_NAMES = frozenset(
    {
        "app_start",
        "connect_start",
        "connect_ok",
        "connect_fail",
        "connect_hang",
        "failover_try",
        "probe_fail",
        "tunnel_drop",
        "disconnect",
        "update_fail",
    }
)
CLIENT_EVENT_ERROR_NAMES = frozenset(
    {
        "connect_fail",
        "probe_fail",
        "tunnel_drop",
        "connect_hang",
        "update_fail",
    }
)
CLIENT_EVENT_RU = {
    "connect_fail": "Подключение не удалось",
    "probe_fail": "Проба не прошла",
    "tunnel_drop": "Туннель оборвался",
    "connect_hang": "Подключение зависло",
    "update_fail": "Обновление не удалось",
}
CLIENT_AUTOTEST_TIMEOUT = 3
CLIENT_AUTOTEST_DEBOUNCE = 30
# Collapse burst failover probe_fail rows (same user+host+port) into one incident.
CLIENT_PROBE_FAIL_INCIDENT_DEBOUNCE = 90
CLIENT_INCIDENT_DESC_MAX = 240
MSK = timezone(timedelta(hours=3))
LOCK = threading.Lock()
DEVICE_LOCK = threading.Lock()
DEVICE_SEEN: dict[str, dict[str, dict[str, float]]] = {}
# user_key -> set of IPs to force-close on the next node report
DEVICE_KICK: dict[str, set[str]] = {}
CLIENT_SEEN: dict[str, dict[str, float]] = {}
# user_key -> {android|ios|windows: last_seen_ts} for admin «ОС» column
PLATFORM_SEEN: dict[str, dict[str, float]] = {}
PLATFORM_LABELS = {
    "android": "Android",
    "ios": "iOS",
    "windows": "Windows",
}
# Compact admin table marks (full names stay in PLATFORM_LABELS for messages).
PLATFORM_MARKS = {
    "android": "A",
    "ios": "IOS",
    "windows": "W",
}
NODE_HEALTH: dict[str, dict] = {}
FLOW_SEEN: dict[str, tuple[int, int, str]] = {}
LIVE_NODES: dict[str, dict[str, dict]] = {}
HOST_REPORT_AT: dict[str, float] = {}
HOST_MINUTE: dict[str, int] = {}
ONLINE_MINUTE_SEEN = 0
ALERT_DOWN: set[str] = set()
ALERT_FRONT_PARTIAL: set[str] = set()
ALERT_FRONT_LIMIT: set[str] = set()
ALERT_MEDIA_HTTPS: set[str] = set()
PANEL_STARTED = time.time()
ALERT_AFTER = 90
ALERT_EVERY = 20
FRONT_LIMIT_AFTER = 180
NODE_WS_PORT = 10086
PROBE_TIMEOUT = 5
PROBE_FAILS_ALERT = 3
PROBE_FAILS: dict[str, int] = {}
PROBE_DOWN: set[str] = set()
# Front/media alerts used to fire on a single TCP blip (AdminVPS flap spam).
# Require the same consecutive-fail budget as EU spare-channel probes.
FRONT_PORT_FAILS: dict[str, int] = {}
FRONT_PARTIAL_FAILS: dict[str, int] = {}
MEDIA_HTTPS_FAILS: dict[str, int] = {}
CLIENT_TTL = 7 * 86400
MEDIA_HTTPS_HOST = "media.nastolkashop.store"

STAGE = os.environ.get("KPAX_STAGE") == "1"
if STAGE:
    CONFIG_PATH = os.environ.get("KPAX_CONFIG") or CONFIG_PATH
    DB_PATH = os.environ.get("KPAX_DB") or DB_PATH
    PORT = int(os.environ.get("KPAX_PORT") or "8799")
CFG = json.load(open(CONFIG_PATH, encoding="utf-8"))

BRANDS: dict[str, dict] = {
    "kpax": {
        "id": "kpax",
        "name": "K-Pax",
        "host": "k-pax.space",
        "sub_host": "sub.k-pax.space",
        "prefix": "KP",
        "price": 110,
        "telegram": True,
        "payments": True,
        "admin_totp": True,
        "cookie": "kpax_admin",
        "happ_provider": "2swyZbeJ",
        "channel": "https://t.me/kpaxvpn",
    },
    "xplm": {
        "id": "xplm",
        "name": "X-Plm",
        "host": "x-plm.online",
        "sub_host": "sub.x-plm.online",
        "prefix": "XP",
        "price": 299,
        "telegram": False,
        "payments": True,
        "admin_totp": False,
        "cookie": "xplm_admin",
        # Each Happ Provider ID is bound to its subscription domain in the Happ cabinet.
        "happ_provider": HAPP_PROVIDER_ID,
    },
}
BRAND_STATE = threading.local()


def brand_id() -> str:
    return getattr(BRAND_STATE, "id", "kpax")


def brand() -> dict:
    return BRANDS[brand_id()]


def cdn_host() -> str:
    """Hostname for WS/XHTTP front (Cloudflare). Brand override, else global for K-Pax, else site host."""
    override = str(brand_cfg().get("cdn_host") or "").strip().lower()
    if override:
        return override
    if brand_id() == "kpax":
        global_host = str(CFG.get("cdn_host") or "").strip().lower()
        if global_host:
            return global_host
    return brand()["host"]


def is_xplm() -> bool:
    return brand_id() == "xplm"


class brand_context:
    """Run a block as one brand: texts, links, mail and admin settings follow it."""

    def __init__(self, bid: str | None) -> None:
        self.bid = bid if bid in BRANDS else "kpax"
        self.prev = "kpax"

    def __enter__(self) -> None:
        self.prev = brand_id()
        BRAND_STATE.id = self.bid

    def __exit__(self, *exc) -> None:
        BRAND_STATE.id = self.prev


def brand_cfg(bid: str | None = None) -> dict:
    return dict((CFG.get("brands") or {}).get(bid or brand_id()) or {})


def brand_mail(bid: str | None = None) -> dict | None:
    bid = bid or brand_id()
    mail = CFG.get("mail_restore") if bid == "kpax" else brand_cfg(bid).get("mail")
    return mail if isinstance(mail, dict) and mail.get("user") else None


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=15)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with LOCK:
        conn = db()
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                public_id TEXT UNIQUE NOT NULL,
                token TEXT UNIQUE NOT NULL,
                contact TEXT NOT NULL,
                uuid TEXT NOT NULL,
                hy2_password TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                active INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS signup_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS restore_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                contact TEXT NOT NULL,
                channel TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS referrals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                referrer_id INTEGER NOT NULL,
                friend_id INTEGER NOT NULL UNIQUE,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS payments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                days INTEGER NOT NULL,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS platega_invoices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                transaction_id TEXT UNIQUE NOT NULL,
                user_id INTEGER NOT NULL,
                public_id TEXT NOT NULL,
                amount INTEGER NOT NULL,
                currency TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS notices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                kind TEXT NOT NULL,
                ref TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL,
                UNIQUE(user_id, kind, ref)
            );
            CREATE TABLE IF NOT EXISTS promos (
                code TEXT PRIMARY KEY,
                days INTEGER NOT NULL,
                max_uses INTEGER NOT NULL,
                used INTEGER NOT NULL DEFAULT 0,
                active INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS promo_uses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT NOT NULL,
                user_id INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                UNIQUE(code, user_id)
            );
            """
        )
        cols = {row[1] for row in conn.execute("PRAGMA table_info(platega_invoices)")}
        if "redirect" not in cols:
            conn.execute("ALTER TABLE platega_invoices ADD COLUMN redirect TEXT NOT NULL DEFAULT ''")
        user_cols = {row[1] for row in conn.execute("PRAGMA table_info(users)")}
        if "telegram_chat_id" not in user_cols:
            conn.execute("ALTER TABLE users ADD COLUMN telegram_chat_id INTEGER")
        if "verified" not in user_cols:
            conn.execute("ALTER TABLE users ADD COLUMN verified INTEGER NOT NULL DEFAULT 1")
        if "verify_token" not in user_cols:
            conn.execute("ALTER TABLE users ADD COLUMN verify_token TEXT NOT NULL DEFAULT ''")
        if "verify_code" not in user_cols:
            conn.execute("ALTER TABLE users ADD COLUMN verify_code TEXT NOT NULL DEFAULT ''")
        if "verify_sent_at" not in user_cols:
            conn.execute("ALTER TABLE users ADD COLUMN verify_sent_at INTEGER NOT NULL DEFAULT 0")
        if "pending_ref" not in user_cols:
            conn.execute("ALTER TABLE users ADD COLUMN pending_ref TEXT NOT NULL DEFAULT ''")
        if "pending_promo" not in user_cols:
            conn.execute("ALTER TABLE users ADD COLUMN pending_promo TEXT NOT NULL DEFAULT ''")
        if "partner" not in user_cols:
            conn.execute("ALTER TABLE users ADD COLUMN partner TEXT NOT NULL DEFAULT ''")
        if "telegram_nick" not in user_cols:
            conn.execute("ALTER TABLE users ADD COLUMN telegram_nick TEXT NOT NULL DEFAULT ''")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS partners (
                code TEXT NOT NULL,
                brand TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                active INTEGER NOT NULL DEFAULT 1,
                PRIMARY KEY (code, brand)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS captcha_hits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """
        )
        if "brand" not in {row[1] for row in conn.execute("PRAGMA table_info(users)")}:
            conn.execute("ALTER TABLE users ADD COLUMN brand TEXT NOT NULL DEFAULT 'kpax'")
        if "brand" not in {row[1] for row in conn.execute("PRAGMA table_info(promos)")}:
            conn.execute("ALTER TABLE promos ADD COLUMN brand TEXT NOT NULL DEFAULT 'kpax'")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS spare_creds (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT UNIQUE NOT NULL,
                hy2_password TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS user_seen (
                user_key TEXT PRIMARY KEY,
                first_seen INTEGER NOT NULL,
                last_seen INTEGER NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS pending_removals (
                uuid TEXT PRIMARY KEY,
                hy2_password TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )
            """
        )
        if "source" not in {row[1] for row in conn.execute("PRAGMA table_info(payments)")}:
            conn.execute("ALTER TABLE payments ADD COLUMN source TEXT NOT NULL DEFAULT 'pay'")
            # Older rows have no source: a row without a confirmed invoice next to it came from the admin button.
            conn.execute(
                """
                UPDATE payments SET source='admin' WHERE NOT EXISTS (
                    SELECT 1 FROM platega_invoices i
                    WHERE i.user_id=payments.user_id AND i.status='CONFIRMED'
                      AND ABS(i.updated_at - payments.created_at) <= 300
                )
                """
            )
        conn.execute("CREATE INDEX IF NOT EXISTS users_brand_contact ON users(brand, contact)")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS app_login (
                token TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                brand TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                ready_at INTEGER NOT NULL DEFAULT 0,
                consumed_at INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        app_login_cols = {row[1] for row in conn.execute("PRAGMA table_info(app_login)")}
        if "code_hash" not in app_login_cols:
            conn.execute(
                "ALTER TABLE app_login ADD COLUMN code_hash TEXT NOT NULL DEFAULT ''"
            )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS app_login_user ON app_login(user_id, created_at)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS users_brand_telegram_nick ON users(brand, telegram_nick)"
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS cash_refunds (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                brand TEXT NOT NULL,
                amount INTEGER NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS cash_refunds_brand_created ON cash_refunds(brand, created_at)"
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS client_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at INTEGER NOT NULL,
                user_key TEXT NOT NULL,
                brand TEXT NOT NULL DEFAULT '',
                app_version TEXT NOT NULL DEFAULT '',
                platform TEXT NOT NULL DEFAULT '',
                session_id TEXT NOT NULL DEFAULT '',
                event TEXT NOT NULL,
                country_id TEXT NOT NULL DEFAULT '',
                kind TEXT NOT NULL DEFAULT '',
                port INTEGER NOT NULL DEFAULT 0,
                host TEXT NOT NULL DEFAULT '',
                error_code TEXT NOT NULL DEFAULT '',
                error TEXT NOT NULL DEFAULT '',
                attempt INTEGER NOT NULL DEFAULT 0,
                connected_ms INTEGER NOT NULL DEFAULT 0,
                up_total INTEGER NOT NULL DEFAULT 0,
                down_total INTEGER NOT NULL DEFAULT 0,
                client_ip TEXT NOT NULL DEFAULT '',
                severity TEXT NOT NULL DEFAULT 'info'
            )
            """
        )
        event_cols = {row[1] for row in conn.execute("PRAGMA table_info(client_events)")}
        if "severity" not in event_cols:
            conn.execute(
                "ALTER TABLE client_events ADD COLUMN severity TEXT NOT NULL DEFAULT 'info'"
            )
        # Idempotent: repair rows left as info after a partial/manual severity migrate.
        conn.execute(
            """
            UPDATE client_events
            SET severity='error'
            WHERE IFNULL(severity, 'info') != 'error'
              AND event IN ('connect_fail','probe_fail','tunnel_drop','connect_hang','update_fail')
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS client_events_user_created ON client_events(user_key, created_at DESC)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS client_events_event_created ON client_events(event, created_at DESC)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS client_events_severity_created ON client_events(severity, created_at DESC)"
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS client_incidents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                user_key TEXT NOT NULL,
                brand TEXT NOT NULL DEFAULT '',
                session_id TEXT NOT NULL DEFAULT '',
                trigger_event TEXT NOT NULL DEFAULT '',
                error_code TEXT NOT NULL DEFAULT '',
                error TEXT NOT NULL DEFAULT '',
                host TEXT NOT NULL DEFAULT '',
                port INTEGER NOT NULL DEFAULT 0,
                country_id TEXT NOT NULL DEFAULT '',
                kind TEXT NOT NULL DEFAULT '',
                platform TEXT NOT NULL DEFAULT '',
                app_version TEXT NOT NULL DEFAULT '',
                description TEXT NOT NULL DEFAULT '',
                autotest_status TEXT NOT NULL DEFAULT 'pending',
                autotest_note TEXT NOT NULL DEFAULT '',
                client_ip TEXT NOT NULL DEFAULT ''
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS client_incidents_created ON client_incidents(created_at DESC)"
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS client_incidents_autotest_created
            ON client_incidents(autotest_status, created_at DESC)
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS client_incidents_user_created
            ON client_incidents(user_key, created_at DESC)
            """
        )
        conn.commit()
        conn.close()


def now_ts() -> int:
    return int(time.time())


def admit_devices(reports: list[dict], now: float, state: dict, limit: int = DEVICE_LIMIT, ttl: int = DEVICE_TTL) -> list[str]:
    """Remember places that are online and return connection ids past the device limit."""
    for item in reports:
        slots = state.setdefault(item["user"], {})
        slot = slots.get(item["ip"])
        if slot is None:
            slots[item["ip"]] = {"first": now, "last": now}
        else:
            slot["last"] = now
    for user, slots in list(state.items()):
        for ip, slot in list(slots.items()):
            if now - slot["last"] > ttl:
                del slots[ip]
        if not slots:
            del state[user]
    close: list[str] = []
    for item in reports:
        kicks = DEVICE_KICK.get(item["user"]) or set()
        if item["ip"] in kicks:
            close.extend(item["ids"])
            kicks.discard(item["ip"])
            if not kicks:
                DEVICE_KICK.pop(item["user"], None)
            slots = state.get(item["user"], {})
            slots.pop(item["ip"], None)
            if not slots:
                state.pop(item["user"], None)
            continue
        slots = state.get(item["user"], {})
        ranked = sorted(slots, key=lambda ip: (slots[ip]["first"], ip))
        if item["ip"] not in set(ranked[:limit]):
            close.extend(item["ids"])
    return close


def mask_device_ip(ip: str) -> str:
    text = (ip or "").strip()
    if ":" in text:
        parts = text.split(":")
        if len(parts) >= 2:
            return parts[0] + ":…:" + parts[-1]
        return "…"
    parts = text.split(".")
    if len(parts) == 4:
        return parts[0] + "." + parts[1] + ".*.*"
    return "…"


def devices_for_token(token: str) -> tuple[dict | None, str]:
    token = (token or "").strip()
    if len(token) < 16 or "/" in token:
        return None, "bad_token"
    with LOCK:
        conn = db()
        user = conn.execute(
            "SELECT * FROM users WHERE token=? AND brand=? LIMIT 1",
            (token, brand_id()),
        ).fetchone()
        conn.close()
    if user is None:
        return None, "not_found"
    key = user_key(str(user["uuid"]))
    now = time.time()
    devices = []
    with DEVICE_LOCK:
        slots = dict(DEVICE_SEEN.get(key) or {})
        labels = [
            name
            for name, seen in sorted(
                (CLIENT_SEEN.get(key) or {}).items(),
                key=lambda item: -item[1],
            )
            if now - seen <= CLIENT_TTL
        ]
        for index, (ip, slot) in enumerate(
            sorted(slots.items(), key=lambda item: item[1].get("first", 0))
        ):
            label = labels[index] if index < len(labels) else "Устройство"
            devices.append(
                {
                    "id": ip,
                    "label": label,
                    "detail": mask_device_ip(ip),
                    "online": True,
                }
            )
    return {
        "limit": DEVICE_LIMIT,
        "online": len(devices),
        "devices": devices,
    }, ""


def kick_device_for_token(token: str, device_id: str) -> tuple[bool, str]:
    payload, error = devices_for_token(token)
    if error:
        return False, error
    device_id = (device_id or "").strip()
    if not device_id:
        return False, "bad_device"
    with LOCK:
        conn = db()
        user = conn.execute(
            "SELECT uuid FROM users WHERE token=? AND brand=? LIMIT 1",
            (token.strip(), brand_id()),
        ).fetchone()
        conn.close()
    if user is None:
        return False, "not_found"
    key = user_key(str(user["uuid"]))
    with DEVICE_LOCK:
        slots = DEVICE_SEEN.get(key) or {}
        if device_id not in slots:
            return False, "missing"
        slots.pop(device_id, None)
        if not slots:
            DEVICE_SEEN.pop(key, None)
        DEVICE_KICK.setdefault(key, set()).add(device_id)
    return True, ""


def user_for_app_token(token: str) -> tuple[sqlite3.Row | None, str]:
    token = (token or "").strip()
    if len(token) < 16 or "/" in token:
        return None, "bad_token"
    with LOCK:
        conn = db()
        user = conn.execute(
            "SELECT * FROM users WHERE token=? AND brand=? LIMIT 1",
            (token, brand_id()),
        ).fetchone()
        conn.close()
    if user is None:
        return None, "not_found"
    return user, ""


def client_events_limited(key: str, count: int) -> bool:
    now = now_ts()
    with LOCK:
        hits = [
            stamp
            for stamp in CLIENT_EVENT_HITS.get(key, [])
            if now - stamp < CLIENT_EVENTS_RATE_WINDOW
        ]
        CLIENT_EVENT_HITS[key] = hits
        return len(hits) + max(0, count) > CLIENT_EVENTS_RATE


def note_client_events(key: str, count: int) -> None:
    if count <= 0:
        return
    now = now_ts()
    with LOCK:
        hits = [
            stamp
            for stamp in CLIENT_EVENT_HITS.get(key, [])
            if now - stamp < CLIENT_EVENTS_RATE_WINDOW
        ]
        hits.extend([now] * count)
        CLIENT_EVENT_HITS[key] = hits


def purge_old_client_events(conn: sqlite3.Connection) -> None:
    cutoff = now_ts() - CLIENT_EVENTS_RETENTION
    conn.execute("DELETE FROM client_events WHERE created_at < ?", (cutoff,))
    conn.execute("DELETE FROM client_incidents WHERE created_at < ?", (cutoff,))


def client_event_severity(event: str) -> str:
    return "error" if event in CLIENT_EVENT_ERROR_NAMES else "info"


def client_event_description(row: dict) -> str:
    event = str(row.get("event") or "")
    head = CLIENT_EVENT_RU.get(event, event)
    country = str(row.get("country_id") or "").strip()
    port = int(row.get("port") or 0)
    kind = str(row.get("kind") or "").strip()
    mid_bits: list[str] = []
    if country and port:
        mid_bits.append("%s:%d" % (country, port))
    elif country:
        mid_bits.append(country)
    elif port:
        mid_bits.append(":%d" % port)
    if kind:
        mid_bits.append(kind)
    err = str(row.get("error") or row.get("error_code") or "").strip()
    text = "%s (%s)" % (head, event)
    if mid_bits:
        text += " " + " ".join(mid_bits)
    if err:
        text += " — " + err
    return _clip_text(text, CLIENT_INCIDENT_DESC_MAX)


def _clip_text(value: object, limit: int) -> str:
    text = re.sub(r"\s+", " ", str(value or "").strip())
    if len(text) > limit:
        return text[:limit]
    return text


def _safe_host(value: object) -> str:
    host = _clip_text(value, 128).lower()
    if not host:
        return ""
    # Host/exit only — reject URLs, paths, query tokens, UUIDs.
    if "://" in host or "/" in host or "?" in host or "#" in host or "@" in host:
        return ""
    if "vless://" in host or "hysteria" in host or "uuid" in host:
        return ""
    if not re.fullmatch(r"[a-z0-9][a-z0-9.\-:]{0,126}", host):
        return ""
    return host


def _safe_int(value: object, *, minimum: int = 0, maximum: int = 2_000_000_000) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        return 0
    if number < minimum:
        return minimum
    if number > maximum:
        return maximum
    return number


def normalize_client_event(raw: object, *, session_id: str, client_ip: str) -> dict | None:
    if not isinstance(raw, dict):
        return None
    event = _clip_text(raw.get("event"), 32)
    if event not in CLIENT_EVENT_NAMES:
        return None
    brand_raw = _clip_text(raw.get("brand"), 16).lower()
    if brand_raw not in BRANDS:
        brand_raw = brand_id()
    platform = _clip_text(raw.get("platform"), 16).lower()
    if platform not in ("android", "ios", "windows"):
        platform = ""
    sid = _clip_text(raw.get("session_id") or session_id, 64)
    if re.search(r"(https?://|/s/|vless://|uuid)", sid, re.I):
        sid = ""
    error = _clip_text(raw.get("error"), CLIENT_EVENTS_ERROR_MAX)
    if re.search(r"(https?://|/s/|vless://|hysteria|uuid=)", error, re.I):
        error = _clip_text(re.sub(r"(https?://\S+|/s/\S+|vless://\S+)", "[redacted]", error), CLIENT_EVENTS_ERROR_MAX)
    ts = _safe_int(raw.get("ts"), maximum=4_000_000_000)
    if ts <= 0:
        ts = now_ts()
    return {
        "ts": ts,
        "brand": brand_raw,
        "app_version": _clip_text(raw.get("app_version"), 32),
        "platform": platform,
        "session_id": sid,
        "event": event,
        "country_id": _clip_text(raw.get("country_id"), 16).lower(),
        "kind": _clip_text(raw.get("kind"), 32),
        "port": _safe_int(raw.get("port"), maximum=65535),
        "host": _safe_host(raw.get("host")),
        "error_code": _clip_text(raw.get("error_code"), 64),
        "error": error,
        "attempt": _safe_int(raw.get("attempt"), maximum=1000),
        "connected_ms": _safe_int(raw.get("connected_ms")),
        "up_total": _safe_int(raw.get("up_total")),
        "down_total": _safe_int(raw.get("down_total")),
        "client_ip": _clip_text(client_ip, 64),
    }


def _update_incident_autotest(
    conn: sqlite3.Connection,
    incident_id: int,
    status: str,
    note: str,
) -> None:
    conn.execute(
        """
        UPDATE client_incidents
        SET autotest_status=?, autotest_note=?, updated_at=?
        WHERE id=?
        """,
        (_clip_text(status, 16), _clip_text(note, 120), now_ts(), int(incident_id)),
    )


def _host_is_literal_ip(host: str) -> bool:
    text = (host or "").strip()
    if not text:
        return False
    try:
        socket.inet_pton(socket.AF_INET, text)
        return True
    except OSError:
        pass
    try:
        socket.inet_pton(socket.AF_INET6, text)
        return True
    except OSError:
        return False


def probe_client_host_port(host: str, port: int) -> tuple[str, str]:
    """TCP reachability from the panel host. Returns (status, note)."""
    target = (host or "").strip()
    if not target or port <= 0 or port > 65535:
        return "skip", "no_host_port"
    ip = target
    if not _host_is_literal_ip(target):
        try:
            infos = socket.getaddrinfo(target, port, type=socket.SOCK_STREAM)
        except OSError:
            return "fail", "dns_fail"
        if not infos:
            return "fail", "dns_fail"
        ip = infos[0][4][0]
    sock = None
    try:
        family = socket.AF_INET6 if ":" in str(ip) else socket.AF_INET
        sock = socket.socket(family, socket.SOCK_STREAM)
        sock.settimeout(CLIENT_AUTOTEST_TIMEOUT)
        code = sock.connect_ex((ip, int(port)))
        if code == 0:
            # Port open from the panel ≠ Reality handshake / client HTTPS path.
            return "ok", "tcp_ok (порт; не Reality/HTTPS)"
        return "fail", "tcp_fail code=%d" % code
    except OSError as exc:
        return "fail", "tcp_fail %s" % _clip_text(type(exc).__name__, 40)
    finally:
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass


def _copy_recent_autotest(
    conn: sqlite3.Connection,
    user_key_value: str,
    host: str,
    port: int,
    *,
    exclude_id: int = 0,
) -> tuple[str, str] | None:
    # Only reuse a fresh completed probe — never an hours-old row while a new
    # probe is still pending (that produced false "skip"/"ok" badges).
    since = now_ts() - max(60, int(CLIENT_AUTOTEST_DEBOUNCE) * 2)
    row = conn.execute(
        """
        SELECT autotest_status, autotest_note
        FROM client_incidents
        WHERE user_key=? AND host=? AND port=?
          AND id!=?
          AND updated_at>=?
          AND autotest_status IN ('ok','fail','skip')
        ORDER BY updated_at DESC, id DESC
        LIMIT 1
        """,
        (user_key_value, host, int(port), int(exclude_id), since),
    ).fetchone()
    if row is None:
        return None
    return str(row["autotest_status"] or "skip"), str(row["autotest_note"] or "debounced")


def _fanout_debounced_autotest(
    conn: sqlite3.Connection,
    *,
    user_key_value: str,
    host: str,
    port: int,
    source_id: int,
    status: str,
    note: str,
) -> None:
    """Copy a finished probe onto siblings left as pending/debounced."""
    stamp = now_ts()
    shared_note = note if note.startswith("debounced") else ("debounced " + note)
    conn.execute(
        """
        UPDATE client_incidents
        SET autotest_status=?, autotest_note=?, updated_at=?
        WHERE user_key=? AND host=? AND port=?
          AND id!=?
          AND autotest_status='pending'
          AND autotest_note LIKE 'debounced%'
        """,
        (
            _clip_text(status, 16),
            _clip_text(shared_note, 120),
            stamp,
            user_key_value,
            host,
            int(port),
            int(source_id),
        ),
    )


def queue_client_incident_autotest(
    incident_id: int,
    user_key_value: str,
    host: str,
    port: int,
) -> None:
    if not host or port <= 0:
        with LOCK:
            conn = db()
            _update_incident_autotest(conn, incident_id, "skip", "no_host_port")
            conn.commit()
            conn.close()
        return
    debounce_key = "%s|%s|%d" % (user_key_value, host, int(port))
    now = time.monotonic()
    with CLIENT_AUTOTEST_LOCK:
        last = CLIENT_AUTOTEST_DEBOUNCE_AT.get(debounce_key, 0.0)
        debounced = (now - last) < CLIENT_AUTOTEST_DEBOUNCE
        if not debounced:
            CLIENT_AUTOTEST_DEBOUNCE_AT[debounce_key] = now
    if debounced:
        with LOCK:
            conn = db()
            copied = _copy_recent_autotest(
                conn,
                user_key_value,
                host,
                int(port),
                exclude_id=int(incident_id),
            )
            if copied is None:
                # Probe still in flight (or none yet) — keep pending, not false skip.
                _update_incident_autotest(conn, incident_id, "pending", "debounced")
            else:
                status, note = copied
                _update_incident_autotest(
                    conn,
                    incident_id,
                    status,
                    note if note.startswith("debounced") else ("debounced " + note),
                )
            conn.commit()
            conn.close()
        return
    CLIENT_AUTOTEST_Q.put(int(incident_id))


def recent_probe_fail_incident(
    conn: sqlite3.Connection,
    key: str,
    host: str,
    port: int,
) -> int | None:
    """Return id of a fresh probe_fail incident for this endpoint, if any."""
    if not host or port <= 0:
        return None
    since = now_ts() - max(30, int(CLIENT_PROBE_FAIL_INCIDENT_DEBOUNCE))
    row = conn.execute(
        """
        SELECT id FROM client_incidents
        WHERE user_key=? AND trigger_event='probe_fail'
          AND host=? AND port=?
          AND created_at>=?
        ORDER BY created_at DESC, id DESC
        LIMIT 1
        """,
        (key, host, int(port), since),
    ).fetchone()
    if row is None:
        return None
    return int(row["id"])


def create_client_incident(conn: sqlite3.Connection, key: str, row: dict) -> int | None:
    """Insert an incident. Returns None when a recent probe_fail was debounced."""
    created = int(row.get("ts") or now_ts())
    # Failover tries every BG/DE spare in seconds — keep events, one incident.
    if str(row.get("event") or "") == "probe_fail":
        existing = recent_probe_fail_incident(
            conn, key, str(row.get("host") or ""), int(row.get("port") or 0)
        )
        if existing is not None:
            return None
    description = client_event_description(row)
    cur = conn.execute(
        """
        INSERT INTO client_incidents(
            created_at, updated_at, user_key, brand, session_id, trigger_event,
            error_code, error, host, port, country_id, kind, platform, app_version,
            description, autotest_status, autotest_note, client_ip
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', '', ?)
        """,
        (
            created,
            created,
            key,
            row["brand"],
            row["session_id"],
            row["event"],
            row["error_code"],
            row["error"],
            row["host"],
            int(row["port"] or 0),
            row["country_id"],
            row["kind"],
            row["platform"],
            row["app_version"],
            description,
            row["client_ip"],
        ),
    )
    return int(cur.lastrowid)


def run_client_incident_autotest(incident_id: int) -> None:
    with LOCK:
        conn = db()
        row = conn.execute(
            "SELECT id, user_key, host, port FROM client_incidents WHERE id=? LIMIT 1",
            (int(incident_id),),
        ).fetchone()
        conn.close()
    if row is None:
        return
    host = str(row["host"] or "")
    port = int(row["port"] or 0)
    user_key_value = str(row["user_key"] or "")
    status, note = probe_client_host_port(host, port)
    with LOCK:
        conn = db()
        _update_incident_autotest(conn, int(incident_id), status, note)
        if user_key_value and host and port > 0 and status in ("ok", "fail", "skip"):
            _fanout_debounced_autotest(
                conn,
                user_key_value=user_key_value,
                host=host,
                port=port,
                source_id=int(incident_id),
                status=status,
                note=note,
            )
        conn.commit()
        conn.close()


def client_autotest_loop() -> None:
    while True:
        incident_id = CLIENT_AUTOTEST_Q.get()
        try:
            run_client_incident_autotest(int(incident_id))
        except Exception as exc:  # noqa: BLE001
            print("client autotest", type(exc).__name__, flush=True)
        finally:
            CLIENT_AUTOTEST_Q.task_done()


def ingest_client_events(
    token: str,
    session_id: str,
    events: list,
    client_ip: str,
) -> tuple[dict | None, int, str]:
    user, error = user_for_app_token(token)
    if error or user is None:
        return None, 404, error or "not_found"
    key = user_key(str(user["uuid"]))
    if not isinstance(events, list) or not events:
        return None, 400, "empty"
    if len(events) > CLIENT_EVENTS_MAX:
        return None, 400, "too_many"
    normalized: list[dict] = []
    for item in events[:CLIENT_EVENTS_MAX]:
        row = normalize_client_event(item, session_id=session_id, client_ip=client_ip)
        if row is not None:
            row["severity"] = client_event_severity(str(row["event"]))
            normalized.append(row)
    if not normalized:
        return None, 400, "no_valid"
    if client_events_limited(key, len(normalized)):
        return None, 429, "rate"
    created = now_ts()
    autotest_jobs: list[tuple[int, str, str, int]] = []
    with LOCK:
        conn = db()
        purge_old_client_events(conn)
        conn.executemany(
            """
            INSERT INTO client_events(
                created_at, user_key, brand, app_version, platform, session_id,
                event, country_id, kind, port, host, error_code, error,
                attempt, connected_ms, up_total, down_total, client_ip, severity
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    int(row["ts"]) or created,
                    key,
                    row["brand"],
                    row["app_version"],
                    row["platform"],
                    row["session_id"],
                    row["event"],
                    row["country_id"],
                    row["kind"],
                    row["port"],
                    row["host"],
                    row["error_code"],
                    row["error"],
                    row["attempt"],
                    row["connected_ms"],
                    row["up_total"],
                    row["down_total"],
                    row["client_ip"],
                    row["severity"],
                )
                for row in normalized
            ],
        )
        for row in normalized:
            if row["severity"] != "error":
                continue
            incident_id = create_client_incident(conn, key, row)
            if incident_id is None:
                continue
            autotest_jobs.append(
                (incident_id, key, str(row["host"] or ""), int(row["port"] or 0))
            )
        conn.commit()
        conn.close()
    for row in normalized:
        remember_platform(key, str(row.get("platform") or ""))
    note_client_events(key, len(normalized))
    for incident_id, user_key_value, host, port in autotest_jobs:
        queue_client_incident_autotest(incident_id, user_key_value, host, port)
    return {"ok": True, "accepted": len(normalized)}, 200, ""


def fmt(ts: int) -> str:
    return datetime.fromtimestamp(ts, MSK).strftime("%d.%m.%Y %H:%M МСК")


def ssh(host: str, remote: str) -> str:
    result = subprocess.run(
        [
            "ssh",
            "-i",
            CFG["ssh_key"],
            "-o",
            "BatchMode=yes",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            "UserKnownHostsFile=" + CFG["known_hosts"],
            "-o",
            "ConnectTimeout=15",
            "root@" + host,
            remote,
        ],
        capture_output=True,
        text=True,
        timeout=50,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "ssh failed").strip()
        raise RuntimeError(host + ": " + detail.splitlines()[-1][:240])
    return result.stdout


# User config changes restart sing-box/Xray on that node and drop its tunnels.
# Signups take pre-added spare credentials; expired users leave in one nightly batch.
# Nightly batch is staggered across nodes so Auto can fail over instead of a global cut.
NODE_LOCK = threading.Lock()
ACTIVATE_LOCK = threading.Lock()
SPARE_TARGET = 12
NODE_MAINTENANCE_UTC = (1, 30)
# Pause only after a node that actually restarted, so live exits stay available.
MAINTENANCE_STAGGER_SEC = 60


def push_user(uuid: str, password: str, action: str) -> None:
    if STAGE:
        print("stage push skipped", action, flush=True)
        return
    with NODE_LOCK:
        if action == "add":
            with LOCK:
                conn = db()
                conn.execute("DELETE FROM pending_removals WHERE uuid=?", (uuid,))
                conn.commit()
                conn.close()
        push_user_locked(uuid, password, action)


def push_user_locked(uuid: str, password: str, action: str) -> None:
    remote = "python3 /usr/local/sbin/k-pax-user.py " + action + " " + uuid + " " + password
    errors = []
    done = []
    for node in CFG["nodes"]:
        if not node_enabled(node):
            continue
        try:
            ssh(node["host"], remote)
            done.append(node)
        except Exception as exc:  # noqa: BLE001
            errors.append("%s: %s" % (node.get("id") or node.get("host"), exc))
    if errors and action == "add":
        # Keep partial success when a maintenance/down exit fails (e.g. BG suspended).
        # Only roll back if no exit node accepted the user.
        exits_done = [n for n in done if not is_front_node(n)]
        if not exits_done:
            for node in done:
                try:
                    ssh(
                        node["host"],
                        "python3 /usr/local/sbin/k-pax-user.py remove "
                        + uuid
                        + " "
                        + password,
                    )
                except Exception:
                    pass
            raise RuntimeError("; ".join(errors))
        print("push_user partial add", "; ".join(errors), flush=True)
    if errors and action == "remove":
        raise RuntimeError("; ".join(errors))


def node_maintenance() -> None:
    """Drop expired users and top up spare credentials; stagger real restarts."""
    if STAGE:
        return
    with NODE_LOCK:
        with LOCK:
            conn = db()
            # A user who paid again after expiring keeps the key.
            conn.execute(
                "DELETE FROM pending_removals WHERE uuid IN (SELECT uuid FROM users WHERE active=1)"
            )
            conn.commit()
            removals = conn.execute("SELECT uuid, hy2_password FROM pending_removals").fetchall()
            spares = conn.execute("SELECT uuid, hy2_password FROM spare_creds").fetchall()
            conn.close()
        fresh = [
            (str(uuid.uuid4()), secrets.token_hex(16))
            for _ in range(max(0, SPARE_TARGET - len(spares)))
        ]
        # Do not re-push existing spares every night: that forced false-positive
        # restarts. Repair after a node rebuild is a separate manual sync.
        items = [
            {"action": "remove", "uuid": r["uuid"], "password": r["hy2_password"]}
            for r in removals
        ]
        items += [{"action": "add", "uuid": u, "password": p} for u, p in fresh]
        if not items:
            print("node maintenance: nothing to do", flush=True)
            return
        payload = base64.b64encode(json.dumps(items).encode()).decode()
        exit_errors = []
        front_errors = []
        remote = "python3 /usr/local/sbin/k-pax-user.py batch " + payload
        nodes = list(CFG["nodes"])
        for index, node in enumerate(nodes):
            try:
                out = ssh(node["host"], remote)
                restarted = "changed" in (out or "")
                if restarted and index + 1 < len(nodes):
                    time.sleep(MAINTENANCE_STAGGER_SEC)
            except Exception as exc:  # noqa: BLE001
                detail = "%s: %s" % (node.get("id"), str(exc)[:200])
                if is_front_node(node):
                    front_errors.append(detail)
                else:
                    exit_errors.append(detail)
        if front_errors:
            print("node maintenance front warn", "; ".join(front_errors), flush=True)
        if exit_errors:
            print("node maintenance failed", "; ".join(exit_errors), flush=True)
            return
        with LOCK:
            conn = db()
            conn.executemany(
                "DELETE FROM pending_removals WHERE uuid=?",
                [(r["uuid"],) for r in removals],
            )
            conn.executemany(
                "INSERT OR IGNORE INTO spare_creds(uuid, hy2_password, created_at) VALUES(?, ?, ?)",
                [(u, p, now_ts()) for u, p in fresh],
            )
            conn.commit()
            conn.close()
    print(
        "node maintenance: removed %d, spares +%d"
        % (len(removals), len(fresh)),
        flush=True,
    )


def spare_count() -> int:
    conn = db()
    count = conn.execute("SELECT COUNT(*) FROM spare_creds").fetchone()[0]
    conn.close()
    return int(count)


def is_front_node(node: dict) -> bool:
    """RU (and similar) entry hops: pushed to nodes, hidden from country pickers."""
    role = str(node.get("role") or "").lower()
    return role == "front" or bool(node.get("front"))


def country_name(node: dict) -> str:
    if is_front_node(node):
        return str(node.get("name") or "Russia front").strip() or "Russia front"
    titles = {"de": "Германия", "fi": "Финляндия", "bg": "Болгария"}
    return titles.get(str(node.get("id") or "").lower(), node["name"])


def front_card_label(node: dict) -> str:
    """Same subtitle shape for every RU front card: domain · IP when both exist."""
    host = str(node.get("host") or "").strip()
    domain = str(node.get("self_domain") or "").strip()
    if domain and host and domain != host:
        return "%s · %s" % (domain, host)
    return domain or host or "—"


def node_enabled(node: dict) -> bool:
    """Per-node kill switch in config.json (`"enabled": false`)."""
    return node.get("enabled", True) is not False


def front_links_in_sub() -> bool:
    """When false, RU front VLESS rows are omitted from subscriptions.
    Use while front→EU relay is blackholed (front machine up, dial to exits times out).
    """
    return CFG.get("front_links_in_sub", True) is not False


def exit_nodes() -> list[dict]:
    return [
        node
        for node in CFG["nodes"]
        if not is_front_node(node) and node_enabled(node)
    ]


def front_nodes() -> list[dict]:
    return [
        node
        for node in CFG["nodes"]
        if is_front_node(node) and node_enabled(node)
    ]


def front_port_for(front: dict, exit_id: str) -> int:
    raw = (front.get("front_ports") or {}).get(str(exit_id or "").lower())
    try:
        port = int(raw)
    except (TypeError, ValueError):
        return 0
    return port if 1 <= port <= 65535 else 0


def self_steal_host(node: dict) -> str:
    """Site name of the node's self-steal Reality: a neutral domain from the config, else its k-pax.space name."""
    if not node.get("self_steal"):
        return ""
    return str(node.get("self_domain") or grpc_host(node))


DEFAULT_REALITY_SNI = "files.nastolkashop.store"


def reality_sni(node: dict) -> str:
    """TLS serverName / ClientHello SNI for primary Reality (own-domain self-steal).

    Prefer reality_sni / reality_dest, then self_domain (VPSPay: no third-party SNI).
    Must match sing-box inbound tls.server_name; handshake is local nginx :8446.
    """
    for key in ("reality_sni", "reality_dest", "self_domain"):
        raw = str(node.get(key) or "").strip().lower()
        if re.fullmatch(r"[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?", raw):
            return raw
    return DEFAULT_REALITY_SNI


def grpc_host(node: dict) -> str:
    node_id = str(node.get("id") or "").lower()
    if node_id in ("de", "fi", "bg"):
        return node_id + ".k-pax.space"
    return str(node.get("grpc_host") or "")


TUIC_PORT = 2087
SS_METHOD = "chacha20-ietf-poly1305"


def links_for(user: sqlite3.Row, pinned_hy2: bool = False, full: bool = False) -> list[str]:
    """full keeps gRPC and TUIC: the K-Pax app switches between them itself and never shows raw rows."""
    vless = []
    grpc = []
    hy2 = []
    tuic = []
    front_vless = []
    for node in exit_nodes():
        country = country_name(node)
        exit_id = str(node.get("id") or "").lower()
        # Self-steal (:2053) before bare :443 — from RF/MSC direct EU :443 is
        # often filtered while :2053 still SoftProbe-OK (FI field 2026-11-26).
        name = grpc_host(node)
        if full and self_steal_host(node):
            vless.append(
                "vless://{uuid}@{host}:{port}?encryption=none&flow=xtls-rprx-vision"
                "&security=reality&sni={sni}&fp=firefox&pbk={pbk}&sid={sid}&type=tcp#{title}".format(
                    uuid=user["uuid"],
                    host=node["host"],
                    port=SELF_STEAL_PORT,
                    sni=self_steal_host(node),
                    pbk=node["pbk"],
                    sid=node["sid"],
                    title=quote(country),
                )
            )
        vless.append(
            "vless://{uuid}@{host}:443?encryption=none&flow=xtls-rprx-vision"
            "&security=reality&sni={sni}&fp=firefox&pbk={pbk}&sid={sid}&type=tcp#{title}".format(
                uuid=user["uuid"],
                host=node["host"],
                sni=reality_sni(node),
                pbk=node["pbk"],
                sid=node["sid"],
                title=quote(country),
            )
        )
        # Hidden RU front: same country title, non-443 port → app uses it only as spare/fallback.
        for front in front_nodes():
            port = front_port_for(front, exit_id)
            if not port:
                continue
            front_vless.append(
                "vless://{uuid}@{host}:{port}?encryption=none&flow=xtls-rprx-vision"
                "&security=reality&sni={sni}&fp=firefox&pbk={pbk}&sid={sid}&type=tcp#{title}".format(
                    uuid=user["uuid"],
                    host=str(front.get("self_domain") or front["host"]),
                    port=port,
                    sni=reality_sni(front),
                    pbk=front["pbk"],
                    sid=front["sid"],
                    title=quote(country),
                )
            )
        if name:
            grpc.append(
                "vless://{uuid}@{host}:{port}?encryption=none&security=tls&sni={sni}&fp=firefox&alpn=h2"
                "&type=grpc&serviceName={service}&mode=gun#{title}".format(
                    uuid=user["uuid"],
                    host=name,
                    port=GRPC_PORT,
                    sni=name,
                    service=GRPC_SERVICE,
                    title=quote(country + " запасной"),
                )
            )
            tuic.append(
                "tuic://{uuid}:{password}@{host}:{port}?congestion_control=bbr&udp_relay_mode=native"
                "&alpn=h3&sni={sni}&zero_rtt_handshake=1#{title}".format(
                    uuid=user["uuid"],
                    password=user["hy2_password"],
                    host=name,
                    port=TUIC_PORT,
                    sni=name,
                    title=quote(country + " TUIC"),
                )
            )
        pin = str(node.get("hy2_pin") or "").lower()
        if pinned_hy2 and not re.fullmatch(r"[0-9a-f]{64}", pin):
            continue
        hy2_query = (
            "pinSHA256=%s&sni=%s" % (pin, quote(str(node["hy2_sni"]), safe=""))
            if pinned_hy2
            else "insecure=1&sni=%s" % quote(str(node["hy2_sni"]), safe="")
        )
        hy2.append(
            "hy2://{password}@{host}:443?{query}#{title}".format(
                password=user["hy2_password"],
                host=node["host"],
                query=hy2_query,
                title=quote(country + " Hy2"),
            )
        )
    if not full:
        grpc, tuic = [], []
    # Omit front rows when relay to EU is dead (config front_links_in_sub=false).
    if not front_links_in_sub():
        front_vless = []
    messages = ss_message_links(user)
    # One-tap for RU third-party (Hiddify lowest-delay / v2rayNG first row):
    # RU fronts first (panel TCP relay → EU when RuVDS↛VPSPay), then direct
    # Reality, then CDN/message, then gRPC/Hy2. K-Pax app Auto also prefers
    # fronts; SoftProbe+Clash still gates Connected.
    return front_vless + vless + messages + grpc + hy2 + tuic


def ss_ws_path(node: dict) -> str:
    secret = str(CFG.get("ss_ws_secret") or "")
    node_id = str(node.get("id") or "").lower()
    if not re.fullmatch(r"[0-9a-f]{32}", secret) or not re.fullmatch(r"[a-z0-9]{2,8}", node_id):
        return ""
    return "/w/%s/%s" % (node_id, secret)


def ss_message_links(user: sqlite3.Row) -> list[str]:
    host = cdn_host()
    lines = []
    for node in exit_nodes():
        path = ss_ws_path(node)
        if not path:
            continue
        lines.append(
            "vless://{uuid}@{host}:443?encryption=none&security=tls&sni={sni}&fp=firefox"
            "&type=ws&host={host}&path={path}#{title}".format(
                uuid=user["uuid"],
                host=host,
                sni=host,
                path=quote(path, safe=""),
                title=quote(country_name(node) + " сообщения"),
            )
        )
    return lines


def v2rayn_uri(kind: str, payload: dict) -> str:
    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
    token = base64.urlsafe_b64encode(raw).decode().rstrip("=")
    return "v2rayn://%s/%s" % (kind, token)


def v2rayn_auto_line() -> str:
    return v2rayn_uri(
        "policygroup",
        {
            "IndexId": "kpaxauto",
            "ConfigType": 101,
            "CoreType": 2,
            "ConfigVersion": 4,
            "Remarks": "Автоматический выбор",
            "ProtoExtraObj": {
                "SubChildItems": "self",
                "MultipleLoad": 0,
            },
        },
    )


def v2rayn_node_lines(user: sqlite3.Row) -> list[str]:
    """Profiles v2rayN imports itself. Plain vless:// lines would be inserted above the group."""
    lines = []
    for node in exit_nodes():
        node_id = str(node.get("id") or "n").lower()
        country = country_name(node)
        lines.append(
            v2rayn_uri(
                "vless",
                {
                    "IndexId": "r-" + node_id,
                    "ConfigType": 5,
                    "CoreType": 2,
                    "ConfigVersion": 4,
                    "Remarks": country,
                    "Address": node["host"],
                    "Port": 443,
                    "Password": user["uuid"],
                    "Network": "tcp",
                    "StreamSecurity": "reality",
                    "Sni": reality_sni(node),
                    "Fingerprint": TLS_FINGERPRINT,
                    "PublicKey": node["pbk"],
                    "ShortId": node["sid"],
                    "SpiderX": "",
                    "ProtoExtraObj": {"Flow": "xtls-rprx-vision", "VlessEncryption": "none"},
                },
            )
        )
        if node.get("hy2_sni") and node.get("hy2_pin"):
            # With CertSha v2rayN drops allowInsecure for Xray and keeps it only for sing-box.
            lines.append(
                v2rayn_uri(
                    "hysteria2",
                    {
                        "IndexId": "h-" + node_id,
                        "ConfigType": 7,
                        "CoreType": 2,
                        "ConfigVersion": 4,
                        "Remarks": country + " Hy2",
                        "Address": node["host"],
                        "Port": 443,
                        "Password": user["hy2_password"],
                        "Sni": node["hy2_sni"],
                        "Alpn": "h3",
                        "AllowInsecure": "true",
                        "CertSha": str(node["hy2_pin"]).lower(),
                    },
                )
            )
        path = ss_ws_path(node)
        if path:
            lines.append(
                v2rayn_uri(
                    "vless",
                    {
                        "IndexId": "w-" + node_id,
                        "ConfigType": 5,
                        "CoreType": 2,
                        "ConfigVersion": 4,
                        "Remarks": country + " сообщения",
                        "Address": cdn_host(),
                        "Port": 443,
                        "Password": user["uuid"],
                        "Network": "ws",
                        "StreamSecurity": "tls",
                        "Sni": cdn_host(),
                        "Fingerprint": TLS_FINGERPRINT,
                        "ProtoExtraObj": {"VlessEncryption": "none"},
                        "TransportExtraObj": {"Host": cdn_host(), "Path": path},
                    },
                )
            )
    return lines


def v2rayn_subscription_body(user: sqlite3.Row) -> str:
    raw = "\n".join([v2rayn_auto_line()] + v2rayn_node_lines(user)) + "\n"
    return base64.b64encode(raw.encode()).decode()


def happ_lines() -> list[str]:
    provider = ["#providerid " + brand()["happ_provider"]] if brand().get("happ_provider") else []
    return provider + [
        "#subscription-autoconnect: 1",
        "#subscription-autoconnect-type: lowestdelay",
        "#subscription-ping-onopen-enabled: 1",
        "#subscriptions-sort-type: without",
        "#ping-type: tcp",
    ]


def subscription_body(
    user: sqlite3.Row,
    pinned_hy2: bool = False,
    full: bool = False,
    *,
    include_v2rayn_group: bool = True,
) -> str:
    # Hiddify/sing-box parsers choke on v2rayn://policygroup (empty outbound type).
    lines = happ_lines()
    if include_v2rayn_group:
        lines.append(v2rayn_auto_line())
    lines.extend(links_for(user, pinned_hy2, full))
    raw = "\n".join(lines) + "\n"
    return base64.b64encode(raw.encode()).decode()


def happ_headers() -> dict[str, str]:
    provider = {"providerid": brand()["happ_provider"]} if brand().get("happ_provider") else {}
    return provider | {
        "subscription-autoconnect": "1",
        "subscription-autoconnect-type": "lowestdelay",
        "subscription-ping-onopen-enabled": "1",
        "subscriptions-sort-type": "without",
        # Proxy ping starts a core per row and fetches a page through it: numbers look high,
        # autoconnect picks by noise, and on iOS the extra cores eat the tunnel's memory limit.
        "ping-type": "tcp",
    }


def v2rayn_configs(user: sqlite3.Row) -> list[dict]:
    proxies = []
    for node in exit_nodes():
        tag = "kpax-" + str(node.get("id") or "n").lower()
        country = country_name(node)
        exit_id = str(node.get("id") or "").lower()
        # RU fronts first: v2rayN/Happ Auto + first-row clients from RF.
        for front in front_nodes():
            port = front_port_for(front, exit_id)
            if not port:
                continue
            front_ep = dict(front)
            front_ep["_front_port"] = port
            front_ep["_exit_id"] = exit_id
            # Unique per front host (ru / ru2): duplicate tags break Xray/INCY/Happ.
            front_id = re.sub(r"[^a-z0-9]+", "", str(front.get("id") or "front").lower()) or "front"
            proxies.append((tag + "-front-" + front_id, country, front_ep, "reality-front"))
        proxies.append((tag + "-reality", country, node, "reality"))
        if self_steal_host(node):
            proxies.append((tag + "-self", country, node, "reality-self"))
        # Xray deprecates gRPC and WebSocket; nodes with "xhttp" get the same rows over XHTTP.
        xhttp = bool(node.get("xhttp"))
        if grpc_host(node):
            proxies.append((tag + "-grpc", country + " запасной", node, "xhttp" if xhttp else "grpc"))
        if node.get("hy2_sni") and node.get("hy2_pin"):
            proxies.append((tag + "-hy2", country + " Hy2", node, "hy2"))
        if ss_ws_path(node):
            proxies.append((tag + "-ss", country + " сообщения", node, "xhttp-cdn" if xhttp else "ss"))
    # One row per country picks the best of its TCP transports; Hy2 (UDP) stays a separate manual row.
    # reality-front is in leastLoad (RU one-tap); CDN/ss stays fallback only.
    auto_proxies = [item for item in proxies if item[3] != "hy2"]
    configs = [xray_profile(user, "Автоматический выбор", auto_proxies, automatic=True)]
    for node in exit_nodes():
        country = country_name(node)
        exit_id = str(node.get("id") or "").lower()
        own = [
            item
            for item in auto_proxies
            if item[2] is node
            or (item[3] == "reality-front" and item[2].get("_exit_id") == exit_id)
        ]
        configs.append(xray_profile(user, country, own, automatic=True))
    for item in proxies:
        if item[3] == "hy2":
            configs.append(xray_profile(user, item[1], [item], automatic=False))
    return configs


XHTTP_TLS_PORT = 8444
# Second Reality inbound that borrows the handshake from a site on the node itself (self_domain in the config):
# SNI, DNS, certificate and IP agree. The old Reality on 443 stays for clients that have not refreshed.
SELF_STEAL_PORT = 2053
# uTLS fingerprint in every subscription. The 2026 filters freeze Chrome, Safari and iOS hellos first;
# share links spell the same value out as fp=firefox.
TLS_FINGERPRINT = "firefox"
# Explicit XHTTP padding and connection reuse; older client cores had other defaults.
XHTTP_EXTRA = {
    "xPaddingBytes": "100-1000",
    "xmux": {"maxConcurrency": "16-32", "hMaxRequestTimes": "600-900", "hMaxReusableSecs": "1800-3000"},
}
# Russian sites go straight from the phone: they refuse foreign IPs, and Russian apps that report VPN use
# do not see our servers. Domain lists only, so no client depends on geoip/geosite files being present.
RU_DIRECT = [
    "domain:ru", "domain:su", "domain:xn--p1ai", "domain:moscow", "domain:tatar",
    "domain:yandex.net", "domain:yastatic.net", "domain:yandex.com", "domain:ya.cc",
    "domain:vk.com", "domain:vk.me", "domain:vkuser.net", "domain:userapi.com", "domain:vk-cdn.net", "domain:vkvideo.ru",
    "domain:mycdn.me", "domain:mradx.net", "domain:okcdn.ru",
    "domain:sberbank.com", "domain:sber.ru", "domain:tbank.ru", "domain:tinkoff.ru", "domain:vtb.ru",
    "domain:gosuslugi.ru", "domain:nalog.gov.ru", "domain:max.ru", "domain:oneme.ru",
]
# Server-side ad blocking does not see direct traffic, so the main Russian ad and analytics hosts are dropped on the phone.
RU_ADS_BLOCK = [
    "domain:an.yandex.ru", "domain:mc.yandex.ru", "domain:adfox.ru", "domain:yandexadexchange.net",
    "domain:ad.mail.ru", "domain:top-fwz1.mail.ru", "domain:ads.vk.com", "domain:vk-analytics.ru",
    "domain:adriver.ru", "domain:tns-counter.ru", "domain:mediascope.net",
]


def xhttp_secret() -> str:
    secret = str(CFG.get("ss_ws_secret") or "")
    return secret if re.fullmatch(r"[0-9a-f]{32}", secret) else ""


def xray_outbound(user: sqlite3.Row, tag: str, node: dict, kind: str) -> dict:
    if kind == "xhttp":
        host = grpc_host(node)
        return {
            "tag": tag,
            "protocol": "vless",
            "settings": {
                "vnext": [{"address": host, "port": XHTTP_TLS_PORT, "users": [{"id": user["uuid"], "encryption": "none"}]}]
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "tls",
                "tlsSettings": {"serverName": host, "fingerprint": TLS_FINGERPRINT, "alpn": ["h2"]},
                "xhttpSettings": {"path": "/xh/" + xhttp_secret(), "mode": "auto", "extra": XHTTP_EXTRA},
            },
        }
    if kind == "xhttp-cdn":
        node_id = str(node.get("id") or "").lower()
        host = cdn_host()
        return {
            "tag": tag,
            "protocol": "vless",
            "settings": {
                "vnext": [{"address": host, "port": 443, "users": [{"id": user["uuid"], "encryption": "none"}]}]
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "tls",
                "tlsSettings": {"serverName": host, "fingerprint": TLS_FINGERPRINT, "alpn": ["h2"]},
                "xhttpSettings": {"path": "/x/%s/%s" % (node_id, xhttp_secret()), "mode": "auto", "extra": XHTTP_EXTRA},
            },
        }
    if kind == "grpc":
        host = grpc_host(node)
        return {
            "tag": tag,
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": host,
                        "port": GRPC_PORT,
                        "users": [{"id": user["uuid"], "encryption": "none"}],
                    }
                ]
            },
            "streamSettings": {
                "network": "grpc",
                "security": "tls",
                "tlsSettings": {
                    "serverName": host,
                    "fingerprint": TLS_FINGERPRINT,
                    "alpn": ["h2"],
                },
                "grpcSettings": {"serviceName": GRPC_SERVICE, "multiMode": False},
            },
        }
    if kind == "hy2":
        # Current Xray rejects allowInsecure; the self-signed Hy2 certificate is pinned instead.
        return {
            "tag": tag,
            "protocol": "hysteria",
            "settings": {"version": 2, "address": node["host"], "port": 443},
            "streamSettings": {
                "network": "hysteria",
                "security": "tls",
                "tlsSettings": {
                    "serverName": node["hy2_sni"],
                    "pinnedPeerCertSha256": str(node["hy2_pin"]).lower(),
                    "alpn": ["h3"],
                },
                "hysteriaSettings": {"version": 2, "auth": user["hy2_password"]},
                "finalmask": {"quicParams": {"congestion": "bbr"}},
            },
        }
    if kind == "ss":
        host = cdn_host()
        return {
            "tag": tag,
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": host,
                        "port": 443,
                        "users": [{"id": user["uuid"], "encryption": "none"}],
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {"serverName": host},
                "wsSettings": {"path": ss_ws_path(node), "host": host},
            },
        }
    if kind == "reality-front":
        port = int(node.get("_front_port") or 0)
        return {
            "tag": tag,
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": str(node.get("self_domain") or node["host"]),
                        "port": port,
                        "users": [
                            {
                                "id": user["uuid"],
                                "encryption": "none",
                                "flow": "xtls-rprx-vision",
                            }
                        ],
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "serverName": reality_sni(node),
                    "fingerprint": TLS_FINGERPRINT,
                    "publicKey": node["pbk"],
                    "shortId": node["sid"],
                    "spiderX": "",
                },
            },
        }
    self_steal = kind == "reality-self"
    return {
        "tag": tag,
        "protocol": "vless",
        "settings": {
            "vnext": [
                {
                    "address": node["host"],
                    "port": SELF_STEAL_PORT if self_steal else 443,
                    "users": [
                        {
                            "id": user["uuid"],
                            "encryption": "none",
                            "flow": "xtls-rprx-vision",
                        }
                    ],
                }
            ]
        },
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "serverName": self_steal_host(node) if self_steal else reality_sni(node),
                "fingerprint": TLS_FINGERPRINT,
                "publicKey": node["pbk"],
                "shortId": node["sid"],
                "spiderX": "",
            },
        },
    }


def xray_profile(user: sqlite3.Row, remarks: str, proxies: list[tuple], automatic: bool) -> dict:
    outbounds = []
    for tag, _title, node, kind in proxies:
        outbounds.append(xray_outbound(user, tag, node, kind))
    outbounds.append({"tag": "direct", "protocol": "freedom", "settings": {}})
    outbounds.append({"tag": "block", "protocol": "blackhole", "settings": {}})
    tags = [tag for tag, _title, _node, _kind in proxies]
    # CDN/ss: last-resort fallback only. RU fronts join leastLoad so Auto from RF
    # picks a working :2443–2445 before filtered bare EU :443.
    cdn_kinds = ("ss", "xhttp-cdn")
    front = [tag for tag, _title, _node, kind in proxies if kind == "reality-front"]
    direct = [
        tag
        for tag, _title, _node, kind in proxies
        if kind not in cdn_kinds and kind != "reality-front"
    ]
    cdn = [tag for tag, _title, _node, kind in proxies if kind in cdn_kinds]
    if automatic and len(tags) > 1:
        selector = (front + direct) or tags
        fallback = (direct[0] if front and direct else None) or (
            cdn[0] if cdn else tags[0]
        )
        # leastLoad + expected>1 spreads across near-best nodes instead of
        # always pinning the single lowest RTT (overloads FI / girl_round).
        routing = {
            "domainStrategy": "IPIfNonMatch",
            "balancers": [
                {
                    "tag": "auto",
                    "selector": selector,
                    "strategy": {
                        "type": "leastLoad",
                        "settings": {
                            # Spread across near-best exits; observatory keeps sticky-ish
                            # picks on healthy nodes without pinning everyone to FI.
                            "expected": min(3, len(selector)),
                            "maxRTT": "800ms",
                            "tolerance": 0.25,
                        },
                    },
                    "fallbackTag": fallback,
                }
            ],
            "rules": [{"type": "field", "network": "tcp,udp", "balancerTag": "auto"}],
        }
        observatory = {
            "subjectSelector": selector,
            "probeURL": "https://www.gstatic.com/generate_204",
            "probeInterval": "1m",
            "enableConcurrency": True,
        }
    else:
        routing = {
            "domainStrategy": "IPIfNonMatch",
            "rules": [{"type": "field", "network": "tcp,udp", "outboundTag": tags[0]}],
        }
        observatory = None
    routing["rules"] = [
        {"type": "field", "domain": RU_ADS_BLOCK, "outboundTag": "block"},
        {"type": "field", "domain": RU_DIRECT, "outboundTag": "direct"},
    ] + routing["rules"]
    config = {
        "remarks": remarks,
        "inbounds": [
            {
                "tag": "socks-in",
                "port": 10808,
                "listen": "127.0.0.1",
                "protocol": "socks",
                "settings": {"udp": True, "auth": "noauth"},
                "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]},
            }
        ],
        "outbounds": outbounds,
        "routing": routing,
    }
    if observatory:
        config["observatory"] = observatory
    return config


def wants_v2rayn(user_agent: str) -> bool:
    low = user_agent.lower()
    return "v2rayn" in low and "v2rayng" not in low


def wants_v2rayng(user_agent: str) -> bool:
    return "v2rayng" in user_agent.lower()


def wants_incy(user_agent: str) -> bool:
    return "incy" in user_agent.lower()


def wants_kpax_app(user_agent: str) -> bool:
    """Official brand app (K-Pax or X-Plm) — gets the full subscription profile."""
    low = user_agent.lower()
    return (
        "k-pax" in low
        or "kpax" in low
        or "x-plm" in low
        or "xplm" in low
    )


def wants_happ(user_agent: str) -> bool:
    return "happ" in user_agent.lower()


def wants_hiddify(user_agent: str) -> bool:
    low = user_agent.lower()
    return "hiddify" in low or "sing-box" in low or "singbox" in low


def present_for_incy(config: dict) -> dict:
    """INCY shows one row per full config and titles it from the first proxy tag."""
    config = json.loads(json.dumps(config))
    title = str(config.get("remarks") or brand()["name"])
    proxies = [
        item
        for item in config["outbounds"]
        if item.get("protocol") not in ("freedom", "blackhole")
    ]
    if not proxies:
        return config
    previous = proxies[0]["tag"]
    proxies[0]["tag"] = title
    for rule in config["routing"].get("rules") or []:
        if rule.get("outboundTag") == previous:
            rule["outboundTag"] = title
    selectors = []
    for balancer in config["routing"].get("balancers") or []:
        if balancer.get("fallbackTag") == previous:
            balancer["fallbackTag"] = title
        selectors = [title if item == previous else item for item in (balancer.get("selector") or [])]
        if title not in selectors:
            selectors.insert(0, title)
        balancer["selector"] = selectors
    if selectors:
        observatory = config.get("observatory")
        if isinstance(observatory, dict):
            current = list(observatory.get("subjectSelector") or [])
            if title not in current:
                current.insert(0, title)
            observatory["subjectSelector"] = current
        config.pop("observatory", None)
        config["burstObservatory"] = {
            "subjectSelector": selectors,
            "pingConfig": {
                "destination": "https://www.gstatic.com/generate_204",
                "connectivity": "https://www.gstatic.com/generate_204",
                "interval": "30s",
                "sampling": 2,
                "timeout": "5s",
            },
        }
        config["stats"] = {}
        config["dns"] = {"servers": ["1.1.1.1", "8.8.8.8"], "queryStrategy": "UseIPv4"}
        config["log"] = {"loglevel": "warning"}
    if not any(item.get("protocol") == "http" for item in config["inbounds"]):
        config["inbounds"].append(
            {
                "tag": "http-in",
                "port": 10809,
                "listen": "127.0.0.1",
                "protocol": "http",
                "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]},
            }
        )
    return config


def incy_configs(user: sqlite3.Row) -> list[dict]:
    return [present_for_incy(item) for item in v2rayn_configs(user)]


VERIFY_TTL = 30 * 60
# Soft IP caps: ownership verify + disposable block carry anti-spam.
# One household / café Wi‑Fi should still onboard a few friends in a day.
TRIAL_IP_DAY = 5
SIGNUP_ATTEMPT_HOUR = 5
DISPOSABLE_DOMAINS = frozenset(
    {
        "mailinator.com",
        "guerrillamail.com",
        "guerrillamail.de",
        "sharklasers.com",
        "grr.la",
        "yopmail.com",
        "tempmail.com",
        "temp-mail.org",
        "10minutemail.com",
        "trashmail.com",
        "discard.email",
        "getnada.com",
        "moakt.com",
        "emailondeck.com",
        "fakeinbox.com",
        "throwawaymail.com",
        "tmpmail.org",
        "tmpmail.net",
        "mailnesia.com",
        "maildrop.cc",
    }
)


def too_many(ip: str) -> bool:
    """Soft IP cap: several trials / day, hard stop only on burst spam."""
    now = now_ts()
    conn = db()
    day = conn.execute(
        "SELECT COUNT(*) FROM signup_log WHERE ip=? AND created_at>?",
        (ip, now - 86400),
    ).fetchone()[0]
    hour = conn.execute(
        "SELECT COUNT(*) FROM signup_log WHERE ip=? AND created_at>?",
        (ip, now - 3600),
    ).fetchone()[0]
    conn.close()
    return int(day) >= TRIAL_IP_DAY or int(hour) >= SIGNUP_ATTEMPT_HOUR


def signup_suspicious(ip: str) -> bool:
    """Captcha only when the IP already looks noisy."""
    now = now_ts()
    conn = db()
    hour = conn.execute(
        "SELECT COUNT(*) FROM signup_log WHERE ip=? AND created_at>?",
        (ip, now - 3600),
    ).fetchone()[0]
    hits = conn.execute(
        "SELECT COUNT(*) FROM captcha_hits WHERE ip=? AND created_at>?",
        (ip, now - 3600),
    ).fetchone()[0]
    conn.close()
    return int(hour) >= 2 or int(hits) >= 2


def note_captcha_hit(ip: str) -> None:
    conn = db()
    conn.execute("INSERT INTO captcha_hits(ip, created_at) VALUES(?, ?)", (ip, now_ts()))
    conn.execute("DELETE FROM captcha_hits WHERE created_at<?", (now_ts() - 2 * 86400,))
    conn.commit()
    conn.close()


def captcha_secret() -> bytes:
    raw = str(CFG.get("admin_password_hash") or CFG.get("limit_secret") or "k-pax")
    return hashlib.sha256(raw.encode("utf-8")).digest()


def issue_captcha() -> tuple[str, str]:
    a = secrets.randbelow(8) + 2
    b = secrets.randbelow(8) + 2
    stamp = now_ts()
    payload = "%d:%d:%d" % (a, b, stamp)
    sig = hmac.new(captcha_secret(), payload.encode(), hashlib.sha256).hexdigest()[:20]
    return "%d + %d =" % (a, b), "%s:%s" % (payload, sig)


def captcha_ok(token: str, answer: str) -> bool:
    parts = (token or "").split(":")
    if len(parts) != 4:
        return False
    a_s, b_s, stamp_s, sig = parts
    payload = "%s:%s:%s" % (a_s, b_s, stamp_s)
    expect = hmac.new(captcha_secret(), payload.encode(), hashlib.sha256).hexdigest()[:20]
    if not hmac.compare_digest(expect, sig):
        return False
    try:
        stamp = int(stamp_s)
        a = int(a_s)
        b = int(b_s)
        value = int((answer or "").strip())
    except ValueError:
        return False
    if now_ts() - stamp > 900:
        return False
    return value == a + b


def disposable_email(contact: str) -> bool:
    if "@" not in contact or contact.startswith("@"):
        return False
    domain = contact.rsplit("@", 1)[-1].lower()
    if domain in DISPOSABLE_DOMAINS:
        return True
    # one level up for foo.mailinator.com style
    parts = domain.split(".")
    if len(parts) >= 3 and ".".join(parts[-2:]) in DISPOSABLE_DOMAINS:
        return True
    return False


def _scrub_contact_raw(raw: str) -> str:
    contact = (raw or "").replace("\u200b", "").replace("\xa0", " ").strip()
    contact = contact.replace("＠", "@")
    if contact.lower().startswith("mailto:"):
        contact = contact[7:].strip()
    angled = re.search(r"<([^>]+@[^>]+)>", contact)
    if angled:
        contact = angled.group(1).strip()
    return contact


def normalize_email(raw: str) -> str:
    """New signups and app login create — email only."""
    contact = _scrub_contact_raw(raw)
    if not contact or any(ch.isspace() for ch in contact) or len(contact) > 120:
        raise ValueError("Укажите почту: name@mail.ru.")
    if contact.startswith("@") or "@" not in contact:
        raise ValueError("Новые аккаунты — только по почте. Укажите name@mail.ru.")
    if not re.fullmatch(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", contact):
        raise ValueError("Некорректная почта. Пример: name@mail.ru")
    normal = contact.lower()
    if disposable_email(normal):
        raise ValueError("Укажите обычную почту. Временные ящики для регистрации не подходят.")
    return normal


def normalize_contact(raw: str) -> str:
    """Email or legacy Telegram nick (existing accounts / bot restore)."""
    contact = _scrub_contact_raw(raw)
    if not contact or any(ch.isspace() for ch in contact) or len(contact) > 120:
        raise ValueError("Укажите почту или Telegram: name@mail.ru или @username.")
    # If it looks like an email attempt, never fall through to Telegram nick rules.
    if "@" in contact and not contact.startswith("@"):
        return normalize_email(contact)
    if not brand()["telegram"]:
        raise ValueError("Укажите почту: name@mail.ru.")
    # Accept @nick, nick, t.me/nick, https://t.me/nick
    nick = contact
    lower = nick.lower()
    for prefix in (
        "https://t.me/",
        "http://t.me/",
        "https://telegram.me/",
        "http://telegram.me/",
        "t.me/",
        "telegram.me/",
    ):
        if lower.startswith(prefix):
            nick = nick[len(prefix) :]
            break
    nick = nick.split("?", 1)[0].split("/", 1)[0].strip()
    if nick.startswith("@"):
        nick = nick[1:]
    if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{4,31}", nick):
        return "@" + nick
    raise ValueError(
        "Ник Telegram: латиница, цифры и _, от 5 символов, начинается с буквы. Пример: @username"
    )


def contact_is_telegram(contact: str) -> bool:
    return str(contact or "").startswith("@")


def user_needs_email_link(user: sqlite3.Row) -> bool:
    return contact_is_telegram(str(user["contact"] or ""))


def hash_verify_code(code: str) -> str:
    return hmac.new(captcha_secret(), code.encode("utf-8"), hashlib.sha256).hexdigest()


def new_email_code() -> str:
    return "%06d" % secrets.randbelow(1_000_000)


def new_verify_token() -> str:
    return secrets.token_urlsafe(18)


APP_LOGIN_TTL = 30 * 60


def new_app_login_token() -> str:
    return secrets.token_urlsafe(24)


def create_app_login(user_id: int, *, code_hash: str = "") -> str:
    token = new_app_login_token()
    with LOCK:
        conn = db()
        conn.execute(
            """
            INSERT INTO app_login(token, user_id, brand, created_at, ready_at, consumed_at, code_hash)
            VALUES(?, ?, ?, ?, 0, 0, ?)
            """,
            (token, int(user_id), brand_id(), now_ts(), code_hash or ""),
        )
        conn.commit()
        conn.close()
    return token


def app_login_row(token: str) -> sqlite3.Row | None:
    if not token or len(token) > 80:
        return None
    conn = db()
    row = conn.execute(
        "SELECT * FROM app_login WHERE token=? AND brand=? LIMIT 1",
        (token, brand_id()),
    ).fetchone()
    conn.close()
    return row


def app_login_expired(row: sqlite3.Row) -> bool:
    return now_ts() - int(row["created_at"] or 0) > APP_LOGIN_TTL


def mark_app_login_ready(token: str) -> sqlite3.Row | None:
    with LOCK:
        conn = db()
        row = conn.execute(
            "SELECT * FROM app_login WHERE token=? AND brand=? LIMIT 1",
            (token, brand_id()),
        ).fetchone()
        if row is None:
            conn.close()
            return None
        if app_login_expired(row):
            conn.close()
            return None
        if int(row["ready_at"] or 0) <= 0:
            conn.execute(
                "UPDATE app_login SET ready_at=? WHERE token=? AND brand=?",
                (now_ts(), token, brand_id()),
            )
            conn.commit()
            row = conn.execute(
                "SELECT * FROM app_login WHERE token=? AND brand=? LIMIT 1",
                (token, brand_id()),
            ).fetchone()
        conn.close()
        return row


def consume_app_login(token: str) -> tuple[str, dict]:
    """Return (status, payload). status: pending|ready|expired."""
    with LOCK:
        conn = db()
        row = conn.execute(
            "SELECT * FROM app_login WHERE token=? AND brand=? LIMIT 1",
            (token, brand_id()),
        ).fetchone()
        if row is None or app_login_expired(row) or int(row["consumed_at"] or 0) > 0:
            conn.close()
            return "expired", {"status": "expired"}
        if int(row["ready_at"] or 0) <= 0:
            conn.close()
            return "pending", {"status": "pending"}
        user = conn.execute(
            "SELECT * FROM users WHERE id=? AND brand=? LIMIT 1",
            (int(row["user_id"]), brand_id()),
        ).fetchone()
        if user is None or not int(user["verified"] or 0) or not int(user["active"] or 0):
            conn.close()
            return "pending", {"status": "pending"}
        conn.execute(
            "UPDATE app_login SET consumed_at=? WHERE token=? AND brand=?",
            (now_ts(), token, brand_id()),
        )
        conn.commit()
        conn.close()
    return "ready", {
        "status": "ready",
        "url": sub_url(str(user["token"])),
        "public_id": str(user["public_id"]),
        "expires_at": int(user["expires_at"] or 0),
        "active": bool(user["active"]) and int(user["expires_at"] or 0) > now_ts(),
        "needs_email_link": user_needs_email_link(user),
    }


def bot_app_login_url(token: str) -> str:
    return "https://t.me/KPax_Space_bot?start=a_" + token


def app_login_confirm_markup(token: str) -> dict:
    return {
        "inline_keyboard": [[{"text": "Подтвердить", "callback_data": "ac:" + token}]],
    }


def app_confirm_url(token: str) -> str:
    return SITE + "/app/confirm?t=" + token


def finish_app_login(token: str) -> tuple[sqlite3.Row | None, str]:
    """Confirm ownership for a login session. Returns (user, error)."""
    row = app_login_row(token)
    if row is None or app_login_expired(row):
        return None, "Ссылка подтверждения устарела. Запросите вход ещё раз в приложении."
    conn = db()
    user = conn.execute(
        "SELECT * FROM users WHERE id=? AND brand=? LIMIT 1",
        (int(row["user_id"]), brand_id()),
    ).fetchone()
    conn.close()
    if user is None:
        return None, "Аккаунт не найден."
    if not int(user["verified"] or 0) or not int(user["active"] or 0):
        try:
            user, _, _ = activate_user(user)
        except Exception as exc:  # noqa: BLE001
            print("app login activate failed", type(exc).__name__, flush=True)
            return None, "Не получилось подтвердить доступ. Попробуйте ещё раз."
    if mark_app_login_ready(token) is None:
        return None, "Ссылка подтверждения устарела. Запросите вход ещё раз в приложении."
    return user, ""


TAKEN = (
    "Этот контакт уже зарегистрирован. Ссылку повторно не показываем. "
    "Чтобы вернуть её, напишите с этой почты на access@k-pax.space "
    "или откройте бота @KPax_Space_bot с этого Telegram."
)


PUBLIC_ID_RE = r"(?:KP|XP)-\d{5,8}"


def referral_code(raw: str) -> str:
    code = (raw or "").strip().upper()
    if re.fullmatch(PUBLIC_ID_RE, code) and code.startswith(brand()["prefix"] + "-"):
        return code
    return ""


def cookie_value(header: str | None, name: str) -> str:
    for part in (header or "").split(";"):
        key, _, value = part.strip().partition("=")
        if key == name:
            return value
    return ""


def referrer_exists(code: str) -> bool:
    code = referral_code(code)
    if not code:
        return False
    conn = db()
    row = conn.execute(
        "SELECT 1 FROM users WHERE public_id=? AND brand=? LIMIT 1",
        (code, brand_id()),
    ).fetchone()
    conn.close()
    return row is not None


def grant_referral(code: str, friend: sqlite3.Row) -> bool:
    """Add 15 days to the inviter when a new account is created from their link."""
    code = referral_code(code)
    if not code or code == friend["public_id"]:
        return False
    with LOCK:
        conn = db()
        referrer = conn.execute(
            "SELECT id, contact FROM users WHERE public_id=? AND brand=?",
            (code, str(friend["brand"] or "kpax")),
        ).fetchone()
        if referrer is None or int(referrer["id"]) == int(friend["id"]):
            conn.close()
            return False
        if str(referrer["contact"]).lower() == str(friend["contact"]).lower():
            conn.close()
            return False
        try:
            conn.execute(
                "INSERT INTO referrals(referrer_id, friend_id, created_at) VALUES(?, ?, ?)",
                (int(referrer["id"]), int(friend["id"]), now_ts()),
            )
            conn.commit()
        except sqlite3.IntegrityError:
            conn.close()
            return False
        conn.close()
    try:
        extend_user(code, REFERRAL_DAYS)
    except Exception as exc:  # noqa: BLE001
        print("referral extend failed", code, type(exc).__name__, flush=True)
        return False
    print("referral", code, friend["public_id"], flush=True)
    return True


def lookup_contact(contact: str) -> sqlite3.Row | None:
    conn = db()
    row = conn.execute(
        "SELECT * FROM users WHERE lower(contact)=lower(?) AND brand=? LIMIT 1",
        (contact, brand_id()),
    ).fetchone()
    if row is None and contact_is_telegram(contact):
        row = conn.execute(
            "SELECT * FROM users WHERE lower(telegram_nick)=lower(?) AND brand=? LIMIT 1",
            (contact, brand_id()),
        ).fetchone()
    conn.close()
    return row


def user_by_sub_token(token: str) -> sqlite3.Row | None:
    if not token or len(token) > 80:
        return None
    conn = db()
    row = conn.execute(
        "SELECT * FROM users WHERE token=? AND brand=? LIMIT 1",
        (token, brand_id()),
    ).fetchone()
    conn.close()
    return row


def bind_email_to_telegram_user(user: sqlite3.Row, email: str) -> sqlite3.Row:
    """Soft-link: contact := email, keep nick in telegram_nick. Raises ValueError."""
    email = normalize_email(email)
    if not user_needs_email_link(user):
        raise ValueError("У этого аккаунта почта уже привязана.")
    taken = lookup_contact(email)
    if taken is not None and int(taken["id"]) != int(user["id"]):
        raise ValueError(
            "Эта почта уже используется другим аккаунтом. Напишите на support@%s"
            % brand()["host"]
        )
    nick = str(user["contact"] or "")
    with LOCK:
        conn = db()
        conn.execute(
            """
            UPDATE users SET contact=?, telegram_nick=?
            WHERE id=? AND brand=?
            """,
            (email, nick, int(user["id"]), brand_id()),
        )
        conn.commit()
        fresh = conn.execute(
            "SELECT * FROM users WHERE id=? AND brand=? LIMIT 1",
            (int(user["id"]), brand_id()),
        ).fetchone()
        conn.close()
    if fresh is None:
        raise RuntimeError("bind email")
    print("email linked", fresh["public_id"], nick, "->", email, flush=True)
    return fresh


def account_status(user: sqlite3.Row) -> str:
    number = user["public_id"]
    when = fmt(int(user["expires_at"]))
    if user["active"] and int(user["expires_at"]) > now_ts():
        return "Номер %s. Эта почта или ник уже используются. Доступ до %s." % (number, when)
    return "Номер %s. Эта почта или ник уже используются. Срок закончился %s." % (number, when)


def restore_channel(contact: str) -> str:
    return "telegram" if contact.startswith("@") else "email"


def partner_code(raw: str) -> str:
    """Partner slug: latin letters, digits, hyphen. Lowercase."""
    code = re.sub(r"[^A-Za-z0-9\-]", "", (raw or "").strip().lower())
    if not re.fullmatch(r"[a-z][a-z0-9\-]{1,31}", code):
        return ""
    return code


def partner_cookie_name() -> str:
    return brand_id() + "_partner"


def partner_exists(code: str, bid: str = "") -> bool:
    code = partner_code(code)
    if not code:
        return False
    conn = db()
    row = conn.execute(
        "SELECT 1 FROM partners WHERE code=? AND brand=? AND active=1 LIMIT 1",
        (code, bid or brand_id()),
    ).fetchone()
    conn.close()
    return row is not None


def resolve_partner(raw: str) -> str:
    code = partner_code(raw)
    return code if code and partner_exists(code) else ""


def create_partner(raw: str, bid: str = "") -> str:
    code = partner_code(raw)
    if not code:
        raise ValueError("Имя латиницей, 2–32 символа, начинается с буквы.")
    bid = bid or brand_id()
    if bid not in BRANDS:
        raise ValueError("Неизвестный бренд.")
    with LOCK:
        conn = db()
        try:
            conn.execute(
                "INSERT INTO partners(code, brand, created_at, active) VALUES(?, ?, ?, 1)",
                (code, bid, now_ts()),
            )
            conn.commit()
        except sqlite3.IntegrityError as exc:
            conn.rollback()
            raise ValueError("Такой партнёр уже есть.") from exc
        finally:
            conn.close()
    return code


def partner_url(code: str, bid: str = "") -> str:
    host = BRANDS.get(bid or brand_id(), BRANDS["kpax"])["host"]
    return "https://%s/?p=%s" % (host, code)


def partner_stats(bid: str = "") -> list[dict]:
    bid = bid or brand_id()
    month = msk_month_start()
    conn = db()
    rows = conn.execute(
        """
        SELECT p.code, p.created_at,
               (SELECT COUNT(*) FROM users u
                WHERE u.partner=p.code AND u.brand=p.brand AND u.verified=1) AS total,
               (SELECT COUNT(*) FROM users u
                WHERE u.partner=p.code AND u.brand=p.brand AND u.verified=1 AND u.created_at>=?) AS month
        FROM partners p
        WHERE p.brand=? AND p.active=1
        ORDER BY p.created_at DESC
        """,
        (month, bid),
    ).fetchall()
    conn.close()
    return [
        {
            "code": str(row["code"]),
            "created_at": int(row["created_at"]),
            "total": int(row["total"] or 0),
            "month": int(row["month"] or 0),
            "url": partner_url(str(row["code"]), bid),
        }
        for row in rows
    ]


def deactivate_partner(raw: str, bid: str = "") -> str:
    code = partner_code(raw)
    bid = bid or brand_id()
    if not code:
        raise ValueError("Укажите партнёра.")
    with LOCK:
        conn = db()
        cur = conn.execute(
            "UPDATE partners SET active=0 WHERE code=? AND brand=? AND active=1",
            (code, bid),
        )
        conn.commit()
        conn.close()
    if cur.rowcount < 1:
        raise ValueError("Такой ссылки нет.")
    return code


def partners_page(notice: str = "", error: str = "") -> tuple[int, str, bytes]:
    bid = brand_id()
    rows = partner_stats(bid)
    body_rows = []
    for item in rows:
        short = "/?p=" + item["code"]
        body_rows.append(
            "<tr>"
            "<td><code>%s</code></td>"
            "<td>%d</td>"
            "<td>%d</td>"
            "<td><a class='cell-link' href='%s' title='%s'>%s</a></td>"
            "<td>"
            "<form class='inline-del' method='post' action='/admin/partner/delete'>"
            "<input type='hidden' name='code' value='%s'>"
            "<button type='submit' class='ghost'>Удалить</button>"
            "</form>"
            "</td>"
            "</tr>"
            % (
                html.escape(item["code"]),
                item["total"],
                item["month"],
                html.escape(item["url"], quote=True),
                html.escape(item["url"], quote=True),
                html.escape(short),
                html.escape(item["code"], quote=True),
            )
        )
    table = (
        "<div class='tablewrap adminlist partners'><table>"
        "<thead><tr>"
        "<th>Партнёр</th><th>Всего</th><th>За месяц</th><th>Ссылка</th><th></th>"
        "</tr></thead><tbody>%s</tbody></table></div>"
        % ("".join(body_rows) or "<tr><td colspan='5'>Партнёрских ссылок пока нет.</td></tr>")
    )
    create = """
<form class="extend createbar" method="post" action="/admin/partner">
<div class="row">
<input name="code" maxlength="32" placeholder="partnername" pattern="[A-Za-z][A-Za-z0-9\\-]{1,31}" required title="Латиница, с буквы">
<button type="submit">Сгенерировать ссылку</button>
</div>
</form>
"""
    note = "<p class='ok'>%s</p>" % html.escape(notice) if notice else ""
    err = "<p class='err'>%s</p>" % html.escape(error) if error else ""
    body = """
{nav}
<div class="toolbar">
<p class="lead">Партнёры: {count}. Имя латиницей → ссылка ?p=имя. Счётчик — подтверждённые регистрации.</p>
<a href="/admin/logout">Выйти</a>
</div>
{note}{err}
{create}
{table}
""".format(
        nav=admin_nav("partners"),
        count=len(rows),
        note=note,
        err=err,
        create=create,
        table=table,
    )
    return page("K-Pax — партнёры", body, 400 if error else 200, wide=True)


def create_user(
    contact: str,
    ip: str,
    *,
    pending_ref: str = "",
    pending_promo: str = "",
    partner: str = "",
) -> sqlite3.Row:
    """Create an unverified trial account. New accounts are email-only."""
    contact = normalize_email(contact)
    partner = resolve_partner(partner)
    with LOCK:
        conn = db()
        existing = conn.execute(
            "SELECT 1 FROM users WHERE lower(contact)=lower(?) AND brand=? LIMIT 1",
            (contact, brand_id()),
        ).fetchone()
        conn.close()
    if existing is not None:
        raise ValueError(TAKEN)
    if too_many(ip):
        raise ValueError("С этого адреса уже создано несколько аккаунтов. Попробуйте позже.")
    user_uuid = str(uuid.uuid4())
    password = secrets.token_hex(16)
    token = secrets.token_urlsafe(24)
    verify_token = new_verify_token()
    email_code = "" if contact.startswith("@") else new_email_code()
    created = now_ts()
    expires = created + TRIAL_DAYS * 86400
    with LOCK:
        conn = db()
        conn.execute("INSERT INTO signup_log(ip, created_at) VALUES(?, ?)", (ip, created))
        taken = conn.execute(
            "SELECT 1 FROM users WHERE lower(contact)=lower(?) AND brand=? LIMIT 1",
            (contact, brand_id()),
        ).fetchone()
        if taken:
            conn.close()
            raise ValueError(TAKEN)
        cur = conn.execute(
            """
            INSERT INTO users(
                public_id, token, contact, uuid, hy2_password, created_at, expires_at, active,
                verified, verify_token, verify_code, verify_sent_at, pending_ref, pending_promo, brand, partner
            ) VALUES('pending', ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                token,
                contact,
                user_uuid,
                password,
                created,
                expires,
                verify_token,
                hash_verify_code(email_code) if email_code else "",
                created if email_code else 0,
                referral_code(pending_ref),
                (pending_promo or "").strip()[:32],
                brand_id(),
                partner,
            ),
        )
        public_id = "%s-%d" % (brand()["prefix"], 10000 + cur.lastrowid)
        conn.execute("UPDATE users SET public_id=? WHERE id=?", (public_id, cur.lastrowid))
        conn.commit()
        user = conn.execute("SELECT * FROM users WHERE id=?", (cur.lastrowid,)).fetchone()
        conn.close()
    if email_code:
        deliver_verify_mail(user, email_code)
    print("created pending", public_id, flush=True)
    return user


def user_by_verify_token(token: str) -> sqlite3.Row | None:
    if not token or len(token) > 80:
        return None
    conn = db()
    row = conn.execute(
        "SELECT * FROM users WHERE verify_token=? AND verified=0 AND brand=? LIMIT 1",
        (token, brand_id()),
    ).fetchone()
    conn.close()
    return row


def refresh_verify_challenge(user: sqlite3.Row) -> str:
    """Return plain email code (empty for Telegram). Updates stored hash."""
    contact = str(user["contact"] or "")
    email_code = "" if contact.startswith("@") else new_email_code()
    with LOCK:
        conn = db()
        conn.execute(
            """
            UPDATE users SET verify_code=?, verify_sent_at=?
            WHERE id=? AND verified=0
            """,
            (
                hash_verify_code(email_code) if email_code else "",
                now_ts() if email_code else 0,
                int(user["id"]),
            ),
        )
        conn.commit()
        conn.close()
    return email_code


PROMO_FAILED = "Промокод не применён: "


def activate_user(user: sqlite3.Row) -> tuple[sqlite3.Row, bool, str]:
    """Give node credentials, mark verified, apply pending referral/promo."""
    with ACTIVATE_LOCK:
        return activate_user_locked(user)


def activate_user_locked(user: sqlite3.Row) -> tuple[sqlite3.Row, bool, str]:
    # A double click waits here and then finds the account already active.
    with LOCK:
        conn = db()
        current = conn.execute("SELECT * FROM users WHERE id=?", (int(user["id"]),)).fetchone()
        if current is None:
            conn.close()
            raise RuntimeError("activate")
        if int(current["verified"] or 0) == 1 and int(current["active"] or 0) == 1:
            conn.close()
            return current, False, ""
        spare = None if STAGE else conn.execute("SELECT * FROM spare_creds ORDER BY id LIMIT 1").fetchone()
        if spare is not None:
            conn.execute("DELETE FROM spare_creds WHERE id=?", (int(spare["id"]),))
            conn.execute(
                "UPDATE users SET uuid=?, hy2_password=? WHERE id=?",
                (spare["uuid"], spare["hy2_password"], int(current["id"])),
            )
            conn.commit()
        conn.close()
    user = current
    if spare is None:
        push_user(user["uuid"], user["hy2_password"], "add")
    with LOCK:
        conn = db()
        conn.execute(
            """
            UPDATE users SET active=1, verified=1, verify_code='', verify_token='',
                verify_sent_at=0 WHERE id=?
            """,
            (int(user["id"]),),
        )
        conn.commit()
        fresh = conn.execute("SELECT * FROM users WHERE id=?", (int(user["id"]),)).fetchone()
        pending_ref = str(fresh["pending_ref"] or "") if fresh is not None else ""
        pending_promo = str(fresh["pending_promo"] or "") if fresh is not None else ""
        if fresh is not None:
            conn.execute(
                "UPDATE users SET pending_ref='', pending_promo='' WHERE id=?",
                (int(fresh["id"]),),
            )
            conn.commit()
            fresh = conn.execute("SELECT * FROM users WHERE id=?", (int(user["id"]),)).fetchone()
        conn.close()
    if fresh is None:
        raise RuntimeError("activate")
    invited = False
    if pending_ref:
        invited = grant_referral(pending_ref, fresh)
    promo_note = ""
    if pending_promo:
        try:
            promo_note = redeem_promo(fresh, pending_promo)
            fresh = user_by_contact(str(fresh["contact"])) or fresh
        except ValueError as exc:
            promo_note = PROMO_FAILED + str(exc)
    print("activated", fresh["public_id"], "spare" if spare is not None else "push", flush=True)
    return fresh, invited, promo_note


def purge_stale_unverified() -> None:
    cutoff = now_ts() - 86400
    with LOCK:
        conn = db()
        rows = conn.execute(
            "SELECT id, public_id FROM users WHERE verified=0 AND created_at<?",
            (cutoff,),
        ).fetchall()
        for row in rows:
            conn.execute("DELETE FROM users WHERE id=?", (int(row["id"]),))
            print("purged pending", row["public_id"], flush=True)
        conn.commit()
        conn.close()


def expire_due() -> None:
    with LOCK:
        conn = db()
        rows = conn.execute(
            "SELECT * FROM users WHERE active=1 AND expires_at<=?",
            (now_ts(),),
        ).fetchall()
        conn.close()
    for user in rows:
        # The node keeps the key until the nightly batch; the subscription already says it has ended.
        with NODE_LOCK, LOCK:
            conn = db()
            ended = conn.execute(
                "UPDATE users SET active=0 WHERE id=? AND active=1 AND expires_at<=?",
                (user["id"], now_ts()),
            ).rowcount
            if ended:
                conn.execute(
                    "INSERT OR REPLACE INTO pending_removals(uuid, hy2_password, created_at) VALUES(?, ?, ?)",
                    (user["uuid"], user["hy2_password"], now_ts()),
                )
            conn.commit()
            conn.close()
        if ended:
            print("expired", user["public_id"], flush=True)


def extend_user(public_id: str, days: int) -> sqlite3.Row:
    if days < 1 or days > 365:
        raise ValueError("Срок от 1 до 365 дней.")
    with LOCK:
        conn = db()
        user = conn.execute("SELECT * FROM users WHERE public_id=?", (public_id,)).fetchone()
        conn.close()
    if user is None:
        raise ValueError("Аккаунт не найден.")
    base = now_ts() if not user["active"] else max(now_ts(), int(user["expires_at"]))
    new_expiry = base + days * 86400
    if not user["active"]:
        push_user(user["uuid"], user["hy2_password"], "add")
    with LOCK:
        conn = db()
        conn.execute(
            "UPDATE users SET expires_at=?, active=1 WHERE id=?",
            (new_expiry, user["id"]),
        )
        conn.commit()
        user = conn.execute("SELECT * FROM users WHERE id=?", (user["id"],)).fetchone()
        conn.close()
    print("extended", public_id, days, flush=True)
    return user


def record_manual_extension(user_id: int, days: int) -> None:
    with LOCK:
        conn = db()
        conn.execute(
            "INSERT INTO payments(user_id, days, created_at, source) VALUES(?, ?, ?, 'admin')",
            (user_id, days, now_ts()),
        )
        conn.commit()
        conn.close()


PAY_AMOUNT = 110
PAY_DAYS = 30
PAY_LINK_TTL = 14 * 60
LOYALTY_EVERY = 6
LOYALTY_BONUS_DAYS = 7
PLATEGA_PROCESS = "https://app.platega.io/transaction/process"
PLATEGA_TRANSACTION = "https://app.platega.io/transaction/"
APPS_HINT = (
    "Windows и Android — приложение K-Pax: почта и код из письма. "
    "iPhone пока — INCY или Happ; своё приложение для iPhone скоро."
)


def sub_url(token: str) -> str:
    return "https://%s/s/%s" % (brand()["sub_host"], token)


def happ_deep_link(url: str) -> str:
    return "happ://add/" + url


def incy_deep_link(url: str) -> str:
    return "incy://add/" + url


def deep_link_buttons(url: str) -> str:
    return (
        '<p class="appopen">'
        '<a class="restore" href="%s">Открыть в Happ</a>'
        '<a class="restore" href="%s">Открыть в INCY</a>'
        "</p>"
        % (html.escape(happ_deep_link(url), quote=True), html.escape(incy_deep_link(url), quote=True))
    )


def deep_link_text(url: str) -> str:
    return (
        "Открыть одним тапом (если приложение установлено):\n"
        "Happ: %s\n"
        "INCY: %s"
    ) % (happ_deep_link(url), incy_deep_link(url))


def classify_os(agent: str) -> str:
    """Map User-Agent to android|ios|windows for admin OS column."""
    low = (agent or "").lower()
    if "android" in low or "dalvik" in low or "okhttp" in low:
        return "android"
    if any(token in low for token in ("iphone", "ipad", "cfnetwork")) or re.search(
        r"(?:^|[^a-z])ios(?:[^a-z]|$)", low
    ):
        return "ios"
    if "windows" in low or "win64" in low or "win32" in low:
        return "windows"
    return ""


def classify_client(agent: str) -> str:
    low = (agent or "").lower()
    os_name = classify_os(agent)
    if os_name in PLATFORM_LABELS:
        kind = PLATFORM_LABELS[os_name]
    elif any(token in low for token in ("mobile", "phone")):
        kind = "телефон"
    elif any(
        token in low
        for token in ("macintosh", "mac os", "linux", "x11", "electron", "desktop")
    ):
        kind = "ПК"
    else:
        kind = "устройство"
    if "incy" in low:
        app = "INCY"
    elif "happ" in low:
        app = "Happ"
    elif "k-pax" in low or "kpax" in low:
        app = "K-Pax"
    elif "x-plm" in low or "xplm" in low:
        app = "X-Plm"
    elif "v2rayng" in low:
        app = "v2rayNG"
    elif "v2rayn" in low:
        app = "v2rayN"
    else:
        app = ""
    return "%s (%s)" % (kind, app) if app else kind


def remember_platform(key: str, platform: str) -> None:
    name = (platform or "").strip().lower()
    if name not in PLATFORM_LABELS:
        return
    now = time.time()
    with DEVICE_LOCK:
        slots = PLATFORM_SEEN.setdefault(key, {})
        slots[name] = now
        for seen_name, seen_at in list(slots.items()):
            if now - seen_at > CLIENT_TTL:
                del slots[seen_name]


def recent_platforms(key: str, db_hits: dict[str, dict[str, float]] | None = None) -> list[str]:
    now = time.time()
    found: dict[str, float] = {}
    with DEVICE_LOCK:
        for name, seen in (PLATFORM_SEEN.get(key) or {}).items():
            if now - seen <= CLIENT_TTL and name in PLATFORM_LABELS:
                found[name] = seen
    if db_hits:
        for name, seen in (db_hits.get(key) or {}).items():
            if name in PLATFORM_LABELS:
                found[name] = max(found.get(name, 0.0), float(seen))
    return [name for name, _ in sorted(found.items(), key=lambda item: -item[1])]


def platforms_cell(platforms: list[str]) -> str:
    if not platforms:
        return "—"
    marks = []
    titles = []
    for name in platforms:
        mark = PLATFORM_MARKS.get(name)
        if not mark:
            continue
        marks.append(mark)
        titles.append(PLATFORM_LABELS.get(name, name))
    if not marks:
        return "—"
    # One line: A / IOS / W (title shows full names on hover).
    return (
        "<span class='os-marks' title='%s'>%s</span>"
        % (
            html.escape(" / ".join(titles), quote=True),
            html.escape(" / ".join(marks)),
        )
    )


def remember_client(user_uuid: str, agent: str) -> None:
    label = classify_client(agent)
    if not label:
        return
    key = user_key(user_uuid)
    remember_platform(key, classify_os(agent))
    now = time.time()
    with DEVICE_LOCK:
        slots = CLIENT_SEEN.setdefault(key, {})
        slots[label] = now
        for name, seen in list(slots.items()):
            if now - seen > CLIENT_TTL:
                del slots[name]
        if len(slots) > 4:
            for name, _ in sorted(slots.items(), key=lambda item: item[1])[: len(slots) - 4]:
                del slots[name]


def online_devices_line(user: sqlite3.Row) -> str:
    key = user_key(user["uuid"])
    live = live_people().get(key)
    count = int(live.get("devices") or 0) if live and live.get("online") else 0
    now = time.time()
    with DEVICE_LOCK:
        labels = [
            name
            for name, seen in sorted(
                (CLIENT_SEEN.get(key) or {}).items(),
                key=lambda item: -item[1],
            )
            if now - seen <= CLIENT_TTL
        ]
    if count <= 0:
        return "Сейчас онлайн: нет"
    shown = labels[: max(1, min(count, 2))]
    if shown:
        return "Сейчас онлайн: " + " / ".join(shown)
    if count == 1:
        return "Сейчас онлайн: 1 устройство"
    return "Сейчас онлайн: %d устройства" % count


FAQ_ITEMS = """
<details>
<summary>Куда вставлять ссылку?</summary>
<p>В INCY или Happ нажмите «+» и вставьте ссылку или отсканируйте QR. На Windows откройте K-Pax и вставьте туда же. Можно нажать «Открыть в Happ / INCY» — если приложение установлено, ссылка добавится сама.</p>
</details>
<details>
<summary>Почему ссылка не показывается повторно?</summary>
<p>Ссылка выдаётся один раз при регистрации. Вернуть её можно письмом с той же почты на access@k-pax.space или через бота @KPax_Space_bot с того же Telegram.</p>
</details>
<details>
<summary>Как оплатить?</summary>
<p>110 ₽ за 30 дней через СБП: QR или ссылка из банковского приложения. Без автопродления и без привязки карты. Оплата на сайте /pay или в боте.</p>
</details>
<details>
<summary>Сколько устройств?</summary>
<p>Два одновременно: обычно телефон и компьютер. Одна ссылка на оба.</p>
</details>
<details>
<summary>Работают ли торренты?</summary>
<p>Нет. Торренты на подключении не работают.</p>
</details>
<details>
<summary>Можно ли вернуть деньги?</summary>
<p>После выдачи доступа возврат не производится, кроме случая, когда услуга не оказана по технической вине. Заявление — в течение 24 часов на support@k-pax.space. Подробнее в <a href="/terms#refund">условиях возврата</a>.</p>
</details>
<details>
<summary>Что значит «без автопродления»?</summary>
<p>Списывается разовая сумма 110 ₽. Карту не привязываем, следующий месяц сам не продлится — продлить можно снова, когда удобно.</p>
</details>
<details>
<summary>Как оплатить другу?</summary>
<p>На главной или на <a href="/pay">/pay</a> укажите почту или Telegram друга — оплата продлит его счёт. Ссылка подключения у него останется прежней.</p>
</details>
"""

FAQ_FAB = '<a class="faqfab" href="/faq">FAQ</a>'

FAQ_DESC = (
    "Ответы на частые вопросы K-Pax: ссылка, оплата, устройства, возврат, поддержка."
)


def platega_creds(bid: str | None = None) -> tuple[str, str]:
    """Each brand has its own Platega shop; K-Pax keeps the top-level keys."""
    source = CFG if (bid or brand_id()) == "kpax" else brand_cfg(bid)
    return str(source.get("platega_merchant_id") or ""), str(source.get("platega_secret") or "")


def platega_configured(bid: str | None = None) -> bool:
    merchant, secret = platega_creds(bid)
    return bool(merchant) and bool(secret)


def pay_amount(bid: str | None = None) -> int:
    return int(BRANDS.get(bid or brand_id(), BRANDS["kpax"])["price"])


def platega_header_brand(merchant: str, secret: str) -> str | None:
    """Brand whose Platega shop signed the callback, or None."""
    for bid in BRANDS:
        expected_merchant, expected_secret = platega_creds(bid)
        if (
            not expected_merchant
            or not expected_secret
            or len(merchant) != len(expected_merchant)
            or len(secret) != len(expected_secret)
        ):
            continue
        if hmac.compare_digest(merchant, expected_merchant) and hmac.compare_digest(secret, expected_secret):
            return bid
    return None


def money_ok(amount: object, currency: object, price: int = PAY_AMOUNT) -> bool:
    """The brand tariff. Platega may add its fee on top, so the paid sum can be higher."""
    if str(currency or "").upper() != "RUB":
        return False
    try:
        value = float(amount)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return False
    return value + 0.001 >= price


def user_by_contact(contact: str) -> sqlite3.Row | None:
    conn = db()
    row = conn.execute(
        "SELECT * FROM users WHERE lower(contact)=lower(?) AND brand=? LIMIT 1",
        (contact, brand_id()),
    ).fetchone()
    conn.close()
    return row


def platega_request(url: str, payload: dict | None = None, bid: str | None = None) -> dict:
    merchant, secret = platega_creds(bid)
    if not merchant or not secret:
        raise RuntimeError("platega")
    headers = {
        "X-MerchantId": merchant,
        "X-Secret": secret,
        "Accept": "application/json",
    }
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method="POST" if payload is not None else "GET")
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            parsed = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        print("platega http", exc.code, flush=True)
        raise RuntimeError("platega") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError("platega")
    return parsed


def pay_redirect_ok(url: str) -> bool:
    parsed = urlparse(url)
    return parsed.scheme == "https" and (parsed.hostname or "").lower() == "pay.platega.io"


def create_platega_invoice(user: sqlite3.Row) -> str:
    bid = str(user["brand"] or "kpax")
    shop = BRANDS[bid]
    amount = pay_amount(bid)
    created = platega_request(
        PLATEGA_PROCESS,
        {
            "paymentMethod": 2,
            "paymentDetails": {"amount": amount, "currency": "RUB"},
            "description": "Подписка %s, 30 дней" % shop["name"],
            "return": "https://%s/pay/done" % shop["host"],
            "failedUrl": "https://%s/pay/fail" % shop["host"],
            "payload": user["public_id"],
            "metadata": {"userId": user["public_id"], "userName": user["public_id"]},
        },
        bid,
    )
    transaction_id = str(created.get("transactionId") or "")
    redirect = str(created.get("redirect") or "")
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", transaction_id) or not pay_redirect_ok(redirect):
        raise RuntimeError("platega")
    stamp = now_ts()
    with LOCK:
        conn = db()
        conn.execute(
            """
            INSERT INTO platega_invoices(
                transaction_id, user_id, public_id, amount, currency, status, created_at, updated_at, redirect
            ) VALUES(?, ?, ?, ?, 'RUB', 'PENDING', ?, ?, ?)
            """,
            (transaction_id, int(user["id"]), user["public_id"], amount, stamp, stamp, redirect),
        )
        conn.commit()
        conn.close()
    print("invoice", user["public_id"], flush=True)
    return redirect


def live_invoice_redirect(user_id: int) -> str:
    conn = db()
    row = conn.execute(
        """
        SELECT redirect FROM platega_invoices
        WHERE user_id=? AND status='PENDING' AND created_at>? AND redirect!=''
        ORDER BY id DESC LIMIT 1
        """,
        (user_id, now_ts() - PAY_LINK_TTL),
    ).fetchone()
    conn.close()
    if row is None:
        return ""
    redirect = str(row["redirect"] or "")
    return redirect if pay_redirect_ok(redirect) else ""


def begin_payment(user: sqlite3.Row, rate_key: str) -> tuple[str, str]:
    """Create or reuse a Platega invoice. Returns ('ok', redirect) or ('error', message)."""
    if not BRANDS.get(str(user["brand"] or "kpax"), BRANDS["kpax"])["payments"]:
        return "error", PAY_STUB_TEXT
    alive = live_invoice_redirect(int(user["id"]))
    if alive:
        return "ok", alive
    if pay_limited(rate_key):
        return "error", "Слишком много попыток. Попробуйте позже."
    if recent_invoices(int(user["id"])) >= 5:
        return "error", "Счёт на оплату уже создан. Подождите и попробуйте ещё раз."
    if not platega_configured(str(user["brand"] or "kpax")):
        bid = str(user["brand"] or "kpax")
        support = REMIND_BRAND.get(bid, REMIND_BRAND["kpax"])["support"]
        return "error", "Оплата временно недоступна. Напишите на %s." % support
    note_pay_start(rate_key)
    try:
        return "ok", create_platega_invoice(user)
    except Exception as exc:  # noqa: BLE001
        print("invoice failed", user["public_id"], type(exc).__name__, flush=True)
        return "error", "Не получилось открыть оплату. Попробуйте через минуту."


def notice_once(user_id: int, kind: str, ref: str = "") -> bool:
    with LOCK:
        conn = db()
        try:
            conn.execute(
                "INSERT INTO notices(user_id, kind, ref, created_at) VALUES(?, ?, ?, ?)",
                (user_id, kind, ref, now_ts()),
            )
            conn.commit()
            conn.close()
            return True
        except sqlite3.IntegrityError:
            conn.rollback()
            conn.close()
            return False


def remember_telegram_chat(contact: str, chat_id: int) -> None:
    if not contact.startswith("@") or not isinstance(chat_id, int):
        return
    with LOCK:
        conn = db()
        conn.execute(
            "UPDATE users SET telegram_chat_id=? WHERE lower(contact)=lower(?) AND brand='kpax'",
            (chat_id, contact),
        )
        conn.commit()
        conn.close()


def paid_message(user: sqlite3.Row, bonus_days: int = 0) -> str:
    bid = str(user["brand"] or "kpax") if "brand" in user.keys() else "kpax"
    meta = REMIND_BRAND.get(bid, REMIND_BRAND["kpax"])
    extra = ""
    if bonus_days:
        extra = (
            "\nБонус лояльности: +%d дн. (каждая %d-я оплата)."
            % (bonus_days, LOYALTY_EVERY)
        )
    return (
        "Оплата прошла. Подписка продлена на %d дней.\n"
        "Доступ до %s.\n"
        "Ссылка подключения не менялась. Без автопродления — карта не привязана.\n"
        "%s%s\n"
        "Пригласить друга (+15 дней к вашей подписке):\n"
        "%s/?ref=%s"
    ) % (
        PAY_DAYS,
        fmt(int(user["expires_at"])),
        online_devices_line(user),
        extra,
        meta["site"],
        user["public_id"],
    )


def remind_message(user: sqlite3.Row) -> str:
    bid = str(user["brand"] or "kpax") if "brand" in user.keys() else "kpax"
    meta = REMIND_BRAND.get(bid, REMIND_BRAND["kpax"])
    bot = "\nИли в боте: Оплатить" if bid == "kpax" else ""
    return (
        "Подписка %s заканчивается %s.\n"
        "Осталось %d дн. Продлить на 30 дней за %d ₽ — без автопродления:\n"
        "%s/pay%s"
    ) % (
        meta["name"],
        fmt(int(user["expires_at"])),
        days_remaining(int(user["expires_at"])),
        meta["price"],
        meta["site"],
        bot,
    )


def notify_user(user: sqlite3.Row, text: str, markup: dict | None = None) -> None:
    bid = str(user["brand"] or "kpax") if "brand" in user.keys() else "kpax"
    contact = str(user["contact"] or "")
    with brand_context(bid):
        if contact and not contact.startswith("@"):
            mail = brand_mail()
            if mail:
                try:
                    send_restore_mail(mail, contact, text)
                except Exception as exc:  # noqa: BLE001
                    print("notify mail failed", user["public_id"], type(exc).__name__, flush=True)
    chat_id = user["telegram_chat_id"] if "telegram_chat_id" in user.keys() else None
    if chat_id and bid == "kpax":
        try:
            telegram_reply(int(chat_id), text, markup)
        except Exception as exc:  # noqa: BLE001
            print("notify telegram failed", user["public_id"], type(exc).__name__, flush=True)


def notify_paid(user_id: int, transaction_id: str, bonus_days: int = 0) -> None:
    if not notice_once(user_id, "paid", transaction_id):
        return
    conn = db()
    user = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
    conn.close()
    if user is None:
        return
    try:
        notify_user(user, paid_message(user, bonus_days), MAIN_KEYBOARD)
        print("paid notice", user["public_id"], flush=True)
    except Exception as exc:  # noqa: BLE001
        print("paid notice failed", user["public_id"], type(exc).__name__, flush=True)


def platega_paid_value(remote: dict, price: int = PAY_AMOUNT) -> tuple[float | None, str]:
    details = remote.get("paymentDetails")
    amount: object = None
    currency = "RUB"
    if isinstance(details, dict):
        amount = details.get("amount")
        currency = str(details.get("currency") or "RUB")
    elif isinstance(details, str):
        match = re.fullmatch(r"\s*([0-9]+(?:[.,][0-9]+)?)\s+([A-Za-z]{3})\s*", details)
        if match:
            amount = match.group(1).replace(",", ".")
            currency = match.group(2).upper()
    try:
        value = float(amount) if amount is not None else None  # type: ignore[arg-type]
    except (TypeError, ValueError):
        value = None
    if value is None:
        return None, currency
    try:
        fee = float(remote.get("comission") or 0)
    except (TypeError, ValueError):
        fee = 0
    if fee > 0 and value < price and value + fee + 0.001 >= price:
        value += fee
    return value, currency


def platega_confirmed(transaction_id: str, public_id: str, bid: str = "kpax") -> bool:
    remote = platega_request(PLATEGA_TRANSACTION + transaction_id, bid=bid)
    status = str(remote.get("status") or "").upper()
    if status != "CONFIRMED":
        if status not in ("PENDING", ""):
            print("platega wait", public_id, status, flush=True)
        if status in ("CANCELED", "CHARGEBACKED"):
            note_platega_status(transaction_id, status)
        return False
    echoed = str(remote.get("payload") or "")
    if echoed and echoed != public_id:
        print("platega payload mismatch", public_id, flush=True)
        return False
    value, currency = platega_paid_value(remote, pay_amount(bid))
    if value is None:
        print("platega amount", public_id, "missing", flush=True)
        return True
    if money_ok(value, currency, pay_amount(bid)):
        return True
    print("platega amount", public_id, value, currency, flush=True)
    return False


def reconcile_platega() -> None:
    conn = db()
    rows = conn.execute(
        """
        SELECT i.transaction_id, i.public_id, COALESCE(u.brand, 'kpax') AS brand
        FROM platega_invoices i LEFT JOIN users u ON u.id = i.user_id
        WHERE i.status='PENDING' AND i.created_at>?
        ORDER BY i.id
        LIMIT 30
        """,
        (now_ts() - 2 * 86400,),
    ).fetchall()
    conn.close()
    for row in rows:
        if not platega_configured(row["brand"]):
            continue
        try:
            result = grant_paid_invoice(row["transaction_id"])
        except Exception as exc:  # noqa: BLE001
            print("platega reconcile", row["public_id"], type(exc).__name__, flush=True)
            continue
        if result == "granted":
            print("platega reconcile", row["public_id"], flush=True)


def platega_loop() -> None:
    while True:
        time.sleep(90)
        try:
            reconcile_platega()
        except Exception as exc:  # noqa: BLE001
            print("platega loop", type(exc).__name__, flush=True)


def grant_paid_invoice(transaction_id: str, shop: str | None = None) -> str:
    """shop is the brand whose Platega callback arrived; an invoice of another brand is refused."""
    with LOCK:
        conn = db()
        row = conn.execute(
            "SELECT * FROM platega_invoices WHERE transaction_id=?",
            (transaction_id,),
        ).fetchone()
        if row is None:
            conn.close()
            return "missing"
        if row["status"] == "CONFIRMED":
            conn.close()
            return "duplicate"
        user = conn.execute("SELECT * FROM users WHERE id=?", (int(row["user_id"]),)).fetchone()
        conn.close()
    if user is None:
        return "missing"
    bid = str(user["brand"] or "kpax")
    if shop is not None and shop != bid:
        print("platega shop mismatch", row["public_id"], flush=True)
        return "missing"
    if int(row["amount"]) != pay_amount(bid) or row["currency"] != "RUB":
        print("platega amount", row["public_id"], flush=True)
        return "amount"
    if not platega_confirmed(transaction_id, user["public_id"], bid):
        return "unconfirmed"
    if not user["active"]:
        push_user(user["uuid"], user["hy2_password"], "add")
    with LOCK:
        conn = db()
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute(
            "SELECT * FROM platega_invoices WHERE transaction_id=?",
            (transaction_id,),
        ).fetchone()
        if row is None or row["status"] == "CONFIRMED":
            conn.rollback()
            conn.close()
            return "duplicate" if row is not None else "missing"
        user = conn.execute("SELECT * FROM users WHERE id=?", (int(row["user_id"]),)).fetchone()
        if user is None:
            conn.rollback()
            conn.close()
            return "missing"
        base = now_ts() if not user["active"] else max(now_ts(), int(user["expires_at"]))
        new_expiry = base + PAY_DAYS * 86400
        updated = conn.execute(
            "UPDATE platega_invoices SET status='CONFIRMED', updated_at=? WHERE id=? AND status!='CONFIRMED'",
            (now_ts(), int(row["id"])),
        ).rowcount
        if updated != 1:
            conn.rollback()
            conn.close()
            return "duplicate"
        paid_n = conn.execute(
            "SELECT COUNT(*) FROM platega_invoices WHERE user_id=? AND status='CONFIRMED'",
            (int(user["id"]),),
        ).fetchone()[0]
        bonus_days = LOYALTY_BONUS_DAYS if int(paid_n) % LOYALTY_EVERY == 0 else 0
        new_expiry += bonus_days * 86400
        conn.execute(
            "UPDATE users SET expires_at=?, active=1 WHERE id=?",
            (new_expiry, int(user["id"])),
        )
        conn.execute(
            "INSERT INTO payments(user_id, days, created_at) VALUES(?, ?, ?)",
            (int(user["id"]), PAY_DAYS + bonus_days, now_ts()),
        )
        conn.commit()
        user_id = int(user["id"])
        conn.close()
    print("paid", user["public_id"], "bonus", bonus_days, flush=True)
    notify_paid(user_id, transaction_id, bonus_days)
    return "granted"


def apply_chargeback(transaction_id: str) -> str:
    with LOCK:
        conn = db()
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute(
            "SELECT * FROM platega_invoices WHERE transaction_id=?",
            (transaction_id,),
        ).fetchone()
        if row is None:
            conn.rollback()
            conn.close()
            return "missing"
        if row["status"] == "CHARGEBACKED":
            conn.rollback()
            conn.close()
            return "duplicate"
        was_paid = row["status"] == "CONFIRMED"
        user = conn.execute("SELECT * FROM users WHERE id=?", (int(row["user_id"]),)).fetchone()
        if user is None:
            conn.execute(
                "UPDATE platega_invoices SET status='CHARGEBACKED', updated_at=? WHERE id=?",
                (now_ts(), int(row["id"])),
            )
            conn.commit()
            conn.close()
            return "missing"
        new_expiry = int(user["expires_at"])
        active = int(user["active"])
        if was_paid:
            new_expiry = max(now_ts(), new_expiry - PAY_DAYS * 86400)
            if new_expiry <= now_ts():
                active = 0
            conn.execute(
                "UPDATE users SET expires_at=?, active=? WHERE id=?",
                (new_expiry, active, int(user["id"])),
            )
        conn.execute(
            "UPDATE platega_invoices SET status='CHARGEBACKED', updated_at=? WHERE id=?",
            (now_ts(), int(row["id"])),
        )
        conn.commit()
        conn.close()
    was_active = bool(user["active"])
    if was_paid and active == 0 and was_active:
        try:
            push_user(user["uuid"], user["hy2_password"], "remove")
        except Exception as exc:  # noqa: BLE001
            print("chargeback push failed", user["public_id"], type(exc).__name__, flush=True)
    print("chargeback", user["public_id"], flush=True)
    if was_paid and notice_once(int(user["id"]), "chargeback", transaction_id):
        text = (
            "Оплата по счёту %s отменена банком.\n"
            "Срок доступа пересчитан: до %s."
            % (user["public_id"], fmt(new_expiry))
        )
        conn = db()
        fresh = conn.execute("SELECT * FROM users WHERE id=?", (int(user["id"]),)).fetchone()
        conn.close()
        if fresh is not None:
            notify_user(fresh, text)
    return "chargebacked"


def note_platega_status(transaction_id: str, status: str) -> None:
    if status == "CHARGEBACKED":
        apply_chargeback(transaction_id)
        return
    if status != "CANCELED":
        return
    with LOCK:
        conn = db()
        conn.execute(
            """
            UPDATE platega_invoices
            SET status=?, updated_at=?
            WHERE transaction_id=? AND status!='CONFIRMED'
            """,
            (status, now_ts(), transaction_id),
        )
        conn.commit()
        conn.close()


def accept_platega_callback(payload: dict, shop: str = "kpax") -> str:
    transaction_id = str(payload.get("id") or payload.get("Id") or "")
    status = str(payload.get("status") or payload.get("Status") or "").upper()
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", transaction_id):
        return "ignored"
    if status == "CONFIRMED":
        result = grant_paid_invoice(transaction_id, shop)
        if result == "missing":
            print("platega unknown", flush=True)
        return result
    if status == "CHARGEBACKED":
        return apply_chargeback(transaction_id)
    if status == "CANCELED":
        note_platega_status(transaction_id, status)
        return "canceled"
    return "ignored"


def delete_user(public_id: str) -> None:
    with LOCK:
        conn = db()
        user = conn.execute("SELECT * FROM users WHERE public_id=?", (public_id,)).fetchone()
        conn.close()
    if user is None:
        raise ValueError("not found")
    if user["active"]:
        push_user(user["uuid"], user["hy2_password"], "remove")
    with LOCK:
        conn = db()
        conn.execute("DELETE FROM users WHERE id=?", (user["id"],))
        conn.commit()
        conn.close()


KALEID_SCRIPT = """<script>
(function () {
  var canvas = document.getElementById("kpax-space");
  if (!canvas) return;
  var ctx = canvas.getContext("2d", { alpha: false });
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var stars = document.createElement("canvas");
  var sctx = stars.getContext("2d", { alpha: false });
  var starDots = [];
  var shards = [];
  var mesh = [];
  var sun = null;
  var flare = { on: false, t0: 0, dur: 520, done: 0 };
  var smooth = 0;
  var lastScroll = 0;
  var lastY = window.scrollY;
  var lastT = 0;
  var w = 0;
  var h = 0;
  var dpr = 1;
  var narrow = false;
  var builtW = 0;
  var builtH = 0;
  var resizeTimer = 0;
  var aimX = 0;
  var aimY = 0;
  var lookX = 0;
  var lookY = 0;
  var parAim = 0;
  var parY = 0;
  var glareAmt = 0;

  function rnd(n) {
    var x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
    return x - Math.floor(x);
  }
  function clamp(v, a, b) {
    return v < a ? a : v > b ? b : v;
  }
  function mix(a, b, t) {
    return a + (b - a) * t;
  }

  function layout() {
    var nw = window.innerWidth;
    var nh = window.innerHeight;
    if (shards.length && Math.abs(nw - builtW) < 2 && Math.abs(nh - builtH) < 140) return;
    w = nw;
    h = nh;
    narrow = w < 800;
    builtW = w;
    builtH = h;
    dpr = Math.min(window.devicePixelRatio || 1, narrow ? 1 : 2);
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.width = w + "px";
    canvas.style.height = h + "px";
    stars.width = w + 280;
    stars.height = h + 280;
    buildStars();
    buildShards();
    var span = Math.max(1, document.documentElement.scrollHeight - h);
    parAim = reduce ? 0 : 0.5 - clamp(window.scrollY / span, 0, 1);
    parY = parAim;
  }

  function layerShift(layer) {
    var depth = layer === 2 ? 1 : layer === 1 ? 0.58 : 0.28;
    return {
      x: lookX * (10 + 16 * depth),
      y: lookY * (6 + 12 * depth) + parY * (18 + 34 * depth)
    };
  }

  function buildStars() {
    starDots = [];
    var count = Math.round(w * h / 48000);
    if (count < 18) count = 18;
    if (count > 48) count = 48;
    var i;
    for (i = 0; i < count; i++) {
      starDots.push({
        x: rnd(i + 1) * w,
        y: rnd(i + 19) * h,
        r: rnd(i + 3) > 0.9 ? 1.8 : 0.9 + rnd(i + 8) * 0.7,
        a: 0.72 + rnd(i + 5) * 0.28,
        tw: rnd(i + 11) > 0.88,
        phase: rnd(i + 13) * Math.PI * 2
      });
    }
  }

  function paintStars(now) {
    var driftX = reduce ? 0 : (now * 0.034) % w;
    var driftY = reduce ? 0 : (now * 0.016) % h;
    var g = sctx.createLinearGradient(0, 0, stars.width, stars.height);
    g.addColorStop(0, "#041025");
    g.addColorStop(0.5, "#020712");
    g.addColorStop(1, "#07182f");
    sctx.fillStyle = g;
    sctx.fillRect(0, 0, stars.width, stars.height);
    var i, dot, alpha, px, py;
    for (i = 0; i < starDots.length; i++) {
      dot = starDots[i];
      alpha = dot.a;
      if (dot.tw && !reduce) alpha = dot.a * (0.55 + 0.45 * Math.sin(now * 0.0012 + dot.phase));
      sctx.fillStyle = "rgba(255,255,255," + alpha.toFixed(3) + ")";
      px = ((dot.x + driftX) % w + w) % w;
      py = ((dot.y + driftY) % h + h) % h;
      blotStar(px + 140, py + 140, dot.r);
      if (px < 140) blotStar(px + 140 + w, py + 140, dot.r);
      if (px > w - 140) blotStar(px + 140 - w, py + 140, dot.r);
      if (py < 140) blotStar(px + 140, py + 140 + h, dot.r);
      if (py > h - 140) blotStar(px + 140, py + 140 - h, dot.r);
    }
  }

  function blotStar(x, y, r) {
    sctx.beginPath();
    sctx.arc(x, y, r, 0, Math.PI * 2);
    sctx.fill();
  }

  function addFace(refs, role, clock) {
    var cx = 0;
    var cy = 0;
    var i;
    for (i = 0; i < refs.length; i++) {
      cx += refs[i].bx;
      cy += refs[i].by;
    }
    cx /= refs.length;
    cy /= refs.length;
    var n = shards.length + 3;
    var layer = rnd(n * 5) > 0.66 ? 2 : rnd(n + 4) > 0.5 ? 1 : 0;
    var shard = {
      verts: refs, role: role, clock: clock, hidden: false,
      cx: cx, cy: cy, minX: 0, minY: 0, maxX: 0, maxY: 0,
      baseR: 8 + rnd(n + 63) * 26,
      baseG: 18 + rnd(n + 67) * 36,
      baseB: 44 + rnd(n + 71) * 54,
      baseA: 0.3 + rnd(n + 73) * 0.16,
      shadeDir: rnd(n + 51) > 0.5 ? 1 : -1,
      shadeAmp: 0.14 + rnd(n + 79) * 0.18,
      shadeT: rnd(n + 83) * Math.PI * 2,
      shadeRate: 0.4 + rnd(n + 89) * 1.15,
      layer: layer,
      baseX: (rnd(n + 2) - 0.5) * 4,
      baseY: (rnd(n + 6) - 0.5) * 4,
      baseZ: (rnd(n + 8) - 0.5) * 1.6,
      rotX: 0, rotY: 0, rotZ: 0,
      ampX: 3 + rnd(n + 11) * 4,
      ampY: 3 + rnd(n + 15) * 4,
      ampZ: 1 + rnd(n + 19) * 2,
      dirX: rnd(n + 21) > 0.5 ? 1 : -1,
      dirY: rnd(n + 23) > 0.5 ? 1 : -1,
      dirZ: rnd(n + 27) > 0.5 ? 1 : -1,
      phase: rnd(n + 31) * Math.PI * 2,
      glare: rnd(n + 91) > 0.72,
      glareAng: rnd(n + 93) * 6.2832,
      glareU: 0.2 + rnd(n + 97) * 0.6,
      glareV: 0.16 + rnd(n + 101) * 0.62,
      glareA: 0.34 + rnd(n + 103) * 0.4,
      sun: false, glint: 0, prevY: 0
    };
    shard.rotX = shard.baseX;
    shard.rotY = shard.baseY;
    shard.rotZ = shard.baseZ;
    shard.prevY = shard.baseY;
    shards.push(shard);
    return shard;
  }

  function morphM(clock) {
    if (!clock.morph || reduce) return clock.asQuad ? 1 : 0;
    return 0.5 + 0.5 * Math.sin(clock.morphT);
  }

  function faceOn(s) {
    return !(s.role === "shrink" && s.clock.m > 0.97);
  }

  function buildShards() {
    var cols = w < 700 ? 6 : w < 1200 ? 9 : 12;
    var pad = Math.max(78, Math.min(w, h) * 0.1);
    var gw = w + pad * 2;
    var gh = h + pad * 2;
    var rows = Math.round(cols * gh / gw);
    if (rows < 5) rows = 5;
    mesh = [];
    var r, c, x, y, edge, v;
    for (r = 0; r <= rows; r++) {
      for (c = 0; c <= cols; c++) {
        x = -pad + (c / cols) * gw;
        y = -pad + (r / rows) * gh;
        edge = c === 0 || r === 0 || c === cols || r === rows;
        if (!edge && c > 0 && c < cols) x += (rnd(r * 40 + c) - 0.5) * (w / cols) * 0.58;
        if (!edge && r > 0 && r < rows) y += (rnd(c * 37 + r + 9) - 0.5) * (h / rows) * 0.58;
        v = {
          bx: x, by: y, x: x, y: y,
          phase: rnd(r * 17 + c + 3) * 6.2832,
          ax: edge ? 0 : (rnd(r * 9 + c + 5) - 0.5) * 14,
          ay: edge ? 0 : (rnd(c * 8 + r + 7) - 0.5) * 14
        };
        mesh.push(v);
      }
    }
    shards = [];
    sun = null;
    var stride = cols + 1;
    var idx, a, b, d, e, clock, n;
    for (r = 0; r < rows; r++) {
      for (c = 0; c < cols; c++) {
        idx = r * stride + c;
        a = mesh[idx];
        b = mesh[idx + 1];
        d = mesh[idx + stride];
        e = mesh[idx + stride + 1];
        n = r * cols + c + 3;
        clock = {
          morph: rnd(n + 53) > 0.18,
          morphT: rnd(n + 57) * 6.2832,
          morphRate: 0.55 + rnd(n + 59) * 0.95,
          asQuad: rnd(n + 61) > 0.45,
          b: b, e: e,
          pivot: { x: b.x, y: b.y }
        };
        clock.m = morphM(clock);
        addFace([a, b, clock.pivot, d], "grow", clock);
        addFace([clock.pivot, e, d], "shrink", clock);
      }
    }
    var best = null;
    var score = 1e9;
    var i, nx, ny, sc;
    for (i = 0; i < shards.length; i++) {
      if (!faceOn(shards[i])) continue;
      nx = shards[i].cx / w;
      ny = shards[i].cy / h;
      if (nx < 0.6 || nx > 0.9 || ny < 0.06 || ny > 0.42) continue;
      sc = Math.abs(nx - 0.76) + Math.abs(ny - 0.16);
      if (sc < score) {
        score = sc;
        best = shards[i];
      }
    }
    if (best) {
      best.sun = true;
      best.layer = 2;
      best.ampY = 6;
      best.glint = best.baseY + best.dirY * 1.15;
      best.prevY = best.baseY;
      sun = best;
    }
    var morphs = 0;
    var glares = 0;
    for (i = 0; i < shards.length; i++) {
      if (shards[i].clock.morph) morphs++;
      if (shards[i].glare) glares++;
    }
    canvas.dataset.shards = String(shards.length);
    canvas.dataset.morph = String(morphs);
    canvas.dataset.glare = String(glares);
  }

  function toneOf(s) {
    var wave = reduce ? 0.6 : (0.5 + 0.5 * Math.sin(s.shadeT));
    var lift = s.shadeDir * (3 + s.shadeAmp * 12) * wave;
    function rgb(extra) {
      var t = lift + extra;
      return (clamp(3 + t * 0.22, 1, 16) | 0) + "," +
        (clamp(8 + t * 0.38, 4, 24) | 0) + "," +
        (clamp(18 + t * 0.7, 10, 40) | 0);
    }
    if (narrow) {
      return {
        fill: "rgba(" + rgb(1) + ",0.94)",
        edge: "rgba(140,164,188," + (0.06 + 0.04 * wave).toFixed(3) + ")"
      };
    }
    var poly = s.view;
    var last = poly[poly.length - 1];
    var g = ctx.createLinearGradient(poly[0].x, poly[0].y, last.x, last.y);
    g.addColorStop(0, "rgba(" + rgb(-2.5) + ",0.94)");
    g.addColorStop(1, "rgba(" + rgb(4) + ",0.94)");
    return {
      fill: g,
      edge: "rgba(140,164,188," + (0.06 + 0.04 * wave).toFixed(3) + ")"
    };
  }

  function meshShift() {
    if (reduce) return { x: 0, y: 0 };
    return {
      x: lookX * 22,
      y: lookY * 14 + parY * 36
    };
  }

  function moveVerts(now) {
    var shift = meshShift();
    var boost = reduce ? 0 : (1 + Math.abs(smooth) * (narrow ? 0.2 : 1.4));
    var i, v, wob;
    for (i = 0; i < mesh.length; i++) {
      v = mesh[i];
      wob = reduce ? 0 : Math.sin(now * 0.0005 + v.phase);
      v.x = v.bx + wob * v.ax * boost + shift.x;
      v.y = v.by + wob * v.ay * boost + shift.y;
    }
  }

  function syncPivots() {
    var i, clock, m, b, e, p;
    for (i = 0; i < shards.length; i++) {
      if (shards[i].role !== "grow") continue;
      clock = shards[i].clock;
      m = morphM(clock);
      clock.m = m;
      b = clock.b;
      e = clock.e;
      p = clock.pivot;
      p.x = b.x + (e.x - b.x) * m;
      p.y = b.y + (e.y - b.y) * m;
    }
  }

  function place(s) {
    var view = s.verts;
    var minX = 1e9;
    var minY = 1e9;
    var maxX = -1e9;
    var maxY = -1e9;
    var i, p;
    for (i = 0; i < view.length; i++) {
      p = view[i];
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    s.view = view;
    s.minX = minX;
    s.minY = minY;
    s.maxX = maxX;
    s.maxY = maxY;
  }

  function drawPoly(s) {
    var poly = s.view;
    ctx.beginPath();
    ctx.moveTo(poly[0].x, poly[0].y);
    var i;
    for (i = 1; i < poly.length; i++) ctx.lineTo(poly[i].x, poly[i].y);
    ctx.closePath();
  }

  function hit(x, y, poly) {
    var n = poly.length;
    var j = n - 1;
    var inside = false;
    var i;
    for (i = 0; i < n; i++) {
      if (((poly[i].y > y) !== (poly[j].y > y)) &&
          (x < (poly[j].x - poly[i].x) * (y - poly[i].y) / ((poly[j].y - poly[i].y) || 0.0001) + poly[i].x)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  function drawGlare(s) {
    var poly = s.view;
    var n = poly.length;
    if (n < 2) return;
    var pulse = glareAmt * (0.62 + 0.38 * Math.sin(s.shadeT * 0.7 + s.phase));
    var start = Math.floor(s.glareU * n) % n;
    var count = s.glareV > 0.62 ? 2 : 1;
    var e, i, a, b, len, alpha, g;
    ctx.save();
    ctx.lineCap = "round";
    for (e = 0; e < count; e++) {
      i = (start + e) % n;
      a = poly[i];
      b = poly[(i + 1) % n];
      len = Math.hypot(b.x - a.x, b.y - a.y);
      if (len < 10) continue;
      alpha = Math.min(1, s.glareA * pulse);
      if (narrow) {
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.strokeStyle = "rgba(255,255,255," + alpha.toFixed(3) + ")";
        ctx.lineWidth = 1.6;
        ctx.stroke();
        continue;
      }
      g = ctx.createLinearGradient(a.x, a.y, b.x, b.y);
      g.addColorStop(0, "rgba(255,255,255,0)");
      g.addColorStop(0.22, "rgba(210,230,255," + (0.25 * alpha).toFixed(3) + ")");
      g.addColorStop(0.5, "rgba(255,255,255," + alpha.toFixed(3) + ")");
      g.addColorStop(0.78, "rgba(210,230,255," + (0.25 * alpha).toFixed(3) + ")");
      g.addColorStop(1, "rgba(255,255,255,0)");
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.strokeStyle = g;
      ctx.lineWidth = 2.2;
      ctx.stroke();
    }
    ctx.restore();
  }

  function drawFlare(s, now) {
    var t = (now - flare.t0) / flare.dur;
    if (t < 0 || t > 1) return;
    var poly = s.view;
    var n = poly.length;
    var best = 0;
    var bestLen = 0;
    var i, a, b, len;
    for (i = 0; i < n; i++) {
      a = poly[i];
      b = poly[(i + 1) % n];
      len = Math.hypot(b.x - a.x, b.y - a.y);
      if (len > bestLen) {
        bestLen = len;
        best = i;
      }
    }
    if (bestLen < 10) return;
    a = poly[best];
    b = poly[(best + 1) % n];
    var pulse = Math.sin(t * Math.PI);
    var g = ctx.createLinearGradient(a.x, a.y, b.x, b.y);
    g.addColorStop(0, "rgba(255,255,255,0)");
    g.addColorStop(0.5, "rgba(255,255,255," + (0.95 * pulse).toFixed(3) + ")");
    g.addColorStop(1, "rgba(255,255,255,0)");
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.strokeStyle = g;
    ctx.lineWidth = 2.6;
    ctx.lineCap = "round";
    ctx.stroke();
  }

  function frame(now) {
    if (!lastT) lastT = now;
    var dt = now - lastT;
    if (dt < 0) dt = 0;
    if (dt > 34) dt = 34;
    lastT = now;
    var step = dt / 16.67;
    if (!reduce) {
      if (now - lastScroll > 90) smooth *= Math.pow(0.88, step);
      if (Math.abs(smooth) < 0.012) smooth = 0;
      var follow = 1 - Math.pow(0.93, step);
      var parFollow = 1 - Math.pow(narrow ? 0.96 : 0.92, step);
      if (narrow) {
        if (follow > 0.08) follow = 0.08;
        if (parFollow > 0.06) parFollow = 0.06;
      }
      lookX += (aimX - lookX) * follow;
      lookY += (aimY - lookY) * follow;
      parY += (parAim - parY) * parFollow;
      if (Math.abs(smooth) > 0.05) glareAmt += (1 - glareAmt) * (1 - Math.pow(0.55, step));
      else glareAmt *= Math.pow(0.93, step);
      if (glareAmt < 0.02) glareAmt = 0;
      var i, s, depth, wob;
      var ease = 1 - Math.pow(0.925, step);
      for (i = 0; i < shards.length; i++) {
        s = shards[i];
        depth = s.layer === 2 ? 1 : s.layer === 1 ? 0.72 : 0.48;
        wob = Math.sin(now * 0.00045 + s.phase) * 2.4;
        s.rotX += (s.baseX + clamp(smooth * s.ampX * s.dirX * depth, -7, 7) + wob - s.rotX) * ease;
        s.rotY += (s.baseY + clamp(smooth * s.ampY * s.dirY * depth, -7, 7) + wob * 0.65 - s.rotY) * ease;
        s.rotZ += (s.baseZ + clamp(smooth * s.ampZ * s.dirZ * depth, -3, 3) - s.rotZ) * ease;
        if (s.role === "grow" && s.clock.morph) s.clock.morphT += 0.008 * s.clock.morphRate * step;
        s.shadeT += 0.009 * s.shadeRate * step;
      }
      if (sun && !flare.on) {
        var crossed = (sun.prevY - sun.glint) * (sun.rotY - sun.glint) <= 0 && Math.abs(sun.rotY - sun.prevY) > 0.02;
        if (crossed && Math.abs(smooth) > 0.15 && now - flare.done > 1700) {
          flare.on = true;
          flare.t0 = now;
          flare.dur = 360 + rnd(Math.floor(now) % 97) * 300;
        }
      }
      if (sun) sun.prevY = sun.rotY;
      if (flare.on && now - flare.t0 > flare.dur) {
        flare.on = false;
        flare.done = now;
      }
    }
    moveVerts(now);
    syncPivots();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = "#020712";
    ctx.fillRect(0, 0, w, h);
    var tone, ox, oy, quads = 0;
    for (i = 0; i < shards.length; i++) {
        s = shards[i];
        s.hidden = !faceOn(s);
        if (s.hidden) continue;
        place(s);
        tone = toneOf(s);
        var bend = 16 + s.layer * 7;
        ox = clamp(s.rotY * bend, -120, 120);
        oy = clamp(s.rotX * bend, -120, 120);
        drawPoly(s);
        ctx.fillStyle = tone.fill;
        ctx.fill();
        var driftX = reduce ? 0 : (now * 0.034) % w;
        var driftY = reduce ? 0 : (now * 0.016) % h;
        var k, dot, sx, sy;
        for (k = 0; k < starDots.length; k++) {
          dot = starDots[k];
          sx = ((dot.x + driftX + ox) % w + w) % w;
          sy = ((dot.y + driftY + oy) % h + h) % h;
          if (sx < s.minX || sx > s.maxX || sy < s.minY || sy > s.maxY) continue;
          if (!hit(sx, sy, s.view)) continue;
          ctx.globalAlpha = dot.a;
          ctx.fillStyle = "#f4f8ff";
          ctx.beginPath();
          ctx.arc(sx, sy, dot.r + 0.35, 0, 6.2832);
          ctx.fill();
        }
        ctx.globalAlpha = 1;
        drawPoly(s);
        ctx.strokeStyle = tone.edge;
        ctx.lineWidth = 1;
        ctx.lineJoin = "miter";
        ctx.stroke();
        if (s.glare && glareAmt > 0.02) drawGlare(s);
        if (s.sun && flare.on) drawFlare(s, now);
        if (s.view.length === 4) quads++;
    }
    canvas.dataset.quads = String(quads);
    var vig = ctx.createRadialGradient(w * 0.45, h * 0.35, Math.min(w, h) * 0.15, w * 0.5, h * 0.4, Math.max(w, h) * 0.78);
    vig.addColorStop(0, "rgba(2,7,18,0)");
    vig.addColorStop(1, "rgba(2,7,18,0.2)");
    ctx.fillStyle = vig;
    ctx.fillRect(0, 0, w, h);
    canvas.dataset.flare = flare.on ? "1" : "0";
    canvas.dataset.glint = glareAmt.toFixed(2);
    canvas.dataset.par = parY.toFixed(3);
    if (!reduce) requestAnimationFrame(frame);
  }

  if (!reduce) {
    window.addEventListener("scroll", function () {
      var y = window.scrollY;
      var now = performance.now();
      var dt = lastScroll ? now - lastScroll : 16;
      if (dt < 16) dt = 16;
      var glide = narrow ? 0.12 : 0.28;
      smooth += (clamp((y - lastY) / dt / (narrow ? 2.4 : 1.1), -1, 1) - smooth) * glide;
      lastY = y;
      lastScroll = now;
      var span = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
      parAim = 0.5 - clamp(y / span, 0, 1);
    }, { passive: true });
    window.addEventListener("pointermove", function (e) {
      aimX = clamp((e.clientX / Math.max(1, w) - 0.5) * 2, -1, 1);
      aimY = clamp((e.clientY / Math.max(1, h) - 0.5) * 2, -1, 1);
    }, { passive: true });
    window.addEventListener("pointerleave", function () {
      aimX = 0;
      aimY = 0;
    });
  }
  window.addEventListener("resize", function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () {
      layout();
      if (reduce) frame(0);
    }, 150);
  });
  layout();
  if (reduce) frame(0);
  else requestAnimationFrame(frame);
})();
</script>"""


SITE = "https://k-pax.space"
HOME_TITLE = "K-Pax — интернет без рекламы"
HOME_DESC = (
    "K-Pax — подключение для работы в интернете без рекламы. "
    "Безопасное соединение, 14 дней бесплатно без привязки карты, затем 110 ₽ за 30 дней на два устройства."
)
PAY_DESC = (
    "Подписка K-Pax: 110 ₽ за 30 дней, два устройства, одна ссылка. "
    "Оплата по СБП. Первые 14 дней бесплатно, без привязки карты."
)
TERMS_DESC = (
    "Пользовательское соглашение K-Pax: подключение без рекламы, 14 дней бесплатно, "
    "затем 110 ₽ за 30 дней, и условия возврата."
)
PRIVACY_DESC = (
    "Политика конфиденциальности K-Pax: какие сведения передаются при использовании сайта и сервиса."
)


def seo_json_ld() -> str:
    payload = {
        "@context": "https://schema.org",
        "@graph": [
            {
                "@type": "WebSite",
                "name": "K-Pax",
                "url": SITE + "/",
                "inLanguage": "ru",
                "description": HOME_DESC,
            },
            {
                "@type": "Organization",
                "name": "K-Pax",
                "url": SITE + "/",
                "logo": SITE + "/logo.png",
                "email": "support@k-pax.space",
            },
            {
                "@type": "Offer",
                "name": "Подписка K-Pax",
                "url": SITE + "/pay",
                "price": "110",
                "priceCurrency": "RUB",
                "description": "110 ₽ за 30 дней, 2 устройства. Первые 14 дней бесплатно.",
            },
        ],
    }
    return '<script type="application/ld+json">%s</script>' % json.dumps(payload, ensure_ascii=False)


def public_head(title: str, description: str, canonical: str, json_ld: str = "") -> str:
    lines = [
        '<meta name="description" content="%s">' % html.escape(description, quote=True),
        '<meta name="robots" content="index, follow, max-image-preview:large">',
        '<link rel="canonical" href="%s">' % html.escape(canonical, quote=True),
        '<meta property="og:type" content="website">',
        '<meta property="og:site_name" content="K-Pax">',
        '<meta property="og:locale" content="ru_RU">',
        '<meta property="og:title" content="%s">' % html.escape(title, quote=True),
        '<meta property="og:description" content="%s">' % html.escape(description, quote=True),
        '<meta property="og:url" content="%s">' % html.escape(canonical, quote=True),
        '<meta property="og:image" content="%s">' % (SITE + "/logo.png"),
        '<meta name="twitter:card" content="summary">',
        '<meta name="twitter:title" content="%s">' % html.escape(title, quote=True),
        '<meta name="twitter:description" content="%s">' % html.escape(description, quote=True),
    ]
    if json_ld:
        lines.append(json_ld)
    return "\n".join(lines)


def robots_txt() -> bytes:
    return (
        "User-agent: *\n"
        "Allow: /\n"
        "Disallow: /s/\n"
        "Disallow: /admin\n"
        "Disallow: /signup\n"
        "Disallow: /app/\n"
        "Disallow: /app/confirm\n"
        "Disallow: /app/login\n"
        "Disallow: /internal/\n"
        "Disallow: /referral\n"
        "Disallow: /restore-mail\n"
        "Disallow: /promo\n"
        "Disallow: /platega/\n"
        "Disallow: /pay/done\n"
        "Disallow: /pay/fail\n"
        "Disallow: /healthz\n"
        "\n"
        "Sitemap: https://k-pax.space/sitemap.xml\n"
    ).encode()


def sitemap_xml() -> bytes:
    urls = ("/", "/pay", "/faq", "/status", "/terms", "/privacy")
    body = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for path in urls:
        body.append("<url><loc>%s</loc></url>" % (SITE + path))
    body.append("</urlset>")
    return "\n".join(body).encode()


STATUS_DESC = "Статус сервиса K-Pax: работают ли подключения сейчас."


def public_status_page() -> tuple[int, str, bytes]:
    now = time.time()
    with DEVICE_LOCK:
        health = {host: dict(sample) for host, sample in NODE_HEALTH.items()}
    up = 0
    down = 0
    for node in CFG["nodes"]:
        if is_front_node(node):
            continue
        sample = health.get(node["host"])
        if sample is None or now - float(sample["seen"]) > ALERT_AFTER:
            down += 1
        else:
            up += 1
    if down == 0:
        title = "Сервис в порядке"
        text = "Подключения работают."
    elif up == 0:
        title = "Сбой"
        text = "Идёт восстановление. Напишите на support@k-pax.space, если доступ нужен срочно."
    else:
        title = "Частичный сбой"
        text = "Часть узлов недоступна. Если не подключается — подождите или напишите на support@k-pax.space."
    body = """
<section class="support paypage">
<h1>Статус</h1>
<p class="payfigure">%s</p>
<p>%s</p>
<p class="muted">Обновляется автоматически. Страны и адреса серверов здесь не показываем.</p>
%s<p class="buyrow"><a class="restore" href="/">На главную</a></p>
</section>
""" % (
        html.escape(title),
        html.escape(text),
        '<p>О плановых работах и сбоях пишем в канале <a href="%s" rel="noopener">t.me/kpaxvpn</a>.</p>\n' % brand()["channel"]
        if brand().get("channel")
        else "",
    )
    return page(
        "Статус — K-Pax",
        body,
        landing=True,
        buy=False,
        index=True,
        description=STATUS_DESC,
        canonical=SITE + "/status",
        faq_fab=True,
    )


UPDATE_TICKER_TEXT = (
    "Если у вас оборвался трафик — значит мы обновили серверы и стабильность. "
    "Пожалуйста, обновите подписку в приложении: откройте раздел «Подписка» и нажмите кнопку обновления."
)


def update_ticker_html() -> str:
    msg = html.escape(UPDATE_TICKER_TEXT)
    return (
        '<div class="site-ticker" role="region" aria-label="Важное сообщение">'
        '<div class="site-ticker-track">'
        f'<p class="site-ticker-msg">{msg}</p>'
        f'<p class="site-ticker-msg" aria-hidden="true">{msg}</p>'
        "</div></div>"
    )


def page(title: str, body: str, status: int = 200, wide: bool = False, landing: bool = False, home: bool = False, buy: bool = True, index: bool = False, description: str = "", canonical: str = "", json_ld: str = "", faq_fab: bool = False) -> tuple[int, str, bytes]:
    head = (
        public_head(title, description, canonical, json_ld)
        if index and description and canonical
        else '<meta name="robots" content="noindex">'
    )
    document = """<!doctype html>
<html lang="ru"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
{head}
<link rel="icon" href="/logo.png" type="image/png">
<link rel="apple-touch-icon" href="/logo.png">
<style>
:root {{ color-scheme: dark; }}
body {{ margin:0; font:16px/1.6 "Segoe UI", sans-serif; background:#10141c; color:#e8eef7; }}
main {{ position:relative; z-index:1; max-width:32rem; margin:0 auto; padding:1.5rem 1.2rem; }}
main.wide {{ max-width:none; padding:1.25rem clamp(1rem, 2vw, 2.2rem); }}
h1 {{ font-size:1.7rem; margin:0 0 .4rem; letter-spacing:.02em; }}
.site-ticker {{
  position:sticky; top:0; z-index:50; overflow:hidden;
  border-bottom:1px solid #3ddc97;
  background:#0c241c;
  color:#d7fff0;
  box-shadow:0 10px 28px rgba(0,0,0,.28);
}}
.site-ticker-track {{
  display:flex; width:max-content; gap:3.5rem;
  padding:.72rem 0;
  animation:site-ticker 38s linear infinite;
}}
.site-ticker-msg {{
  margin:0; padding:0 1.25rem; white-space:nowrap;
  font-size:.95rem; font-weight:650; letter-spacing:.01em; line-height:1.35;
}}
.site-ticker-msg::before {{
  content:"●"; display:inline-block; margin-right:.65rem; color:#3ddc97;
}}
@keyframes site-ticker {{
  from {{ transform:translateX(0); }}
  to {{ transform:translateX(-50%); }}
}}
@media (prefers-reduced-motion: reduce) {{
  .site-ticker-track {{ animation:none; width:auto; max-width:72rem; margin:0 auto; flex-wrap:wrap; gap:.35rem; }}
  .site-ticker-msg {{ white-space:normal; }}
  .site-ticker-msg[aria-hidden="true"] {{ display:none; }}
}}
.brand {{ margin:0 0 1rem; display:flex; align-items:center; gap:.85rem; }}
.brand a.mark {{ display:inline-flex; align-items:center; gap:.75rem; color:#f4f7fb; text-decoration:none; font-weight:720; letter-spacing:.04em; }}
.brand img {{ width:132px; height:132px; border-radius:28px; display:block; }}
main.landing .brand {{ justify-content:space-between; }}
main.landing .brand img {{ width:64px; height:64px; border-radius:16px; }}
.brand a.home {{ color:#93a0b5; text-decoration:none; font-weight:650; }}
.brand a.home:hover {{ color:#8ee0c0; }}
.toplinks {{ display:flex; gap:1rem; align-items:center; }}
a.faqfab {{
  display:inline-flex; align-items:center; justify-content:center;
  min-width:3rem; height:2.2rem; padding:0 .85rem; margin:0;
  border-radius:10px; text-decoration:none; font-weight:650;
  color:#d7fff0; background:transparent; border:1px solid #3d6a58;
  box-shadow:none;
}}
a.faqfab:hover {{ border-color:#3ddc97; color:#8ee0c0; }}
@media (max-width: 720px) {{
  .brand {{ flex-wrap:wrap; row-gap:.4rem; }}
  .brand img, main.landing .brand img {{ width:48px; height:48px; border-radius:12px; }}
  .brand a.mark, .toplinks a {{ white-space:nowrap; }}
  .toplinks {{ margin-left:auto; flex-wrap:nowrap; gap:.85rem; }}
  a.faqfab {{ min-width:2.6rem; height:2rem; padding:0 .7rem; font-size:.92rem; }}
}}
main.wide .brand {{ margin-bottom:.35rem; }}
main.wide .brand img {{ width:56px; height:56px; border-radius:14px; }}
h2 {{ font-size:1.05rem; margin:0 0 .45rem; line-height:1.35; }}
.lead {{ color:#a9b6c9; margin:0; line-height:1.45; }}
main.landing .hero h1.lead {{ margin:0; }}
.legal {{ margin:.75rem 0 0; color:#93a0b5; font-size:.86rem; line-height:1.6; }}
.legal a {{ color:#8ee0c0; }}
.docs p {{ margin:0 0 .85rem; color:#d5deea; line-height:1.65; }}
.docs p:last-child {{ margin-bottom:0; }}
.docs h2 {{ margin:1.15rem 0 .45rem; font-size:1.05rem; line-height:1.35; }}
.docs ol {{ margin:.35rem 0 .85rem; padding-left:1.2rem; }}
.docs li {{ margin:.4rem 0; color:#d5deea; line-height:1.55; }}
.docbtns {{ display:flex; flex-wrap:wrap; gap:.5rem; margin:.85rem 0 0; }}
.docbtns a {{ display:inline-block; text-decoration:none; border:1px solid #3d6a58; color:#d7fff0; background:#15241e; border-radius:10px; padding:.55rem .85rem; font-weight:650; }}
body:has(main.landing) {{ min-height:100vh; background:#070b12; }}
.sky {{
  position:fixed; inset:0; z-index:0; overflow:hidden; pointer-events:none;
  background:#020712;
}}
.sky canvas {{ display:block; width:100%; height:100%; }}
main.landing .block {{ margin-top:2.75rem; }}
main.landing .about {{ margin-top:0; }}
main.landing .about .lead {{ font-size:clamp(1.7rem, 4vw, 2.7rem); line-height:1.12; color:#f3f7fb; font-weight:700; letter-spacing:-.03em; max-width:none; }}
main.landing .about h1.lead {{ margin:0; }}
main.landing .section {{ margin:0 0 1rem; font-size:1.35rem; }}
main.landing .steps form.signup {{
  background:transparent; border:0; padding:0; margin:1rem 0 0; box-shadow:none;
  display:flex; flex-direction:column; gap:.85rem; position:relative;
}}
main.landing .steps form.signup label {{ margin:0; }}
main.landing .steps form.signup input {{ margin:0; display:block; }}
main.landing .steps form.signup p {{ margin:0; }}
main.landing .steps form.signup button {{ width:100%; margin:0; flex:0 0 auto; }}
main.landing .steps form.signup .legal {{ margin:0; }}
main.landing .steps .apps {{ margin-top:1rem; }}
main.landing .steps p + p {{ margin-top:.75rem; }}
main.landing .offergrid {{ display:grid; gap:1rem; }}
main.landing .offergrid .card {{ padding:1.25rem 1.3rem 1.35rem; }}
main.landing .offergrid .card h2 {{ margin:0 0 .45rem; }}
main.landing .offergrid .payfigure {{ margin:.15rem 0 .55rem; }}
main.landing .appopen {{ display:flex; flex-wrap:wrap; gap:.65rem; margin:.85rem 0 0; }}
main.landing .appopen a.restore {{ margin-top:0; }}
main.landing .faq {{ margin:.85rem 0 1.25rem; }}
main.landing .faq details {{
  background:rgba(22,29,41,.92);
  border:1px solid #2c3648;
  border-radius:12px;
  padding:.85rem 1rem;
  margin:0 0 .55rem;
}}
main.landing .faq summary {{
  cursor:pointer; font-weight:650; color:#e8eef7; list-style:none;
}}
main.landing .faq summary::-webkit-details-marker {{ display:none; }}
main.landing .faq details[open] summary {{ color:#8ee0c0; margin-bottom:.45rem; }}
main.landing .faq details p {{ margin:0; color:#c5d0e0; line-height:1.55; }}
main.landing .faq details p a {{ color:#8ee0c0; }}
main.landing .faqpage h2 {{ margin-top:1.35rem; }}
main.landing .promostrip {{
  margin-top:2.75rem;
  background:rgba(22,29,41,.92);
  border:1px solid #2c3648;
  border-radius:14px;
  padding:.95rem 1.25rem 1.1rem;
  box-shadow:0 12px 28px rgba(0,0,0,.14);
}}
main.landing .promostrip h2 {{ margin:0 0 .75rem; font-size:1.05rem; line-height:1.4; }}
main.landing .promostrip form {{ background:transparent; border:0; padding:0; margin:0; box-shadow:none; }}
main.landing .promostrip .promorow {{ display:grid; gap:.85rem 1.2rem; }}
main.landing .promostrip label {{ margin-bottom:.32rem; font-size:.88rem; line-height:1.4; }}
main.landing .promostrip input {{ padding:.68rem .8rem; line-height:1.45; }}
main.landing .promostrip button {{ margin-top:0; width:100%; line-height:1.35; }}
main.landing .promostrip .ok, main.landing .promostrip .err {{ margin:0 0 .75rem; line-height:1.5; }}
@media (min-width: 760px) {{
  main.landing .promostrip .promorow {{ grid-template-columns:1.25fr 1fr auto; align-items:end; column-gap:1.35rem; }}
  main.landing .promostrip button {{ width:auto; min-width:8.5rem; padding:.68rem 1.15rem; }}
}}
main.landing button, main.landing a.restore {{
  position:relative; overflow:hidden;
  transition:transform .18s ease, filter .18s ease, box-shadow .18s ease;
}}
main.landing button:hover, main.landing a.restore:hover {{
  filter:brightness(1.06);
  box-shadow:0 12px 28px rgba(61,220,151,.28);
}}
main.landing button:active, main.landing a.restore:active {{ transform:scale(.98); }}
main.landing button::after, main.landing a.restore::after {{
  content:""; position:absolute; top:0; bottom:0; left:0; width:42%;
  background:linear-gradient(90deg, transparent, rgba(255,255,255,.42), transparent);
  transform:translateX(-180%); animation:shine 5.6s ease-in-out infinite; pointer-events:none;
}}
@keyframes shine {{
  0%, 64% {{ transform:translateX(-180%); }}
  100% {{ transform:translateX(320%); }}
}}
main.landing .apps a {{ transition:border-color .18s ease, color .18s ease, background .18s ease; }}
main.landing .apps a:hover {{ background:#182232; }}
main.landing .steps > li {{ transition:border-color .2s ease; }}
main.landing .steps > li:hover {{ border-color:#3d6a58; }}
main.landing .foot {{ margin:2rem 0 0; color:#7d8ba0; font-size:.88rem; }}
@media (prefers-reduced-motion: reduce) {{
  main.landing button::after, main.landing a.restore::after {{ animation:none; }}
  main.landing button, main.landing a.restore, main.landing .apps a, main.landing .steps > li {{ transition:none; }}
}}
main.landing {{ max-width:68rem; padding:clamp(1.5rem, 4vw, 2.4rem) clamp(1rem, 3vw, 2rem); }}
main.landing > h1 {{ font-size:clamp(2.4rem, 6vw, 3.6rem); letter-spacing:-.035em; line-height:1.15; margin:0 0 .7rem; }}
main.landing .lead {{ color:#d7e0ec; font-size:clamp(1.05rem, 2.2vw, 1.3rem); max-width:38rem; margin:0; line-height:1.2; }}
main.landing .sub {{ color:#93a0b5; max-width:36rem; margin:.75rem 0 0; line-height:1.6; }}
.facts {{ display:flex; flex-wrap:wrap; gap:.45rem; margin:1rem 0 0; }}
.facts span {{ border:1px solid #314056; background:rgba(18,24,34,.72); color:#d5deea; border-radius:999px; padding:.38rem .75rem; font-size:.9rem; }}
main.landing .steps {{ list-style:none; margin:0; padding:0; display:grid; grid-template-columns:1fr; gap:1rem; }}
main.landing .steps > li {{
  min-width:0;
  background:rgba(22,29,41,.92);
  border:1px solid #2c3648;
  border-radius:18px;
  padding:1.25rem 1.25rem 1.35rem;
  box-shadow:0 16px 40px rgba(0,0,0,.18);
}}
main.landing .num {{
  width:1.45rem; height:1.45rem; margin:0 0 .45rem;
  border-radius:50%; background:#12382c; color:#8ee0c0;
  display:flex; align-items:center; justify-content:center; font-weight:700; font-size:.82rem;
}}
main.landing .steps h2 {{ font-size:1rem; margin:0 0 .4rem; line-height:1.3; }}
main.landing .steps p {{ margin:0; line-height:1.55; }}
main.landing .apps {{ display:flex; flex-wrap:wrap; gap:.5rem; margin:.2rem 0 .35rem; }}
main.landing .apps a {{
  flex:1 1 9rem; text-align:center; text-decoration:none;
  background:#121820; border:1px solid #3a465c; border-radius:12px;
  padding:.5rem .75rem; font-weight:500; color:#e8eef7; white-space:nowrap;
}}
main.landing .apps a:hover {{ border-color:#3ddc97; color:#8ee0c0; }}
main.landing input:focus {{ outline:2px solid #3ddc97; border-color:transparent; }}
.support {{
  margin-top:1.1rem;
  background:rgba(22,29,41,.92);
  border:1px solid #2c3648;
  border-radius:18px;
  padding:1.25rem 1.3rem 1.35rem;
}}
main.landing .block.support {{ margin-top:2.75rem; }}
.support h1, .support h2 {{ font-size:1.12rem; margin:1rem 0 .45rem; line-height:1.3; }}
.support h1:first-child, .support h2:first-child {{ margin-top:0; }}
.support p {{ margin:0 0 .75rem; line-height:1.6; }}
.support p:last-child {{ margin-bottom:0; }}
.support .apps + h2 {{ margin:1rem 0 .45rem; }}
.support .apps {{ margin-top:.65rem; }}
.support .apps a {{ flex:1 1 14rem; }}
.support .applist {{ list-style:none; margin:.95rem 0 0; padding:0; }}
.support .applist li {{ margin:.45rem 0; }}
.support .applist b {{ display:block; color:#8ee0c0; font-size:.78rem; letter-spacing:.06em; text-transform:uppercase; }}
.support ul {{ margin:.35rem 0 .75rem; padding-left:1.15rem; }}
.support li {{ margin:.35rem 0; line-height:1.55; }}
.payfigure {{ margin:0 0 .75rem; font-size:1.55rem; font-weight:720; letter-spacing:-.02em; line-height:1.2; }}
main.landing .paypage {{ max-width:56rem; margin-left:auto; margin-right:auto; }}
main.landing .paypage form.signup {{
  background:transparent; border:0; padding:0; margin:1rem 0 0; box-shadow:none; max-width:32rem;
  display:flex; flex-direction:column; gap:.85rem; position:relative;
}}
main.landing .paypage form.signup label {{ margin:0; }}
main.landing .paypage form.signup input {{ margin:0; display:block; }}
main.landing .paypage form.signup p {{ margin:0; }}
main.landing .paypage form.signup button {{ width:100%; margin:0; flex:0 0 auto; }}
@media (min-width: 900px) {{
  main.landing .steps {{ grid-template-columns:repeat(3, minmax(0, 1fr)); gap:1rem; align-items:stretch; }}
  main.landing .offergrid {{ grid-template-columns:1fr 1fr; gap:1rem; }}
}}
#q {{ margin:.9rem 0 1rem; }}
.healthrow {{ display:grid; grid-template-columns:repeat(auto-fit, minmax(14rem, 1fr)); gap:.7rem; margin:0 0 .9rem; }}
.health {{ background:#1a2130; border:1px solid #2c3648; border-radius:14px; padding:1rem; }}
.health p {{ margin:.25rem 0; line-height:1.45; }}
.health p:first-child {{ margin-top:0; }}
.health p:last-child {{ margin-bottom:0; }}
.health .figure {{ font-size:1.45rem; font-weight:720; letter-spacing:-.02em; }}
.tablewrap {{ border:1px solid #2c3648; border-radius:14px; background:#1a2130; overflow-x:auto; }}
.tablewrap.paylog {{ max-height: calc(21 * (1.6em + 1.4rem + 1px)); overflow: auto; }}
table {{ width:100%; border-collapse:collapse; table-layout:fixed; }}
col.num {{ width:8rem; }}
col.who {{ width:18%; }}
col.state {{ width:7rem; }}
col.until {{ width:12rem; }}
col.extend {{ width:15rem; }}
th, td {{ text-align:left; padding:.7rem .75rem; border-bottom:1px solid #2c3648; vertical-align:middle; }}
th {{ color:#93a0b5; font-size:.82rem; font-weight:650; }}
tr:last-child td {{ border-bottom:0; }}
.tablewrap.people td:first-child, .tablewrap.people td:nth-child(4), .tablewrap.people td:nth-child(5) {{ white-space:nowrap; }}
.tablewrap.people td:nth-child(3) {{ white-space:normal; }}
.tablewrap.people td:nth-child(6) {{ white-space:nowrap; overflow:visible; }}
.tablewrap.people td:nth-child(7), .tablewrap.people td:nth-child(8) {{ overflow:hidden; }}
.os-marks {{
  display:inline-block; font-size:.78rem; font-weight:700; letter-spacing:.04em;
  color:#8ee0c0; white-space:nowrap; vertical-align:middle;
}}
.tablewrap.people td.os-cell {{ max-width:7rem; white-space:nowrap; }}
.tablewrap .linkline {{ margin-top:0; width:100%; min-width:0; }}
.tablewrap p.link {{ display:block; max-width:none; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; word-break:normal; }}
.tablewrap button {{ margin-top:0; }}
.tablewrap .row {{ margin-top:0; flex-wrap:nowrap; }}
.toolbar {{ display:flex; flex-wrap:wrap; align-items:flex-start; justify-content:space-between; gap:.75rem 1.25rem; margin:0 0 1rem; }}
.toolbar .lead, .toolbar h1 {{ margin:0; flex:1 1 16rem; }}
.toolbar > a {{ flex:0 0 auto; margin:0; color:#93a0b5; text-decoration:none; font-weight:650; white-space:nowrap; padding:.2rem 0; }}
.toolbar > a:hover {{ color:#8ee0c0; }}
@media (max-width: 860px) {{
  .tablewrap {{ overflow-x:auto; }}
  table {{ min-width:48rem; }}
  .tablewrap.paylog table {{ min-width:0; }}
}}
.hp {{ position:absolute; left:-9999px; width:1px; height:1px; overflow:hidden; opacity:0; pointer-events:none; }}
form, .card {{ background:#1a2130; border:1px solid #2c3648; border-radius:14px; padding:1rem; }}
.card p {{ margin:0 0 .75rem; line-height:1.6; }}
.card p:last-child {{ margin-bottom:0; }}
.qrwrap {{ width:fit-content; margin:.85rem 0 .15rem; background:#fff; border-radius:16px; padding:10px; }}
.qrwrap svg {{ display:block; width:min(220px, 68vw); height:auto; }}
label {{ display:block; margin-bottom:.35rem; color:#c5d0e0; }}
input, select {{ width:100%; box-sizing:border-box; padding:.75rem .8rem; border-radius:10px; border:1px solid #3a465c; background:#0e131c; color:#fff; font:inherit; }}
button, .copy, a.restore {{ margin-top:.8rem; background:#3ddc97; color:#062216; border:0; border-radius:10px; padding:.75rem 1rem; font:inherit; font-weight:650; cursor:pointer; }}
a.restore {{ display:inline-block; text-decoration:none; }}
.buyrow {{ display:flex; flex-wrap:wrap; gap:.65rem; align-items:center; margin:.85rem 0 0; }}
.buyrow a.restore,
.buyrow button.ghost {{ margin-top:0; flex:0 0 auto; width:auto; }}
.buyrow .or {{ color:#e8eef7; font-weight:650; flex:0 0 auto; }}
button.ghost {{ background:transparent; color:#d7fff0; border:1px solid #3d6a58; box-shadow:none; }}
button.ghost::after, .modal .x::after {{ display:none; }}
button.ghost:hover {{ box-shadow:none; filter:none; border-color:#3ddc97; color:#8ee0c0; transform:none; }}
button.danger {{ background:#8b2e3b; color:#ffe8ec; }}
button.danger:hover {{ filter:brightness(1.06); }}
.delete-box {{ margin:1.4rem 0 0; padding:1rem 0 0; border-top:1px solid #243044; }}
.delete-box > p {{ margin:0 0 .75rem; color:#93a0b5; }}
.modal {{ position:fixed; inset:0; z-index:30; display:flex; align-items:center; justify-content:center; padding:1.2rem; background:rgba(2,7,18,.72); }}
.modal[hidden], .modal [hidden] {{ display:none !important; }}
.modal .sheet {{ width:min(26rem, 100%); position:relative; background:#161d29; border:1px solid #2c3648; border-radius:18px; padding:1.2rem 1.15rem 1.25rem; box-shadow:0 24px 60px rgba(0,0,0,.45); }}
.modal h2 {{ margin:0 2rem .5rem 0; font-size:1.2rem; }}
.modal p {{ margin:0 0 .75rem; line-height:1.55; }}
.modal .warn {{ color:#ffc1cc; font-weight:700; margin:0 0 .55rem; }}
.modal .x {{ position:absolute; top:.45rem; right:.45rem; margin:0; padding:.3rem .55rem; background:transparent; color:#93a0b5; border:0; font-size:1.35rem; line-height:1; box-shadow:none; }}
.modal form {{
  background:transparent; border:0; padding:0; margin:.2rem 0 0; box-shadow:none;
  display:flex; flex-direction:column; gap:.75rem; position:relative;
}}
.modal form label {{ margin:0; }}
.modal form input {{ margin:0; }}
.modal form button {{ margin:0; width:100%; }}
.modal .actions {{ display:flex; gap:.65rem; flex-wrap:wrap; margin-top:.35rem; }}
.modal .actions button {{ margin:0; flex:1 1 8rem; width:auto; }}
.modal code {{ display:block; margin-top:.35rem; }}
form.extend {{ background:transparent; border:0; padding:0; margin:0 0 1rem; }}
form.inline-del {{
  display:inline; margin:0; padding:0; background:transparent; border:0; border-radius:0; box-shadow:none;
}}
form.inline-del button {{
  margin:0; padding:.35rem .7rem; font-size:.82rem; line-height:1.2; white-space:nowrap; vertical-align:middle;
}}
.tablewrap.adminlist table {{ width:100%; table-layout:fixed; border-collapse:collapse; }}
.tablewrap.adminlist th, .tablewrap.adminlist td {{
  white-space:nowrap; vertical-align:middle; padding:.55rem .65rem;
  overflow:hidden; text-overflow:ellipsis;
}}
.tablewrap.adminlist.promos th:nth-child(1), .tablewrap.adminlist.promos td:nth-child(1) {{ width:11%; }}
.tablewrap.adminlist.promos th:nth-child(2), .tablewrap.adminlist.promos td:nth-child(2) {{ width:8%; }}
.tablewrap.adminlist.promos th:nth-child(3), .tablewrap.adminlist.promos td:nth-child(3) {{ width:9%; }}
.tablewrap.adminlist.promos th:nth-child(4), .tablewrap.adminlist.promos td:nth-child(4) {{ width:11%; }}
.tablewrap.adminlist.promos th:nth-child(5), .tablewrap.adminlist.promos td:nth-child(5) {{ width:8%; }}
.tablewrap.adminlist.promos th:nth-child(6), .tablewrap.adminlist.promos td:nth-child(6) {{ width:18%; }}
.tablewrap.adminlist.promos th:nth-child(7), .tablewrap.adminlist.promos td:nth-child(7) {{ width:22%; }}
.tablewrap.adminlist.promos th:nth-child(8), .tablewrap.adminlist.promos td:nth-child(8) {{ width:13%; }}
.tablewrap.adminlist.partners th:nth-child(1), .tablewrap.adminlist.partners td:nth-child(1) {{ width:20%; }}
.tablewrap.adminlist.partners th:nth-child(2), .tablewrap.adminlist.partners td:nth-child(2) {{ width:12%; }}
.tablewrap.adminlist.partners th:nth-child(3), .tablewrap.adminlist.partners td:nth-child(3) {{ width:14%; }}
.tablewrap.adminlist.partners th:nth-child(4), .tablewrap.adminlist.partners td:nth-child(4) {{ width:38%; }}
.tablewrap.adminlist.partners th:nth-child(5), .tablewrap.adminlist.partners td:nth-child(5) {{ width:16%; }}
.tablewrap.adminlist th:last-child, .tablewrap.adminlist td:last-child {{
  text-align:right; overflow:visible; text-overflow:clip;
}}
.tablewrap.adminlist td[colspan] {{ text-align:left; white-space:normal; overflow:visible; color:#93a0b5; }}
.tablewrap.adminlist a.cell-link {{
  color:#8ee0c0; text-decoration:none; font-family:ui-monospace, monospace; font-size:.86rem;
}}
.tablewrap.adminlist a.cell-link:hover {{ text-decoration:underline; }}
.tablewrap.adminlist tr.error td {{
  background:rgba(255,93,122,.10);
}}
.tablewrap.adminlist tr.error td:first-child {{
  box-shadow:inset 3px 0 0 #ff5d7a;
}}
.tablewrap.adminlist td.desc {{
  white-space:normal; overflow:visible; text-overflow:clip; color:#d7dee9; font-size:.86rem;
}}
.tablewrap.adminlist td.summary a {{
  color:#d7dee9; text-decoration:none;
}}
.tablewrap.adminlist td.summary a:hover {{ text-decoration:underline; color:#8ee0c0; }}
.badge-sev, .badge-autotest {{
  display:inline-block; padding:.15rem .45rem; border-radius:999px; font-size:.75rem; font-weight:650;
}}
.badge-sev.error {{ background:#3a1d24; color:#ffc1cc; }}
.badge-sev.info {{ background:#1c2433; color:#93a0b5; }}
.badge-autotest.ok {{ background:#143528; color:#b6f3d6; }}
.badge-autotest.fail {{ background:#3a1d24; color:#ffc1cc; }}
.badge-autotest.pending {{ background:#2a2414; color:#ffd89a; }}
.badge-autotest.skip {{ background:#1c2433; color:#93a0b5; }}
.incident-summary {{ margin:0 0 1rem; }}
.incident-summary .lead {{ margin-bottom:.55rem; }}
.event-detail .kv {{
  display:grid; grid-template-columns:9.5rem minmax(0, 1fr); gap:.35rem .75rem;
  margin:0 0 1rem; padding:1rem; background:#1a2130; border:1px solid #2c3648; border-radius:14px;
}}
.event-detail .kv dt {{ color:#93a0b5; font-size:.82rem; font-weight:650; }}
.event-detail .kv dd {{ margin:0; min-width:0; overflow-wrap:anywhere; }}
.event-detail .long {{
  margin:0 0 1rem; padding:1rem; background:#1a2130; border:1px solid #2c3648; border-radius:14px;
  white-space:pre-wrap; overflow-wrap:anywhere; font-family:ui-monospace, monospace; font-size:.86rem; line-height:1.45;
}}
.event-detail h2 {{ margin:1.1rem 0 .55rem; font-size:1rem; }}
.tablewrap.adminlist.events th:nth-child(1), .tablewrap.adminlist.events td:nth-child(1) {{ width:11%; }}
.tablewrap.adminlist.events th:nth-child(2), .tablewrap.adminlist.events td:nth-child(2) {{ width:9%; }}
.tablewrap.adminlist.events th:nth-child(3), .tablewrap.adminlist.events td:nth-child(3) {{ width:6%; }}
.tablewrap.adminlist.events th:nth-child(4), .tablewrap.adminlist.events td:nth-child(4) {{ width:5%; }}
.tablewrap.adminlist.events th:nth-child(5), .tablewrap.adminlist.events td:nth-child(5) {{ width:9%; }}
.tablewrap.adminlist.events th:nth-child(6), .tablewrap.adminlist.events td:nth-child(6) {{ width:12%; }}
.tablewrap.adminlist.events th:nth-child(7), .tablewrap.adminlist.events td:nth-child(7) {{ width:10%; }}
.tablewrap.adminlist.events th:nth-child(8), .tablewrap.adminlist.events td:nth-child(8) {{ width:7%; }}
.tablewrap.adminlist.events th:nth-child(9), .tablewrap.adminlist.events td:nth-child(9) {{ width:6%; }}
.tablewrap.adminlist.events th:nth-child(10), .tablewrap.adminlist.events td:nth-child(10) {{ width:16%; }}
.tablewrap.adminlist.events th:nth-child(11), .tablewrap.adminlist.events td:nth-child(11) {{ width:5%; }}
.tablewrap.adminlist.events th:nth-child(12), .tablewrap.adminlist.events td:nth-child(12) {{ width:9%; }}
form.extend.createbar {{ margin:0 0 .9rem; }}
form.extend.createbar .row {{ margin:0; gap:.6rem; flex-wrap:nowrap; align-items:stretch; }}
form.extend.createbar .row input,
form.extend.createbar .row select,
form.extend.createbar .row button {{ height:2.6rem; box-sizing:border-box; }}
form.extend.eventfilters .row {{
  margin:0; gap:.45rem .55rem; flex-wrap:wrap; align-items:center;
}}
form.extend.eventfilters .row > input[type="search"] {{
  flex:1 1 11rem; min-width:10rem; max-width:16rem; height:2.5rem; margin:0;
}}
form.extend.eventfilters .row label {{
  display:inline-flex; align-items:center; gap:.35rem; margin:0; color:#93a0b5;
  font-size:.78rem; font-weight:650; white-space:nowrap; flex:0 1 auto;
}}
form.extend.eventfilters .row label select {{
  height:2.5rem; margin:0; min-width:5.5rem; max-width:11rem; width:auto; flex:0 1 auto;
}}
form.extend.eventfilters .row button {{
  height:2.5rem; margin:0; padding:.45rem .9rem; flex:0 0 auto;
}}
.row {{ display:flex; gap:.55rem; align-items:center; margin:.15rem 0 .9rem; flex-wrap:wrap; }}
.row input, .row select {{ width:auto; min-width:7rem; flex:1 1 8rem; max-width:16rem; margin:0; padding:.55rem .7rem; }}
.row input[name="code"], .row input[type="search"], .row #q {{ min-width:12rem; flex:1 1 14rem; max-width:28rem; }}
.row input[name="days"], .row input[name="max_uses"] {{ flex:0 0 6.5rem; min-width:5.5rem; max-width:7rem; }}
.row select[name="brand"] {{ flex:0 0 8rem; min-width:7rem; max-width:9rem; }}
.row button {{ margin:0; padding:.55rem .9rem; flex:0 0 auto; }}
@media (max-width: 900px) {{
  .tablewrap.adminlist {{ overflow-x:auto; }}
  .tablewrap.adminlist table {{ min-width:48rem; }}
  form.extend.createbar .row {{ flex-wrap:wrap; align-items:center; }}
  form.extend.createbar .row input,
  form.extend.createbar .row select,
  form.extend.createbar .row button {{ height:auto; }}
  form.extend.eventfilters .row {{ flex-wrap:wrap; }}
  form.extend.eventfilters .row > input[type="search"],
  form.extend.eventfilters .row label select,
  form.extend.eventfilters .row button {{ height:auto; }}
}}
.linkline {{ display:flex; gap:.5rem; align-items:center; margin-top:.45rem; }}
.linkline .link {{ flex:1; min-width:0; margin:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }}
.linkline button {{ margin:0; padding:.45rem .7rem; white-space:nowrap; }}
.err {{ background:#3a1d24; color:#ffc1cc; padding:.7rem .8rem; border-radius:10px; }}
.ok {{ background:#143528; color:#b6f3d6; padding:.7rem .8rem; border-radius:10px; }}
a {{ color:#8ee0c0; }}
code {{ font-family:ui-monospace, monospace; font-size:.9rem; }}
.link {{ font-family:ui-monospace, monospace; font-size:.9rem; }}
.muted {{ color:#93a0b5; font-size:.92rem; line-height:1.55; }}
.adminnav {{ display:flex; gap:.35rem .9rem; flex-wrap:wrap; margin:0 0 .9rem; }}
.adminnav a {{ color:#93a0b5; font-weight:680; text-decoration:none; }}
.adminnav a.on {{ color:#8ee0c0; }}
.badge {{ display:inline-block; margin-left:.4rem; padding:.05rem .45rem; border-radius:999px; background:#3a2a14; color:#ffd6a3; font-size:.75rem; font-weight:700; vertical-align:middle; }}
.tablewrap.people table {{ table-layout:auto; min-width:82rem; }}
.tablewrap.people th a {{ color:#93a0b5; text-decoration:none; }}
.tablewrap.people th a:hover {{ color:#e8eef7; }}
.pager {{ display:flex; gap:.35rem; flex-wrap:wrap; margin:1rem 0 0; }}
.pager a, .pager span {{ display:inline-block; min-width:2.1rem; text-align:center; padding:.35rem .5rem; border-radius:8px; border:1px solid #2c3648; background:#1a2130; text-decoration:none; }}
.pager span {{ color:#8ee0c0; border-color:#3d6a58; }}
.statline {{ margin:.2rem 0 .9rem; }}
ol {{ padding-left:1.15rem; }}
</style>{extra_head}</head><body>{ticker}{sky}<main class="{klass}">
<p class="brand"><a class="mark" href="/" aria-label="На главную"><img src="/logo.png" alt="K-Pax" width="132" height="132"><span>K-Pax</span></a>{nav}</p>
{body}
</main>{script}</body></html>""".format(
        title=html.escape(title),
        head=head,
        klass=(
            "wide xp-admin" if wide and is_xplm()
            else "wide kp-admin" if wide
            else "landing home" if home
            else "landing" if landing
            else ""
        ),
        nav=(
            ('<span class="toplinks">' + (FAQ_FAB if faq_fab else "") + "</span>")
            if home
            else (
                '<span class="toplinks">'
                + (FAQ_FAB if faq_fab else "")
                + '<a class="home" href="/pay">Купить подписку</a><a class="home" href="/">На главную</a></span>'
                if buy
                else '<span class="toplinks">'
                + (FAQ_FAB if faq_fab else "")
                + '<a class="home" href="/">На главную</a></span>'
            )
        ),
        ticker="" if wide or is_xplm() else update_ticker_html(),
        sky=(
            '<div class="sky" aria-hidden="true"><canvas id="kpax-space"></canvas></div>'
        ) if landing and not is_xplm() else "",
        script=KALEID_SCRIPT if landing and not is_xplm() else "",
        extra_head=XPLM_HEAD if is_xplm() else KPAX_HEAD,
        body=body,
    )
    if is_xplm():
        # Replace only the XPLM presentation shell; K-Pax and form handlers stay intact.
        document = re.sub(
            r'<p class="brand">.*?</p>',
            lambda _: xplm_templates.header(home=home, wide=wide),
            document, count=1, flags=re.S,
        )
    return status, "text/html; charset=utf-8", document.encode()


KPAX_ASSETS = "20261103m"
KPAX_HEAD = (
    '<link rel="preload" href="/fonts/manrope-cyrillic-700-normal.woff2" as="font" type="font/woff2" crossorigin>'
    '<link rel="preload" href="/fonts/manrope-latin-700-normal.woff2" as="font" type="font/woff2" crossorigin>'
    '<link rel="preload" href="/fonts/manrope-cyrillic-400-normal.woff2" as="font" type="font/woff2" crossorigin>'
    '<link rel="preload" href="/fonts/manrope-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin>'
    '<link rel="stylesheet" href="/assets/kpax.css?v=%s">' % KPAX_ASSETS
)

XPLM_ASSETS = "20261106-neon6"
XPLM_HEAD = (
    '<link rel="preload" href="/fonts/manrope-cyrillic-700-normal.woff2" as="font" type="font/woff2" crossorigin>'
    '<link rel="preload" href="/fonts/manrope-latin-700-normal.woff2" as="font" type="font/woff2" crossorigin>'
    '<link rel="preload" href="/fonts/manrope-cyrillic-400-normal.woff2" as="font" type="font/woff2" crossorigin>'
    '<link rel="preload" href="/fonts/manrope-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin>'
    '<link rel="icon" href="/assets/xplm-mark.svg?v=%s" type="image/svg+xml">'
    '<link rel="stylesheet" href="/assets/xplm.css?v=%s">' % (XPLM_ASSETS, XPLM_ASSETS)
)

def _load_xplm_logo() -> bytes:
    here = os.path.dirname(os.path.abspath(__file__))
    for name in ("logo.svg", os.path.join("assets", "logo.svg"), os.path.join("x-plm", "logo.svg")):
        path = os.path.join(here, name)
        if os.path.isfile(path):
            with open(path, "rb") as fh:
                return fh.read()
    return (
        b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" role="img" aria-label="X-Plm">'
        b'<path fill="none" stroke="#1A1A1A" stroke-width="10" stroke-linejoin="miter" '
        b'd="M24 28L64 64L24 100M104 28L64 64L104 100"/></svg>'
    )


XPLM_LOGO_SVG = _load_xplm_logo()

XPLM_WINDOWS_APP = (
    '<a href="%s">X-Plm для Windows</a>' % XPLM_WINDOWS_APP_URL
)

XPLM_TEXT = (
    (" или откройте бота @KPax_Space_bot с этого Telegram", ""),
    (" или через бота @KPax_Space_bot с того же Telegram", ""),
    (" или через бота с этого Telegram", ""),
    (" или бот с того же Telegram", ""),
    (" или в Telegram-бот @KPax_Space_bot", ""),
    (" Telegram-бот: @KPax_Space_bot, https://t.me/KPax_Space_bot.", ""),
    (" или сообщением боту @KPax_Space_bot с того же Telegram", ""),
    (" Бот: https://t.me/KPax_Space_bot.", ""),
    ("откройте бота @KPax_Space_bot с этого Telegram или напишите", "напишите"),
    ('<a href="https://t.me/KPax_Space_bot">@KPax_Space_bot</a>', ""),
    ('<a href="https://t.me/k_pax_space">Менеджер @k_pax_space</a>', ""),
    (
        "Ссылку покажем после подтверждения: код на почту или вход в бота. Если Telegram без VPN не открывается — берите почту.",
        "Ссылку покажем после подтверждения: пришлём код на эту почту.",
    ),
    ("Ссылка выдаётся после подтверждения почты или Telegram.", "Ссылка выдаётся после подтверждения почты."),
    ("Почта или Telegram друга", "Почта друга"),
    ("почту или Telegram друга", "почту друга"),
    ("Почта или Telegram счёта", "Почта счёта"),
    ("почту или Telegram счёта", "почту счёта"),
    ("Почта или Telegram", "Почта"),
    ("почту или Telegram", "почту"),
    ("почту или ник Telegram", "почту"),
    ("name@mail.ru или @username", "name@mail.ru"),
    ("Поиск по почте или нику", "Поиск по почте или номеру"),
    ("Эта почта или ник уже используются", "Эта почта уже используется"),
    ("Если почта или ник уже есть", "Если почта уже есть"),
    ("Этой почты или ника ещё нет", "Этой почты ещё нет"),
    ("Оплата на сайте /pay или в боте.", "Оплата на сайте /pay."),
    ("\nИли в боте: Оплатить", ""),
    (
        "Windows и Android — приложение K-Pax: почта и код из письма.",
        "Windows и Android — приложение X-Plm: почта и код из письма.",
    ),
    (
        "iPhone пока — INCY или Happ; своё приложение для iPhone скоро.",
        "iPhone пока — INCY или Happ; своё приложение для iPhone скоро.",
    ),
    (
        "Windows и Android — официальное приложение K-Pax.",
        "Windows и Android — официальное приложение X-Plm.",
    ),
    ("Компьютер — K-Pax, Happ или v2rayN.", "Компьютер — X-Plm, Happ или v2rayN."),
    ("<b>Компьютер</b>K-Pax, Happ и v2rayN.", "<b>Компьютер</b>X-Plm, Happ и v2rayN."),
    ("На компьютер — K-Pax.", "На компьютер — X-Plm."),
    ("На Windows откройте K-Pax и вставьте туда же.", "На Windows откройте X-Plm и вставьте туда же."),
    ('/logo.png" type="image/png"', '/logo.svg?v=%s" type="image/svg+xml"' % XPLM_ASSETS),
    ("/logo.png", "/logo.svg?v=%s" % XPLM_ASSETS),
    ("Редакция от 9 октября 2026 года", "Редакция от 21 октября 2026 года"),
    ("110 ₽", "299 ₽"),
    ("110&nbsp;₽", "299&nbsp;₽"),
    ('"price": "110"', '"price": "299"'),
    ("sub.k-pax.space", "sub.x-plm.online"),
    ("k-pax.space", "x-plm.online"),
    ("kpax://", "xplm://"),
    ("scheme=kpax", "scheme=xplm"),
    ("space.kpax.app", "online.xplm.app"),
    ("Укажите почту или Telegram.", "Укажите почту."),
    ("Укажите почту или Telegram", "Укажите почту"),
    ("почту или Telegram", "почту"),
    ("Если Telegram не открывается без VPN — подтвердите почтой.", "Подтвердите почту кодом из письма."),
    ("K-Pax", "X-Plm"),
)


def rebrand(text: str) -> str:
    """K-Pax wording → X-Plm wording. Safe to run on HTML, JSON and plain mail."""
    text = re.sub(r"<!--tg-->.*?<!--/tg-->", "", text, flags=re.S)
    text = re.sub(
        r'<a href="[^"]*/releases/download/[^"]*\.exe"[^>]*>K-Pax для Windows</a>',
        XPLM_WINDOWS_APP,
        text,
    )
    for old, new in XPLM_TEXT:
        text = text.replace(old, new)
    return text


REFERRAL_MODAL = """
<div id="ref-modal" class="modal" hidden>
<div class="sheet" role="dialog" aria-modal="true" aria-labelledby="ref-title">
<button class="x" type="button" id="close-ref" aria-label="Закрыть">×</button>
<h2 id="ref-title">15 дней за друга</h2>
<p>Введите свою почту или Telegram. Ссылка подключения не откроется. Появится кнопка: за каждого нового человека к вашей подписке добавится 15 дней, ему откроются обычные 14.</p>
<form id="ref-form">
<label for="ref-contact">Почта или Telegram</label>
<input id="ref-contact" maxlength="80" autocomplete="username" required placeholder="name@mail.ru или @username">
<button type="submit" id="ref-go">Продолжить</button>
</form>
<p id="ref-msg" class="err" hidden></p>
<p id="ref-signup" hidden><button type="button" id="ref-to-signup">Получить ссылку</button></p>
<p id="ref-get" hidden><button type="button" id="ref-copy">Получить реферальную ссылку</button></p>
<p id="refbox" hidden><code id="invite"></code></p>
</div>
</div>
<script>
(function () {
  var modal = document.getElementById("ref-modal");
  var form = document.getElementById("ref-form");
  var msg = document.getElementById("ref-msg");
  var getRow = document.getElementById("ref-get");
  var signupRow = document.getElementById("ref-signup");
  var box = document.getElementById("refbox");
  var invite = document.getElementById("invite");
  var go = document.getElementById("ref-go");
  var pending = "";
  function reset() {
    pending = "";
    msg.hidden = true;
    msg.textContent = "";
    getRow.hidden = true;
    signupRow.hidden = true;
    box.hidden = true;
    invite.textContent = "";
    go.hidden = false;
  }
  function show(on) {
    modal.hidden = !on;
    if (on) document.getElementById("ref-contact").focus();
  }
  document.getElementById("open-ref").addEventListener("click", function () { reset(); show(true); });
  document.getElementById("close-ref").addEventListener("click", function () { show(false); });
  modal.addEventListener("click", function (event) { if (event.target === modal) show(false); });
  document.addEventListener("keydown", function (event) { if (event.key === "Escape" && !modal.hidden) show(false); });
  document.getElementById("ref-contact").addEventListener("input", function () {
    if (getRow.hidden && signupRow.hidden) return;
    pending = "";
    getRow.hidden = true;
    signupRow.hidden = true;
    box.hidden = true;
    invite.textContent = "";
    go.hidden = false;
  });
  document.getElementById("ref-to-signup").addEventListener("click", function () {
    show(false);
    var field = document.getElementById("contact");
    if (!field) return;
    field.scrollIntoView({block: "center"});
    field.focus();
  });
  form.addEventListener("submit", function (event) {
    event.preventDefault();
    reset();
    go.hidden = true;
    fetch("/referral", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({contact: document.getElementById("ref-contact").value})
    }).then(function (response) { return response.json(); }).then(function (data) {
      if (!data.found) {
        msg.hidden = false;
        msg.textContent = data.error || "Этой почты ещё нет. Закройте окно и нажмите «Получить ссылку».";
        if (data.signup) signupRow.hidden = false;
        else go.hidden = false;
        return;
      }
      pending = data.url || "";
      getRow.hidden = false;
    }).catch(function () {
      go.hidden = false;
      msg.hidden = false;
      msg.textContent = "Не получилось проверить контакт. Попробуйте ещё раз.";
    });
  });
  document.getElementById("ref-copy").addEventListener("click", function () {
    if (!pending) return;
    invite.textContent = pending;
    box.hidden = false;
    if (navigator.clipboard) navigator.clipboard.writeText(pending);
  });
  var resend = document.getElementById("resend-mail");
  if (resend) {
    resend.addEventListener("click", function () {
      var field = document.getElementById("contact");
      var note = document.getElementById("resend-msg");
      resend.disabled = true;
      fetch("/restore-mail", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({contact: field ? field.value : ""})
      }).then(function (response) { return response.json(); }).then(function (data) {
        resend.disabled = false;
        if (!note) return;
        note.hidden = false;
        note.className = data.sent ? "ok" : "err";
        note.textContent = data.sent
          ? "Письмо со ссылкой отправлено. Проверьте папку «Спам»."
          : (data.error || "Не получилось отправить письмо.");
      }).catch(function () {
        resend.disabled = false;
        if (!note) return;
        note.hidden = false;
        note.className = "err";
        note.textContent = "Не получилось отправить письмо. Попробуйте ещё раз.";
      });
    });
  }
})();
</script>
"""


GIFT_MODAL = """
<div id="gift-modal" class="modal" hidden>
<div class="sheet" role="dialog" aria-modal="true" aria-labelledby="gift-title">
<button class="x" type="button" id="close-gift" aria-label="Закрыть">×</button>
<h2 id="gift-title">Оплатить другу</h2>
<p>Укажите почту или Telegram друга, у которого уже есть K-Pax. Откроется разовая оплата 110 ₽ через СБП — без автопродления. Продлится его счёт, ссылка у него не меняется.</p>
<form id="gift-form" method="post" action="/pay">
<label for="gift-contact">Почта или Telegram друга</label>
<input id="gift-contact" name="contact" maxlength="80" autocomplete="username" required placeholder="name@mail.ru или @username">
<div class="hp" aria-hidden="true"><input name="company" tabindex="-1" autocomplete="off"></div>
<button type="submit">Оплатить 110 ₽ другу</button>
</form>
</div>
</div>
<script>
(function () {
  var modal = document.getElementById("gift-modal");
  var open = document.getElementById("open-gift");
  if (!modal || !open) return;
  function show(on) {
    modal.hidden = !on;
    if (on) document.getElementById("gift-contact").focus();
  }
  open.addEventListener("click", function () { show(true); });
  document.getElementById("close-gift").addEventListener("click", function () { show(false); });
  modal.addEventListener("click", function (event) { if (event.target === modal) show(false); });
  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && !modal.hidden) show(false);
  });
})();
</script>
"""


def home(
    error: str = "",
    notice: str = "",
    restore: str = "",
    contact: str = "",
    ref: str = "",
    partner: str = "",
    index: bool = False,
    promo_contact: str = "",
    promo_code: str = "",
    promo_notice: str = "",
    promo_error: str = "",
    captcha_q: str = "",
    captcha_token: str = "",
) -> tuple[int, str, bytes]:
    err = "<p class='err'>%s</p>" % html.escape(error) if error else ""
    note = "<p class='ok'>%s</p>" % html.escape(notice) if notice else ""
    promo_note = "<p class='ok'>%s</p>" % html.escape(promo_notice) if promo_notice else ""
    promo_err = "<p class='err'>%s</p>" % html.escape(promo_error) if promo_error else ""
    if restore == "email":
        action = (
            "<p><button type='button' id='resend-mail'>Получить ссылку повторно</button></p>"
            "<p id='resend-msg' class='ok' hidden></p>"
        )
    elif restore == "telegram":
        action = (
            "<p class='muted'>Напишите с этого же Telegram. Бот пришлёт ссылку и сколько дней осталось.</p>"
            "<p><a class='restore' href='https://t.me/KPax_Space_bot?start=restore' target='_blank' rel='noopener'>Написать в Telegram</a></p>"
        )
    else:
        action = ""
    if restore:
        action += "<p class='muted'>Ссылка подключения повторно не показывается.</p>"
    captcha_fields = ""
    if captcha_q and captcha_token and not restore:
        captcha_fields = (
            '<label for="captcha">Сколько будет: %s</label>'
            '<input id="captcha" name="captcha" required maxlength="8" inputmode="numeric" autocomplete="off">'
            '<input type="hidden" name="captcha_token" value="%s">'
        ) % (html.escape(captcha_q), html.escape(captcha_token, quote=True))
    submit = (
        ""
        if restore
        else "<button type=\"submit\">Получить ссылку</button>"
    )
    legal = (
        ""
        if restore
        else "<p class=\"legal\">Получая ссылку, вы принимаете пользовательское соглашение и политику конфиденциальности. Ссылка выдаётся после подтверждения почты или Telegram.</p>"
    )
    invited = referral_code(ref) if referrer_exists(ref) else ""
    partner_ok = resolve_partner(partner)
    ref_field = ""
    if invited:
        ref_field += '<input type="hidden" name="ref" value="%s">' % html.escape(invited, quote=True)
    if partner_ok:
        ref_field += '<input type="hidden" name="p" value="%s">' % html.escape(partner_ok, quote=True)
    ref_note = (
        "<p class='ok'>Вас пригласили. Когда ссылка будет создана, пригласившему добавится 15 дней.</p>"
        if invited
        else ""
    )
    body = (xplm_templates.HOME if is_xplm() else kpax_templates.HOME).format(
        note=note,
        action=action,
        submit=submit,
        legal=legal,
        err=err,
        contact=html.escape(contact, quote=True),
        windows_url=html.escape(
            XPLM_WINDOWS_APP_URL if is_xplm() else WINDOWS_APP_URL, quote=True
        ),
        android_url=html.escape(XPLM_ANDROID_APP_URL if is_xplm() else ANDROID_APP_URL, quote=True),
        apps_hint=html.escape(APPS_HINT),
        ref_field=ref_field,
        ref_note=ref_note,
        promo_note=promo_note,
        promo_err=promo_err,
        promo_contact=html.escape(promo_contact or contact, quote=True),
        promo_code=html.escape(promo_code, quote=True),
        captcha_fields=captcha_fields,
    )
    body += REFERRAL_MODAL
    body += GIFT_MODAL
    visible = index and not error and not promo_error
    return page(
        HOME_TITLE if visible else "K-Pax",
        body,
        400 if error or promo_error else 200,
        landing=True,
        home=True,
        index=visible,
        description=HOME_DESC,
        canonical=SITE + "/",
        json_ld=seo_json_ld() if visible else "",
        faq_fab=True,
    )


def pay_result_page(title: str, text: str, *, open_app: bool = False) -> tuple[int, str, bytes]:
    app_block = ""
    if open_app:
        app_block = """
<p class="buyrow"><a class="restore" href="kpax://paid">Открыть приложение и обновить доступ</a></p>
<p class="muted">Android: <a href="intent://paid#Intent;scheme=kpax;package=space.kpax.app;end">вернуть в K-Pax</a></p>
<script>setTimeout(function(){ try { location.href = 'kpax://paid'; } catch (e) {} }, 400);</script>
"""
    body = """
<section class="support paypage">
<h1>%s</h1>
<p>%s</p>
%s
<p class="buyrow"><a class="restore" href="/pay">Вернуться к оплате</a></p>
</section>
""" % (html.escape(title), html.escape(text), app_block)
    return page(title + " — K-Pax", body, landing=True, buy=False, faq_fab=True)


PAY_STUB = (
    '<p class="stub">Онлайн-оплата скоро откроется. Сейчас доступен бесплатный период 14 дней, '
    "без привязки карты. Когда оплата заработает, напишем на почту.</p>"
)
PAY_STUB_TEXT = "Онлайн-оплата скоро откроется. Сейчас доступен бесплатный период 14 дней."


def pay_page(error: str = "", contact: str = "") -> tuple[int, str, bytes]:
    err = '<p class="err">%s</p>' % html.escape(error) if error else ""
    body = """
<section class="support paypage">
<h1>Оплатить подписку</h1>
<p class="payfigure">110 ₽ за 30 дней</p>
<p class="muted">Без автопродления · карта не привязывается · разовая СБП</p>
<p>Покупатель получает подключение для работы в интернете без рекламы. Между устройством и сетью создаётся безопасное соединение.</p>
<ul>
<li>2 устройства: телефон и компьютер, одна ссылка.</li>
<li>Оплата продлевает ту же ссылку на 30 дней. Новая ссылка не выдаётся.</li>
<li>Рекламные сети и трекеры отключаются на каждом подключении.</li>
<li>Торренты на подключении не работают.</li>
<li>Каждая 6-я оплата — бонус +7 дней к сроку.</li>
</ul>
<p>До первой оплаты — 14 дней бесплатно, без привязки карты.</p>
<p>Оплата через СБП: QR-код и ссылка из банковского приложения. Укажите почту или Telegram счёта, который нужно продлить — свой или друга.</p>
<form class="signup" method="post" action="/pay">
<label for="contact">Почта или Telegram счёта</label>
<input id="contact" name="contact" autocomplete="username" required maxlength="80" placeholder="name@mail.ru или @username" value="%s">
<div class="hp" aria-hidden="true"><input name="company" tabindex="-1" autocomplete="off"></div>
<p class="muted">110 ₽ списываются один раз и продлевают этот счёт на 30 дней. Без автопродления. Ссылка подключения не меняется.</p>
%s
%s
</form>
<div class="docbtns">
<a href="/faq">FAQ</a>
<a href="/terms">Пользовательское соглашение</a>
<a href="/privacy">Политика конфиденциальности</a>
<a href="/terms#refund">Условия возврата</a>
<a href="mailto:support@k-pax.space">Поддержка: support@k-pax.space</a>
</div>
</section>
""" % (
        html.escape(contact, quote=True),
        err,
        PAY_STUB + '<button type="submit" disabled>Оплатить 110 ₽</button>'
        if not brand()["payments"]
        else '<button type="submit">Оплатить 110 ₽</button>',
    )
    return page(
        "Оплатить подписку — K-Pax",
        body,
        400 if error else 200,
        landing=True,
        buy=False,
        index=not error,
        description=PAY_DESC,
        canonical=SITE + "/pay",
        faq_fab=True,
    )


def faq_page() -> tuple[int, str, bytes]:
    body = (
        """
<section class="support paypage faqpage">
<h1>Частые вопросы</h1>
<p class="muted">Короткие ответы про ссылку, оплату и поддержку. Если не нашли — напишите нам.</p>
<div class="faq">
"""
        + FAQ_ITEMS
        + """
</div>
<h2>Поддержка</h2>
<p class="muted">Жалобы, предложения и возврат — на support@k-pax.space. Ссылку возвращает робот: письмо с той же почты на access@k-pax.space или бот с того же Telegram.</p>
<div class="docbtns">
<a href="mailto:support@k-pax.space">support@k-pax.space</a>
<a href="mailto:access@k-pax.space?subject=%D0%92%D0%BE%D1%81%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BB%D0%B5%D0%BD%D0%B8%D0%B5%20%D0%B4%D0%BE%D1%81%D1%82%D1%83%D0%BF%D0%B0%20K-Pax">access@k-pax.space</a>
<a href="https://t.me/KPax_Space_bot">@KPax_Space_bot</a>
<a href="https://t.me/k_pax_space">Менеджер @k_pax_space</a>
<a href="/terms#refund">Условия возврата</a>
<a href="/pay">Оплатить</a>
</div>
</section>
"""
    )
    return page(
        "FAQ — K-Pax",
        body,
        landing=True,
        buy=True,
        index=True,
        description=FAQ_DESC,
        canonical=SITE + "/faq",
        faq_fab=False,
    )


def terms_page() -> tuple[int, str, bytes]:
    body = """
<h1>Пользовательское соглашение</h1>
<p class="muted">Редакция от 30 октября 2026 года. Сервис: https://k-pax.space</p>
<div class="docs">
<h2>1. Общие положения</h2>
<p>1.1. Настоящее Пользовательское соглашение регулирует использование онлайн-сервиса K-Pax на сайте https://k-pax.space и официальных клиентах K-Pax для Android и Windows (далее — «Сервис»).</p>
<p>1.2. Используя Сервис, включая получение ссылки доступа, запуск приложения, установку обновления клиента или оплату, Пользователь подтверждает, что ознакомился с Соглашением, Политикой конфиденциальности и условиями возврата и принимает их.</p>
<p>1.3. Если Пользователь не согласен с условиями, он обязан прекратить использование Сервиса.</p>
<h2>2. Услуга и тариф</h2>
<p>2.1. K-Pax — подключение для работы в интернете без рекламы. Между устройством Пользователя и сетью создаётся безопасное соединение. На каждом подключении известные рекламные сети и трекеры обрываются.</p>
<p>2.2. Тариф один. Первые 14 дней — бесплатно, без привязки карты. Далее подписка стоит 110 ₽ за 30 дней.</p>
<p>2.3. Одновременно можно подключить два устройства. Ссылка доступа показывается один раз и при оплате не меняется: 110 ₽ продлевают срок той же ссылки на 30 дней.</p>
<p>2.4. Номер счёта сам по себе подключение не открывает. Если страну не выбирать, приложение использует сервер, который отвечает быстрее.</p>
<p>2.4.1. Официальные клиенты K-Pax могут проверять наличие новой версии на сервере Сервиса и предлагать установку обновления с официальной страницы релизов. Установка обновления добровольна.</p>
<p>2.5. Оплата принимается через СБП НСПК: QR-код и ссылка из банковского приложения. Стоимость для Пользователя указана на сайте до оплаты и составляет 110 ₽ за 30 дней.</p>
<p>2.6. Услуга цифровая и нематериальная. Доступ считается предоставленным, когда Пользователь получил рабочую ссылку.</p>
<p>2.7. Торренты на подключении не работают.</p>
<h2>3. Отказ от гарантий</h2>
<p>3.1. Сервис предоставляется на условиях «как есть».</p>
<p>3.2. Администрация не гарантирует соответствие Сервиса ожиданиям Пользователя и бесперебойную работу сети, серверов и приложений.</p>
<p>3.3. Администрация не отвечает за прямые и косвенные убытки, действия третьих лиц и временные технические сбои.</p>
<h2>4. Законность использования</h2>
<p>4.1. Сервис не предназначен для противоправной деятельности.</p>
<p>4.2. Пользователь обязуется использовать Сервис в рамках применимого законодательства.</p>
<p>4.3. Ответственность за законность использования Сервиса несёт Пользователь.</p>
<h2>5. Интеллектуальная собственность</h2>
<p>5.1. Ссылку доступа нельзя передавать другим людям, копировать для перепродажи или публиковать.</p>
<p>5.2. При нарушении Администрация может остановить доступ без компенсации.</p>
<h2>6. Приостановка доступа</h2>
<p>6.1. Администрация вправе приостановить доступ, если Пользователь нарушил Соглашение, ссылкой явно пользуются чужие люди, либо этого требуют закон или платёжный партнёр.</p>
<p>6.2. Приостановка доступа не отменяет обязательства, которые уже возникли.</p>
<h2 id="refund">7. Платежи и возврат</h2>
<p>7.1. Цена и срок указаны на сайте до оплаты: 110 ₽ за 30 дней после бесплатных 14 дней.</p>
<p>7.2. После того как доступ предоставлен, возврат не производится, кроме случаев ниже.</p>
<p>7.3. Возврат возможен, если услуга не оказана по технической вине Сервиса и доступ фактически не был предоставлен.</p>
<p>7.4. Заявление нужно отправить в поддержку в течение 24 часов с момента оплаты: на support@k-pax.space или в Telegram-бот @KPax_Space_bot.</p>
<p>7.5. Решение о возврате принимает Администрация.</p>
<p>7.6. Пользователь обязуется не запрашивать отмену платежа через банк или платёжную систему, не обратившись сначала в поддержку Сервиса.</p>
<h2>8. Конфиденциальность</h2>
<p>8.1. Порядок обработки данных описан в Политике конфиденциальности на странице https://k-pax.space/privacy.</p>
<h2>9. Изменение условий</h2>
<p>9.1. Администрация может обновлять Соглашение. Новая редакция публикуется на этой странице с датой.</p>
<p>9.2. Продолжение использования Сервиса означает согласие с новой редакцией.</p>
<h2>10. Контакты поддержки</h2>
<p>10.1. Поддержка, жалобы и возврат: support@k-pax.space. Возврат ссылки: письмо с той же почты на access@k-pax.space. Telegram-бот: @KPax_Space_bot, https://t.me/KPax_Space_bot.</p>
<p>Используя Сервис, Пользователь подтверждает, что ознакомился с Соглашением и принимает его.</p>
</div>
<div class="docbtns"><a href="/terms">Пользовательское соглашение</a><a href="/privacy">Политика конфиденциальности</a><a href="/terms#refund">Условия возврата</a><a href="/pay">Тарифы и оплата</a><a href="mailto:support@k-pax.space">Поддержка: support@k-pax.space</a></div>
"""
    return page(
        "Пользовательское соглашение — K-Pax",
        body,
        index=True,
        description=TERMS_DESC,
        canonical=SITE + "/terms",
    )


def privacy_page() -> tuple[int, str, bytes]:
    body = """
<h1>Политика конфиденциальности</h1>
<p class="muted">Редакция от 30 октября 2026 года. Сервис: https://k-pax.space</p>
<div class="docs">
<p>Политика описывает, какие данные собирает K-Pax, зачем они нужны и как защищаются. Паспорт и фотографии документов Сервис не запрашивает.</p>
<h2>1. Общие положения</h2>
<p>1.1. Политика регулирует обработку информации, которую Пользователь передаёт при использовании сайта https://k-pax.space, официальных клиентов K-Pax для Android и Windows и сервиса K-Pax для работы без рекламы.</p>
<p>1.2. Пользуясь Сервисом, Пользователь соглашается с Политикой. Если он не согласен, он прекращает использование Сервиса.</p>
<h2>2. Какие данные собираются</h2>
<p>2.1. Сервис хранит только то, что нужно для доступа:</p>
<ol>
<li>почту или ник Telegram;</li>
<li>номер счёта;</li>
<li>срок доступа;</li>
<li>технический ключ, без которого приложение не подключается;</li>
<li>IP-адрес в момент создания аккаунта, чтобы ограничить массовую регистрацию;</li>
<li>сообщения, которые Пользователь сам отправляет в поддержку;</li>
<li>при проверке обновления клиента — факт запроса и версия приложения (без списка сайтов и без содержимого трафика).</li>
</ol>
<p>2.2. Содержимое сайтов и переписки внутри соединения Сервис не читает и не продаёт.</p>
<p>2.3. Паспортные данные, документы и фотографии не требуются.</p>
<h2>3. Зачем используются данные</h2>
<p>3.1. Данные используются, чтобы выдать доступ, продлить ту же ссылку, вернуть потерянную ссылку и ответить в поддержку.</p>
<p>3.2. На серверах могут оставаться технические записи о сбоях соединения. Это не список сайтов, которые открывал Пользователь.</p>
<h2>4. Передача третьим лицам</h2>
<p>4.1. Данные не передаются третьим лицам, кроме случаев, когда это требует закон, когда это нужно для проведения оплаты через платёжного партнёра, или когда Пользователь сам согласился.</p>
<h2>5. Хранение и защита</h2>
<p>5.1. Данные хранятся, пока нужен доступ и пока Пользователь может запросить восстановление ссылки.</p>
<p>5.2. Администрация принимает разумные меры защиты, но не обещает абсолютную безопасность передачи через интернет.</p>
<h2>6. Отказ от ответственности</h2>
<p>6.1. Передача данных через интернет связана с риском.</p>
<p>6.2. Администрация не отвечает за утрату данных по вине третьих лиц или самого Пользователя.</p>
<h2>7. Изменения</h2>
<p>7.1. Политика может обновляться. Новая редакция публикуется на этой странице с датой.</p>
<p>7.2. Продолжение использования Сервиса означает согласие с новой редакцией.</p>
<h2>8. Удаление и контакты</h2>
<p>8.1. Удалить доступ можно письмом на support@k-pax.space с той же почты или сообщением боту @KPax_Space_bot с того же Telegram.</p>
<p>8.2. Поддержка: support@k-pax.space. Возврат ссылки: access@k-pax.space. Бот: https://t.me/KPax_Space_bot.</p>
</div>
<div class="docbtns"><a href="/terms">Пользовательское соглашение</a><a href="/privacy">Политика конфиденциальности</a><a href="/terms#refund">Условия возврата</a><a href="/pay">Тарифы и оплата</a><a href="mailto:support@k-pax.space">Поддержка: support@k-pax.space</a></div>
"""
    return page(
        "Политика конфиденциальности — K-Pax",
        body,
        index=True,
        description=PRIVACY_DESC,
        canonical=SITE + "/privacy",
    )


def legal_page(title: str, paragraphs: tuple[str, ...]) -> tuple[int, str, bytes]:
    body = "<h1>%s</h1><div class='docs'>%s</div>" % (
        html.escape(title),
        "".join("<p>%s</p>" % html.escape(item) for item in paragraphs),
    )
    return page("K-Pax — " + title, body)


def qr_svg(text: str) -> str:
    qr = qrcodegen.QrCode.encode_text(text, qrcodegen.QrCode.Ecc.MEDIUM)
    border = 4
    size = qr.get_size()
    dim = size + border * 2
    parts = []
    for y in range(size):
        for x in range(size):
            if qr.get_module(x, y):
                parts.append("M%d %dh1v1h-1z" % (x + border, y + border))
    return (
        '<svg class="qr" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" role="img" aria-label="QR-код ссылки подписки">'
        '<rect width="%d" height="%d" fill="#ffffff"/>'
        '<path fill="#10141c" d="%s"/></svg>'
    ) % (dim, dim, dim, dim, "".join(parts))


def welcome(
    user: sqlite3.Row,
    invited: bool = False,
    mailed: bool = False,
    promo_note: str = "",
) -> tuple[int, str, bytes]:
    url = sub_url(user["token"])
    invite = "https://k-pax.space/?ref=" + user["public_id"]
    invited_note = (
        "<p class='ok'>Пригласившему добавлено 15 дней.</p>" if invited else ""
    )
    if promo_note:
        invited_note += "<p class='%s'>%s</p>" % (
            "err" if promo_note.startswith(PROMO_FAILED) else "ok",
            html.escape(promo_note),
        )
    mailed_note = (
        "<p class='ok'>Копия ссылки отправлена на эту почту. Проверьте папку «Спам».</p>"
        if mailed
        else ""
    )
    body = """
<p class="lead">Аккаунт создан. Сохраните номер и ссылку.</p>
{invited}
<div class="card">
<p><b>Номер</b><br><code>{pid}</code></p>
<p><b>Ссылка подписки</b><br><code id="sub">{url}</code></p>
<button class="copy" type="button" onclick="navigator.clipboard.writeText(document.getElementById('sub').textContent)">Скопировать ссылку</button>
{open_apps}
<div class="qrwrap">{qr}</div>
<p class="muted">Наведите камеру в INCY или Happ: кнопка «+». Или откройте одним тапом кнопками выше. Действует до {until}. Ссылка не меняется: позже по ней же продлевается срок.</p>
{mailed}
<p class="muted">Если Hiddify пишет «Не удалось добавить профиль», поставьте INCY или Happ. Ссылка при этом рабочая.</p>
<p><b>Приглашение</b></p>
<p class="muted">Это не ссылка подключения. Её отправляют другу.</p>
<p><code id="invite">{invite}</code></p>
<p class="muted">За каждого нового человека по этой ссылке к вашей подписке добавится 15 дней. Ему откроются обычные 14 дней. Номер сам по себе не подключает.</p>
</div>
<h2>Как подключить</h2>
<ol>
<li>На Windows и Android откройте приложение K-Pax: почта → код из письма.</li>
<li>На iPhone пока — INCY или Happ: «+» и ссылка с этой страницы или из письма.</li>
<li>В K-Pax ссылку копировать не нужно — доступ уже в приложении.</li>
<li>Сверху будет «Автоматический выбор»: приложение само берёт быстрый сервер.</li>
</ol>
<p class="muted">Ссылка одновременно работает на 2 устройствах: телефон и компьютер. Номер {pid} сам по себе не подключает. Если ссылка потеряется, откройте бота @KPax_Space_bot с этого Telegram или напишите с этой почты на access@k-pax.space.</p>
""".format(
        pid=html.escape(user["public_id"]),
        url=html.escape(url),
        until=html.escape(fmt(user["expires_at"])),
        qr=qr_svg(url),
        invite=html.escape(invite),
        invited=invited_note,
        mailed=mailed_note,
        open_apps=deep_link_buttons(url),
    )
    return page("K-Pax — доступ", body, landing=True, faq_fab=True)


def bot_verify_url(token: str) -> str:
    return "https://t.me/KPax_Space_bot?start=v_" + token


def pending_verify_page(
    user: sqlite3.Row,
    *,
    error: str = "",
    notice: str = "",
    captcha_q: str = "",
    captcha_token: str = "",
) -> tuple[int, str, bytes]:
    contact = str(user["contact"] or "")
    err = '<p class="err">%s</p>' % html.escape(error) if error else ""
    note = '<p class="ok">%s</p>' % html.escape(notice) if notice else ""
    token = str(user["verify_token"] or "")
    if contact.startswith("@"):
        body = """
<section class="support paypage">
<h1>Подтвердите Telegram</h1>
{note}{err}
<p>Аккаунт <code>{contact}</code> создан, но ссылка ещё не выдана. Откройте бота с этого же Telegram — так мы убедимся, что ник ваш.</p>
<p class="buyrow"><a class="restore" href="{bot}" target="_blank" rel="noopener">Открыть @KPax_Space_bot</a></p>
<p class="muted">Если Telegram не открывается без VPN — подтвердите почтой. Временные ящики не принимаем.</p>
<form class="signup" method="post" action="/verify/email-fallback">
<input type="hidden" name="token" value="{token}">
<label for="email-fallback">Почта</label>
<input id="email-fallback" name="email" type="email" required maxlength="80" placeholder="name@mail.ru" autocomplete="email">
<button type="submit">Подтвердить почтой</button>
</form>
<p class="muted">После подтверждения откроется ссылка подписки на 14 дней.</p>
</section>
""".format(
            contact=html.escape(contact),
            bot=html.escape(bot_verify_url(token), quote=True),
            token=html.escape(token, quote=True),
            note=note,
            err=err,
        )
    else:
        captcha_block = ""
        if captcha_q and captcha_token:
            captcha_block = """
<label for="captcha">Сколько будет: {q}</label>
<input id="captcha" name="captcha" required maxlength="8" inputmode="numeric" autocomplete="off">
<input type="hidden" name="captcha_token" value="{ct}">
""".format(q=html.escape(captcha_q), ct=html.escape(captcha_token, quote=True))
        body = """
<section class="support paypage">
<h1>Подтвердите почту</h1>
{note}{err}
<p>На <code>{contact}</code> отправлен код. Введите его ниже — после этого появится ссылка подписки.</p>
<form class="signup" method="post" action="/verify">
<input type="hidden" name="token" value="{token}">
<label for="code">Код из письма</label>
<input id="code" name="code" required maxlength="8" inputmode="numeric" autocomplete="one-time-code" placeholder="123456">
{captcha}
<button type="submit">Подтвердить</button>
</form>
<form class="signup" method="post" action="/verify/resend" style="margin-top:1rem">
<input type="hidden" name="token" value="{token}">
<button type="submit" class="ghost">Отправить код ещё раз</button>
</form>
<p class="muted">Проверьте «Спам». Код действует 30 минут.</p>
</section>
""".format(
            contact=html.escape(contact),
            token=html.escape(token, quote=True),
            note=note,
            err=err,
            captcha=captcha_block,
        )
    return page("Подтверждение — K-Pax", body, landing=True, faq_fab=True)


LOGIN_FAILS: dict[str, list[int]] = {}
REF_LOOKUPS: dict[str, list[int]] = {}
RESEND_MAIL: dict[str, list[int]] = {}
PAY_STARTS: dict[str, list[int]] = {}
PROMO_TRIES: dict[str, list[int]] = {}
# user_key -> recent event timestamps (soft ~120/min)
CLIENT_EVENT_HITS: dict[str, list[int]] = {}
CLIENT_AUTOTEST_Q: queue.Queue = queue.Queue()
CLIENT_AUTOTEST_LOCK = threading.Lock()
# "user|host|port" -> last enqueue monotonic time
CLIENT_AUTOTEST_DEBOUNCE_AT: dict[str, float] = {}
TG_WAIT: dict[int, dict] = {}
TG_WAIT_TTL = 600


def password_digest(password: str, salt: bytes) -> bytes:
    return hashlib.scrypt(password.encode("utf-8"), salt=salt, n=16384, r=8, p=1, dklen=32)


def password_ok(password: str) -> bool:
    try:
        if is_xplm():
            salt = bytes.fromhex(admin_setting("admin_password_salt"))
            expected = bytes.fromhex(admin_setting("admin_password_hash"))
            if not expected:
                return False
        else:
            salt = bytes.fromhex(CFG["admin_password_salt"])
            expected = bytes.fromhex(CFG["admin_password_hash"])
        actual = password_digest(password, salt)
    except Exception:
        return False
    return hmac.compare_digest(actual, expected)


def user_ok(name: str) -> bool:
    actual = name.encode("utf-8")
    if is_xplm():
        expected = admin_setting("admin_user").encode("utf-8")
    else:
        expected = str(CFG.get("admin_user") or "").encode("utf-8")
    if len(actual) != len(expected) or not expected:
        return False
    return hmac.compare_digest(actual, expected)


def set_brand_admin(bid: str, name: str, password: str) -> None:
    name = name.strip()
    if not re.fullmatch(r"[A-Za-z0-9._-]{3,32}", name):
        raise ValueError("Логин: 3–32 символа, латиница, цифры, точка, дефис.")
    if len(password) < 12:
        raise ValueError("Пароль не короче 12 символов.")
    salt = secrets.token_bytes(16)
    with brand_context(bid):
        set_admin_setting("admin_user", name)
        set_admin_setting("admin_password_salt", salt.hex())
        set_admin_setting("admin_password_hash", password_digest(password, salt).hex())
        set_admin_setting("session_epoch", str(session_epoch() + 1))


def admin_key(key: str) -> str:
    return key if brand_id() == "kpax" else brand_id() + ":" + key


def admin_setting(key: str) -> str:
    conn = db()
    row = conn.execute("SELECT value FROM admin_settings WHERE key=?", (admin_key(key),)).fetchone()
    conn.close()
    return str(row["value"]) if row is not None else ""


def set_admin_setting(key: str, value: str | None) -> None:
    key = admin_key(key)
    with LOCK:
        conn = db()
        if value is None:
            conn.execute("DELETE FROM admin_settings WHERE key=?", (key,))
        else:
            conn.execute(
                "INSERT INTO admin_settings(key, value) VALUES(?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                (key, value),
            )
        conn.commit()
        conn.close()


def session_epoch() -> int:
    raw = admin_setting("session_epoch")
    return int(raw) if raw.isdigit() else 0


def session_key() -> bytes:
    secret = str(CFG["session_secret"])
    return (secret if brand_id() == "kpax" else secret + ":" + brand_id()).encode("utf-8")


def make_session() -> str:
    claims = {"exp": now_ts() + 14 * 86400, "e": session_epoch()}
    body = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
    signature = hmac.new(session_key(), body.encode("utf-8"), hashlib.sha256).hexdigest()
    return body + "." + signature


def session_ok(value: str) -> bool:
    if value.count(".") != 1:
        return False
    body, signature = value.split(".", 1)
    expected = hmac.new(session_key(), body.encode("utf-8"), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature, expected):
        return False
    try:
        padded = body + "=" * (-len(body) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded))
        if int(payload.get("e", 0)) != session_epoch():
            return False
        return int(payload.get("exp", 0)) > now_ts()
    except Exception:
        return False


TOTP_STEP = 30
TOTP_ISSUER = "K-Pax admin"


def totp_secret() -> str:
    if not brand()["admin_totp"]:
        return ""
    return admin_setting("totp_secret")


def new_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def totp_at(secret: str, counter: int) -> str:
    key = base64.b32decode(secret + "=" * (-len(secret) % 8), casefold=True)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    return "%06d" % (value % 1_000_000)


def totp_match(secret: str, code: str, now: float | None = None) -> int | None:
    """Counter of the matching step within ±1 step, or None."""
    code = re.sub(r"\s+", "", code or "")
    if not secret or not re.fullmatch(r"\d{6}", code):
        return None
    current = int((time.time() if now is None else now) // TOTP_STEP)
    for counter in (current - 1, current, current + 1):
        if hmac.compare_digest(totp_at(secret, counter), code):
            return counter
    return None


def totp_accept(code: str) -> bool:
    """Check the enrolled secret and refuse a code that was already used."""
    counter = totp_match(totp_secret(), code)
    if counter is None:
        return False
    last = admin_setting("totp_last")
    if last.isdigit() and counter <= int(last):
        return False
    set_admin_setting("totp_last", str(counter))
    return True


def totp_uri(secret: str) -> str:
    issuer = brand()["name"] + " admin"
    account = admin_setting("admin_user") if is_xplm() else str(CFG.get("admin_user") or "admin")
    label = quote(issuer + ":" + (account or "admin"))
    return "otpauth://totp/%s?secret=%s&issuer=%s&digits=6&period=%d" % (
        label,
        secret,
        quote(issuer),
        TOTP_STEP,
    )


def enable_totp(secret: str) -> None:
    set_admin_setting("totp_secret", secret)
    set_admin_setting("totp_pending", None)
    set_admin_setting("totp_last", None)
    set_admin_setting("session_epoch", str(session_epoch() + 1))


def reset_totp() -> None:
    for key in ("totp_secret", "totp_pending", "totp_last"):
        set_admin_setting(key, None)
    set_admin_setting("session_epoch", str(session_epoch() + 1))


def login_blocked(ip: str) -> bool:
    now = now_ts()
    with LOCK:
        hits = [stamp for stamp in LOGIN_FAILS.get(ip, []) if now - stamp < 900]
        LOGIN_FAILS[ip] = hits
        return len(hits) >= 8


def note_login_fail(ip: str) -> None:
    with LOCK:
        LOGIN_FAILS.setdefault(ip, []).append(now_ts())


def referral_limited(ip: str) -> bool:
    now = now_ts()
    with LOCK:
        hits = [stamp for stamp in REF_LOOKUPS.get(ip, []) if now - stamp < 3600]
        REF_LOOKUPS[ip] = hits
        return len(hits) >= 30


def note_referral_lookup(ip: str) -> None:
    with LOCK:
        REF_LOOKUPS.setdefault(ip, []).append(now_ts())


def resend_limited(ip: str) -> bool:
    now = now_ts()
    with LOCK:
        hits = [stamp for stamp in RESEND_MAIL.get(ip, []) if now - stamp < 3600]
        RESEND_MAIL[ip] = hits
        return len(hits) >= 10


def note_resend(ip: str) -> None:
    with LOCK:
        RESEND_MAIL.setdefault(ip, []).append(now_ts())


def pay_limited(ip: str) -> bool:
    now = now_ts()
    with LOCK:
        hits = [stamp for stamp in PAY_STARTS.get(ip, []) if now - stamp < 3600]
        PAY_STARTS[ip] = hits
        return len(hits) >= 8


def note_pay_start(ip: str) -> None:
    with LOCK:
        PAY_STARTS.setdefault(ip, []).append(now_ts())


def promo_limited(ip: str) -> bool:
    now = now_ts()
    with LOCK:
        hits = [stamp for stamp in PROMO_TRIES.get(ip, []) if now - stamp < 3600]
        PROMO_TRIES[ip] = hits
        return len(hits) >= 20


def note_promo_try(ip: str) -> None:
    with LOCK:
        PROMO_TRIES.setdefault(ip, []).append(now_ts())


def recent_invoices(user_id: int) -> int:
    conn = db()
    count = conn.execute(
        "SELECT COUNT(*) FROM platega_invoices WHERE user_id=? AND created_at>?",
        (user_id, now_ts() - 3600),
    ).fetchone()[0]
    conn.close()
    return int(count)


def mbps_text(value: float) -> str:
    text = "%.0f" % value if value >= 100 else "%.1f" % value
    return text.replace(".", ",")


def probe_front_ports(node: dict) -> tuple[list[str], list[str]]:
    """TCP check of whitelist front listen ports from the panel."""
    host = str(node.get("host") or "").strip()
    ports = node.get("front_ports") or {}
    if not host or not isinstance(ports, dict):
        return [], ["нет front_ports"]
    ok: list[str] = []
    bad: list[str] = []
    for exit_id, raw in sorted(ports.items()):
        try:
            port = int(raw)
        except (TypeError, ValueError):
            bad.append("%s:?" % str(exit_id).upper())
            continue
        label = "%s:%d" % (str(exit_id).upper(), port)
        try:
            with socket.create_connection((host, port), timeout=PROBE_TIMEOUT):
                ok.append(label)
        except OSError:
            bad.append(label)
    return ok, bad


def health_cards() -> str:
    titles = {"de": "Германия", "fi": "Финляндия", "bg": "Болгария"}
    now = time.time()
    cards = []
    with DEVICE_LOCK:
        snapshot = {host: dict(sample) for host, sample in NODE_HEALTH.items()}
    for node in CFG["nodes"]:
        if is_front_node(node):
            title = html.escape(country_name(node))
        else:
            title = html.escape(titles.get(str(node.get("id") or "").lower(), node["name"]))
        sample = snapshot.get(node["host"])
        if is_front_node(node):
            ok, bad = probe_front_ports(node)
            label = html.escape(front_card_label(node))
            if ok and not bad:
                ports = "<p class='ok'>порты: %s</p>" % html.escape(", ".join(ok))
            elif ok and bad:
                ports = (
                    "<p class='ok'>ок: %s</p><p class='err'>нет: %s</p>"
                    % (html.escape(", ".join(ok)), html.escape(", ".join(bad)))
                )
            else:
                ports = "<p class='err'>порты: %s</p>" % html.escape(", ".join(bad) or "нет ответа")
            if sample and now - sample["seen"] <= 30:
                cards.append(
                    "<article class='health'><b>{title}</b>"
                    "<p class='muted'>whitelist → DE/FI/BG · {label}</p>"
                    "<p><span class='figure'>{online}</span> онлайн</p>"
                    "<p><span class='figure'>{speed}</span> Мбит/с</p>"
                    "<p class='muted'>Процессор {load} из {cores}</p>"
                    "{ports}</article>".format(
                        title=title,
                        label=label,
                        online=sample["online"],
                        speed=mbps_text(max(sample["rx"], sample["tx"])),
                        load=("%.2f" % sample["load"]).replace(".", ","),
                        cores=sample["cores"],
                        ports=ports,
                    )
                )
            else:
                cards.append(
                    "<article class='health'><b>%s</b>"
                    "<p class='muted'>whitelist → DE/FI/BG · %s</p>"
                    "<p class='muted'>Нет свежих данных нагрузки.</p>%s</article>"
                    % (title, label, ports)
                )
            continue
        if not sample or now - sample["seen"] > 30:
            cards.append("<article class='health'><b>%s</b><p class='muted'>Нет свежих данных.</p></article>" % title)
            continue
        cards.append(
            "<article class='health'><b>{title}</b>"
            "<p><span class='figure'>{online}</span> онлайн</p>"
            "<p><span class='figure'>{speed}</span> Мбит/с</p>"
            "<p class='muted'>Процессор {load} из {cores}</p></article>".format(
                title=title,
                online=sample["online"],
                speed=mbps_text(max(sample["rx"], sample["tx"])),
                load=("%.2f" % sample["load"]).replace(".", ","),
                cores=sample["cores"],
            )
        )
    return (
        "<div class='healthrow'>%s</div>"
        "<p class='muted'>EU — выход. Russia front — вход при белых списках (скрытый spare в подписке). "
        "Новый EU-сервер пора подключать, когда одна страна долго держит канал у предела тарифа.</p>"
        % "".join(cards)
    )


def remember_health(host: str, stats: object, online: int, now: float) -> None:
    if not isinstance(stats, dict):
        return
    try:
        load = float(stats.get("load"))
        cores = int(stats.get("cores"))
        rx = float(stats.get("rx_mbps"))
        tx = float(stats.get("tx_mbps"))
    except (TypeError, ValueError):
        return
    if not (1 <= cores <= 256 and 0 <= load <= 1000 and 0 <= rx <= 100000 and 0 <= tx <= 100000):
        return
    NODE_HEALTH[host] = {
        "load": load,
        "cores": cores,
        "rx": rx,
        "tx": tx,
        "online": max(0, min(online, 100000)),
        "seen": now,
    }


PROTO_LABELS = {
    "reality": "Reality",
    "hy2": "Hy2",
    "grpc": "gRPC",
    "tuic": "TUIC",
    "message": "Сообщения",
    "xhttp": "XHTTP",
    "vless": "VLESS",
    "other": "Другой",
}
USER_SORTS = (
    "online",
    "speed",
    "traffic",
    "server",
    "proto",
    "until",
    "id",
    "contact",
    "os",
    "status",
    "paid",
    "last_paid",
)
PAGE_SIZE = 20


def user_key(user_uuid: str) -> str:
    return "kp-" + user_uuid.replace("-", "")[:8]


def msk_day_start(moment: int | None = None) -> int:
    current = datetime.fromtimestamp(moment if moment is not None else now_ts(), MSK)
    start = current.replace(hour=0, minute=0, second=0, microsecond=0)
    return int(start.timestamp())


def msk_month_start(moment: int | None = None) -> int:
    current = datetime.fromtimestamp(moment if moment is not None else now_ts(), MSK)
    start = current.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    return int(start.timestamp())


def month_key(moment: int | None = None) -> str:
    return datetime.fromtimestamp(moment if moment is not None else now_ts(), MSK).strftime("%Y-%m")


def month_label(moment: int | None = None) -> str:
    names = (
        "январь",
        "февраль",
        "март",
        "апрель",
        "май",
        "июнь",
        "июль",
        "август",
        "сентябрь",
        "октябрь",
        "ноябрь",
        "декабрь",
    )
    current = datetime.fromtimestamp(moment if moment is not None else now_ts(), MSK)
    return "%s %d" % (names[current.month - 1], current.year)


def bytes_text(amount: int) -> str:
    value = float(max(0, int(amount)))
    for unit in ("Б", "КБ", "МБ", "ГБ", "ТБ"):
        if value < 1024 or unit == "ТБ":
            if unit == "Б":
                return "%d Б" % int(value)
            text = "%.1f" % value if value < 10 else "%.0f" % value
            return text.replace(".", ",") + " " + unit
        value /= 1024
    return "0 Б"


def bps_text(bps: float) -> str:
    return mbps_text(max(0.0, bps) * 8 / 1_000_000) + " Мбит/с"


def host_title(host: str) -> str:
    for node in CFG["nodes"]:
        if node.get("host") == host:
            return node_title(node)
    return "—"


def proto_label(proto: str) -> str:
    return PROTO_LABELS.get(proto, "Другой")


def subscription_menu() -> str:
    xhttp = [country_name(node) for node in exit_nodes() if node.get("xhttp")]
    front_bits = []
    for node in front_nodes():
        ports = node.get("front_ports") or {}
        port_txt = ", ".join(
            "%s→%s" % (str(exit_id).upper(), ports[exit_id])
            for exit_id in ("de", "fi", "bg")
            if exit_id in ports
        )
        front_bits.append(
            "%s (%s; %s)"
            % (country_name(node), node.get("host") or "?", port_txt or "порты не заданы")
        )
    items = (
        "Happ и INCY — 7 строк: «Автоматический выбор», по строке на страну "
        "(сама выбирает Reality, запасной и «сообщения») и 3 строки Hy2.",
        "Hiddify, v2rayNG, v2rayN и другие — 9 строк: по стране Reality, Hy2 и «сообщения».",
        "Приложение K-Pax / X-Plm — Reality + запасные по странам; РФ-фронт в подписке скрыт "
        "(те же названия стран, non-443) и берётся как spare при обрыве прямого EU.",
        "XHTTP вместо gRPC и WebSocket (только Happ и INCY): "
        + (", ".join(xhttp) if xhttp else "пока нигде") + ".",
        "РФ-фронт в config: "
        + (", ".join(front_bits) if front_bits else "выключен") + ".",
    )
    return "<ul>%s</ul>" % "".join("<li>%s</li>" % html.escape(item) for item in items)


def admin_nav(current: str) -> str:
    items = [
        ("/admin/stats", "Статистика", "stats"),
        ("/admin/users", "Участники", "users"),
        ("/admin/client-events", "События", "client-events"),
        ("/admin/partners", "Партнёры", "partners"),
        ("/admin/promos", "Промокоды", "promos"),
        ("/admin/2fa", "Защита входа", "2fa"),
    ]
    if is_xplm():
        items.insert(1, ("/admin/cash", "Касса", "cash"))
    if not brand()["admin_totp"]:
        items = [item for item in items if item[2] != "2fa"]
    links = []
    for href, label, key in items:
        mark = " class='on'" if key == current else ""
        links.append("<a href='%s'%s>%s</a>" % (href, mark, label))
    nav = "<nav class='adminnav'>%s</nav>" % "".join(links)
    if brand()["admin_totp"] and current != "2fa" and not totp_secret():
        nav += (
            "<p class='err'>Вход в админку защищён только паролем. "
            "<a href='/admin/2fa'>Подключите код из приложения</a>.</p>"
        )
    return nav


def totp_page(error: str = "", notice: str = "") -> tuple[int, str, bytes]:
    err = "<p class='err'>%s</p>" % html.escape(error) if error else ""
    note = "<p class='ok'>%s</p>" % html.escape(notice) if notice else ""
    if totp_secret():
        body = """
{nav}
<h1>Защита входа</h1>
{note}{err}
<p class="ok">Включена: при входе нужны логин, пароль и 6-значный код из приложения.</p>
{reset}
{brand_admin}
""".format(
            nav=admin_nav("2fa"),
            note=note,
            err=err,
            reset=TOTP_RESET_XPLM if is_xplm() else TOTP_RESET_KPAX,
            brand_admin="" if is_xplm() else brand_admin_form(),
        )
        return page("K-Pax — защита входа", body, 400 if error else 200, wide=True)
    secret = admin_setting("totp_pending")
    if not secret:
        secret = new_totp_secret()
        set_admin_setting("totp_pending", secret)
    grouped = " ".join(secret[i : i + 4] for i in range(0, len(secret), 4))
    body = """
{nav}
<h1>Защита входа</h1>
{note}{err}
<p class="lead">Сейчас вход только по логину и паролю. Добавьте второй ключ — код из приложения на телефоне.</p>
<ol>
<li>Установите «Яндекс Ключ», Google Authenticator или любое приложение с кодами TOTP.</li>
<li>Добавьте аккаунт: отсканируйте QR или введите ключ вручную.</li>
<li>Введите 6 цифр из приложения ниже.</li>
</ol>
<div class="qrwrap" style="max-width:14rem">{qr}</div>
<p class="muted">Ключ для ручного ввода:</p>
<p><code>{grouped}</code></p>
<form class="extend" method="post" action="/admin/2fa">
<div class="row"><input name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="7" required placeholder="123456" style="width:8rem">
<button type="submit">Включить</button></div>
</form>
<p class="muted">После включения все текущие сессии админки завершатся, войти нужно будет заново: логин, пароль и код.</p>
{brand_admin}
""".format(
        nav=admin_nav("2fa"),
        note=note,
        err=err,
        qr=qr_svg(totp_uri(secret)),
        grouped=html.escape(grouped),
        brand_admin="" if is_xplm() else brand_admin_form(),
    )
    return page("K-Pax — защита входа", body, 400 if error else 200, wide=True)


TOTP_RESET_KPAX = """<p class="muted">Если телефон с приложением потерян, сбросьте защиту на сервере командой
<code>cd /opt/k-pax &amp;&amp; python3 panel.py reset-2fa</code> и подключите заново.
Для админки X-Plm: <code>python3 panel.py reset-2fa xplm</code>.
Сброс завершает все открытые сессии админки.</p>"""

TOTP_RESET_XPLM = """<p class="muted">Если телефон с приложением потерян, попросите администратора сервиса сбросить защиту, затем подключите её заново.</p>"""


def brand_admin_form() -> str:
    with brand_context("xplm"):
        current = admin_setting("admin_user")
    state = (
        "Вход настроен: логин <code>%s</code>, вход по логину и паролю." % html.escape(current)
        if current
        else "Вход ещё не настроен."
    )
    return """
<h2>Админка X-Plm</h2>
<p class="muted">Только просмотр пользователей X-Plm. {state} Новый пароль завершит все сессии админки X-Plm.</p>
<form class="extend" method="post" action="/admin/brand-admin">
<input type="hidden" name="brand" value="xplm">
<div class="row">
<input name="username" autocomplete="off" required maxlength="32" placeholder="логин" style="width:12rem">
<input name="password" type="password" autocomplete="new-password" required minlength="12" placeholder="пароль от 12 символов" style="width:16rem">
<button type="submit">Сохранить</button>
</div>
</form>
""".format(state=state)


def online_user_count(now: float) -> int:
    count = 0
    for slots in DEVICE_SEEN.values():
        if any(now - slot["last"] <= DEVICE_TTL for slot in slots.values()):
            count += 1
    return count


def ingest_report(host: str, flows: list[dict], now: float) -> tuple[list[tuple], list[tuple], int | None, int]:
    """Update live speeds. Caller holds DEVICE_LOCK. Returns usage, node minutes, online minute, online count."""
    global ONLINE_MINUTE_SEEN
    seen_ids: set[str] = set()
    usage: list[tuple] = []
    per_user: dict[str, dict] = {}
    for flow in flows:
        # Xray totals arrive under the same id from every node; deltas must be taken per node.
        fid = host + "|" + flow["id"]
        seen_ids.add(fid)
        prev = FLOW_SEEN.get(fid)
        up = flow["up"]
        down = flow["down"]
        if prev is None:
            d_up = d_down = 0
        else:
            d_up = up - prev[0] if up >= prev[0] else up
            d_down = down - prev[1] if down >= prev[1] else down
        FLOW_SEEN[fid] = (up, down, host)
        if d_up or d_down:
            usage.append((flow["user"], flow["proto"], d_up, d_down))
        slot = per_user.setdefault(flow["user"], {"up": 0, "down": 0, "proto": flow["proto"], "score": -1})
        slot["up"] += d_up
        slot["down"] += d_down
        if d_up + d_down >= slot["score"]:
            slot["proto"] = flow["proto"]
            slot["score"] = d_up + d_down
    for fid, triple in list(FLOW_SEEN.items()):
        if triple[2] == host and fid not in seen_ids:
            del FLOW_SEEN[fid]
    elapsed = now - HOST_REPORT_AT[host] if host in HOST_REPORT_AT else 0.0
    HOST_REPORT_AT[host] = now
    speed_elapsed = elapsed if 0 < elapsed <= 30 else 0.0
    for nodes in list(LIVE_NODES.values()):
        nodes.pop(host, None)
    empty = [user for user, nodes in LIVE_NODES.items() if not nodes]
    for user in empty:
        del LIVE_NODES[user]
    for user, slot in per_user.items():
        # Zero-delta flow rows (stale Xray totals) must not keep a user "online".
        if not (slot["up"] or slot["down"]):
            continue
        LIVE_NODES.setdefault(user, {})[host] = {
            "seen": now,
            "up_bps": (slot["up"] / speed_elapsed) if speed_elapsed else 0.0,
            "down_bps": (slot["down"] / speed_elapsed) if speed_elapsed else 0.0,
            "proto": slot["proto"],
        }
    minute = int(now // 60)
    node_rows: list[tuple] = []
    sample = NODE_HEALTH.get(host)
    if sample and HOST_MINUTE.get(host) != minute:
        HOST_MINUTE[host] = minute
        node_rows.append(
            (minute, host, sample["load"], sample["cores"], sample["rx"], sample["tx"], sample["online"])
        )
    online_now = online_user_count(now)
    online_minute = None
    if ONLINE_MINUTE_SEEN != minute:
        ONLINE_MINUTE_SEEN = minute
        online_minute = minute
    return usage, node_rows, online_minute, online_now


def save_usage(usage: list[tuple], node_rows: list[tuple], online_minute: int | None, online_now: int) -> None:
    if not usage and not node_rows and online_minute is None:
        return
    month = month_key()
    cutoff = int(time.time() // 60) - 40 * 24 * 60
    with LOCK:
        conn = db()
        for user, proto, up, down in usage:
            conn.execute(
                """
                INSERT INTO usage_month(user_key, month, proto, bytes_up, bytes_down)
                VALUES(?, ?, ?, ?, ?)
                ON CONFLICT(user_key, month, proto) DO UPDATE SET
                    bytes_up = bytes_up + excluded.bytes_up,
                    bytes_down = bytes_down + excluded.bytes_down
                """,
                (user, month, proto, up, down),
            )
        seen_at = now_ts()
        for user in {item[0] for item in usage if item[2] + item[3] > 0}:
            conn.execute(
                """
                INSERT INTO user_seen(user_key, first_seen, last_seen) VALUES(?, ?, ?)
                ON CONFLICT(user_key) DO UPDATE SET last_seen = excluded.last_seen
                """,
                (user, seen_at, seen_at),
            )
        for row in node_rows:
            conn.execute(
                """
                INSERT OR REPLACE INTO node_minute(minute, host, load, cores, rx, tx, online)
                VALUES(?, ?, ?, ?, ?, ?, ?)
                """,
                row,
            )
        if online_minute is not None:
            conn.execute(
                "INSERT OR REPLACE INTO online_minute(minute, users) VALUES(?, ?)",
                (online_minute, online_now),
            )
        conn.execute("DELETE FROM node_minute WHERE minute < ?", (cutoff,))
        conn.execute("DELETE FROM online_minute WHERE minute < ?", (cutoff,))
        conn.commit()
        conn.close()


def live_people() -> dict[str, dict]:
    now = time.time()
    with DEVICE_LOCK:
        raw = {user: {host: dict(item) for host, item in nodes.items()} for user, nodes in LIVE_NODES.items()}
        devices = {
            user: len(slots)
            for user, slots in DEVICE_SEEN.items()
            if any(now - slot["last"] <= DEVICE_TTL for slot in slots.values())
        }
    found: dict[str, dict] = {}
    # Online = active session slots (DEVICE_SEEN), same source as peak / per-node cards.
    # LIVE_NODES only supplies speed and protocol for those sessions.
    for user, device_count in devices.items():
        fresh = {host: item for host, item in raw.get(user, {}).items() if now - item["seen"] <= 30}
        up = sum(item["up_bps"] for item in fresh.values())
        down = sum(item["down_bps"] for item in fresh.values())
        if fresh:
            host = max(fresh, key=lambda name: fresh[name]["down_bps"] + fresh[name]["up_bps"])
            proto = fresh[host]["proto"]
        else:
            host = ""
            proto = ""
        found[user] = {
            "online": True,
            "up_bps": up,
            "down_bps": down,
            "speed": max(up, down),
            "proto": proto,
            "host": host,
            "devices": device_count,
        }
    return found


def account_totals(only_brand: str = "") -> dict[str, int]:
    now = now_ts()
    day = msk_day_start(now)
    month = msk_month_start(now)
    week = 7 * 86400
    where = "WHERE brand=?" if only_brand else ""
    extra = (only_brand,) if only_brand else ()
    conn = db()
    row = conn.execute(
        """
        SELECT
            SUM(CASE WHEN active=1 AND expires_at>? THEN 1 ELSE 0 END),
            COUNT(*),
            SUM(CASE WHEN created_at>=? THEN 1 ELSE 0 END),
            SUM(CASE WHEN created_at>=? THEN 1 ELSE 0 END),
            SUM(CASE WHEN active=0 AND expires_at<=? AND expires_at>=? THEN 1 ELSE 0 END),
            SUM(CASE WHEN active=0 AND expires_at<=? AND expires_at>=? THEN 1 ELSE 0 END)
        FROM users
        """
        + where,
        (now, month, day, now - week, month - week, now - week, day - week) + extra,
    ).fetchone()
    paid = conn.execute(
        """
        SELECT
            COUNT(DISTINCT p.user_id),
            COUNT(DISTINCT CASE WHEN p.updated_at>=? AND p.updated_at<=? THEN p.user_id END)
        FROM platega_invoices p
        """
        + ("JOIN users u ON u.id=p.user_id WHERE p.status='CONFIRMED' AND u.brand=?" if only_brand else "WHERE p.status='CONFIRMED'"),
        (month, now) + extra,
    ).fetchone()
    manual = conn.execute(
        """
        SELECT
            COUNT(DISTINCT p.user_id),
            COUNT(DISTINCT CASE WHEN p.created_at>=? AND p.created_at<=? THEN p.user_id END)
        FROM payments p
        """
        + ("JOIN users u ON u.id=p.user_id WHERE p.source='admin' AND u.brand=?" if only_brand else "WHERE p.source='admin'"),
        (month, now) + extra,
    ).fetchone()
    # Node traffic is keyed by "kp-" + the first 8 hex digits of the uuid.
    key_sql = "'kp-' || substr(replace(u.uuid, '-', ''), 1, 8)"
    brand_sql = " AND u.brand=?" if only_brand else ""
    seen = conn.execute(
        """
        SELECT
            SUM(CASE WHEN s.last_seen>=? THEN 1 ELSE 0 END),
            SUM(CASE WHEN s.last_seen>=? THEN 1 ELSE 0 END)
        FROM users u JOIN user_seen s ON s.user_key = %s
        WHERE u.verified=1%s
        """ % (key_sql, brand_sql),
        (now - 86400, now - week) + extra,
    ).fetchone()
    never = conn.execute(
        """
        SELECT COUNT(*) FROM users u
        WHERE u.verified=1 AND u.active=1 AND u.expires_at>?%s
          AND NOT EXISTS (SELECT 1 FROM user_seen s WHERE s.user_key = %s)
          AND NOT EXISTS (SELECT 1 FROM usage_month m WHERE m.user_key = %s AND m.bytes_up + m.bytes_down > 0)
        """ % (brand_sql, key_sql, key_sql),
        (now,) + extra,
    ).fetchone()
    conn.close()
    keys = ("active", "registered", "joined_month", "joined_day", "left_month", "left_day")
    totals = {key: int(row[index] or 0) for index, key in enumerate(keys)}
    totals["paid_total"] = int(paid[0] or 0)
    totals["paid_month"] = int(paid[1] or 0)
    totals["manual_total"] = int(manual[0] or 0)
    totals["manual_month"] = int(manual[1] or 0)
    totals["seen_day"] = int(seen[0] or 0)
    totals["seen_week"] = int(seen[1] or 0)
    totals["never"] = int(never[0] or 0)
    return totals


def activity_cards(totals: dict[str, int]) -> str:
    return card("Были в сети за 24 ч", str(totals["seen_day"]), "за 7 дней %d" % totals["seen_week"]) + card(
        "Ни разу не подключались", str(totals["never"]), "из %d активных" % totals["active"]
    )


def manual_note(count: int, base: str = "") -> str:
    if not count:
        return base
    note = "ещё %d продлено вручную" % count
    return "%s, %s" % (base, note) if base else note


def usage_by_user(month: str) -> dict[str, tuple[int, int]]:
    conn = db()
    rows = conn.execute(
        """
        SELECT user_key, SUM(bytes_up), SUM(bytes_down)
        FROM usage_month WHERE month=? GROUP BY user_key
        """,
        (month,),
    ).fetchall()
    conn.close()
    return {row[0]: (int(row[1] or 0), int(row[2] or 0)) for row in rows}


def usage_by_proto(month: str) -> list[tuple[str, int]]:
    conn = db()
    rows = conn.execute(
        """
        SELECT proto, SUM(bytes_up + bytes_down)
        FROM usage_month WHERE month=? GROUP BY proto ORDER BY 2 DESC
        """,
        (month,),
    ).fetchall()
    conn.close()
    return [(str(row[0]), int(row[1] or 0)) for row in rows]


def peak_today() -> dict[str, object]:
    start = msk_day_start() // 60
    conn = db()
    nodes = conn.execute(
        "SELECT host, load, cores, rx, tx, online FROM node_minute WHERE minute>=?",
        (start,),
    ).fetchall()
    online = conn.execute(
        "SELECT MAX(users) FROM online_minute WHERE minute>=?",
        (start,),
    ).fetchone()
    conn.close()
    peak_speed = None
    peak_load = None
    peak_node_online = 0
    for row in nodes:
        speed = max(float(row["rx"]), float(row["tx"]))
        if peak_speed is None or speed > peak_speed[0]:
            peak_speed = (speed, row["host"])
        ratio = float(row["load"]) / max(1, int(row["cores"]))
        if peak_load is None or ratio > peak_load[0]:
            peak_load = (ratio, float(row["load"]), int(row["cores"]), row["host"])
        peak_node_online = max(peak_node_online, int(row["online"]))
    return {
        "speed": peak_speed,
        "load": peak_load,
        "node_online": peak_node_online,
        "users": int(online[0] or 0) if online else 0,
        "samples": len(nodes),
    }


def card(title: str, figure: str, note: str = "") -> str:
    extra = "<p class='muted'>%s</p>" % html.escape(note) if note else ""
    return (
        "<article class='health'><p class='muted'>%s</p><p><span class='figure'>%s</span></p>%s</article>"
        % (html.escape(title), html.escape(figure), extra)
    )


def rub_text(amount: int | float) -> str:
    value = int(round(float(amount)))
    return "₽ %s" % format(value, ",").replace(",", " ")


def cash_day_key(ts: int) -> str:
    return datetime.fromtimestamp(int(ts), MSK).strftime("%Y-%m-%d")


def cash_day_label(day: str) -> str:
    stamp = datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=MSK)
    return stamp.strftime("%d.%m")


def parse_cash_period(query: str = "") -> tuple[int, int, str, str, str]:
    """Return start/end unix bounds (MSK days), preset key, and YYYY-MM-DD form values."""
    qs = parse_qs(query)
    preset = (qs.get("range") or ["7"])[0].strip().lower()
    if preset not in ("7", "30", "custom"):
        preset = "7"
    today = msk_day_start()
    end = today + 86400 - 1
    if preset == "30":
        start = today - 29 * 86400
    elif preset == "custom":
        raw_from = (qs.get("from") or [""])[0].strip()
        raw_to = (qs.get("to") or [""])[0].strip()
        try:
            start_dt = datetime.strptime(raw_from, "%Y-%m-%d").replace(tzinfo=MSK)
            end_dt = datetime.strptime(raw_to, "%Y-%m-%d").replace(tzinfo=MSK)
            start = int(start_dt.timestamp())
            end = int(end_dt.timestamp()) + 86400 - 1
            if end < start:
                start, end = end - 86399, start + 86399
            if end - start > 366 * 86400:
                start = end - 365 * 86400 + 1
                start = msk_day_start(start)
        except ValueError:
            preset = "7"
            start = today - 6 * 86400
    else:
        start = today - 6 * 86400
    return (
        start,
        end,
        preset,
        datetime.fromtimestamp(start, MSK).strftime("%Y-%m-%d"),
        datetime.fromtimestamp(end, MSK).strftime("%Y-%m-%d"),
    )


def xplm_cash_metrics(start: int, end: int) -> dict:
    price = pay_amount("xplm")
    conn = db()
    paid_rows = conn.execute(
        """
        SELECT i.amount, i.updated_at
        FROM platega_invoices i
        JOIN users u ON u.id = i.user_id
        WHERE u.brand='xplm' AND i.status='CONFIRMED'
          AND i.currency='RUB' AND i.updated_at BETWEEN ? AND ?
        ORDER BY i.updated_at
        """,
        (start, end),
    ).fetchall()
    charge_rows = conn.execute(
        """
        SELECT i.amount, i.updated_at
        FROM platega_invoices i
        JOIN users u ON u.id = i.user_id
        WHERE u.brand='xplm' AND i.status='CHARGEBACKED'
          AND i.currency='RUB' AND i.updated_at BETWEEN ? AND ?
        ORDER BY i.updated_at
        """,
        (start, end),
    ).fetchall()
    manual_rows = conn.execute(
        """
        SELECT amount, created_at
        FROM cash_refunds
        WHERE brand='xplm' AND created_at BETWEEN ? AND ?
        ORDER BY created_at
        """,
        (start, end),
    ).fetchall()
    lifetime = conn.execute(
        """
        SELECT COALESCE(SUM(CASE WHEN i.amount > 0 THEN i.amount ELSE ? END), 0), COUNT(*)
        FROM platega_invoices i
        JOIN users u ON u.id = i.user_id
        WHERE u.brand='xplm' AND i.status='CONFIRMED' AND i.currency='RUB'
        """,
        (price,),
    ).fetchone()
    conn.close()

    days: list[str] = []
    cursor = msk_day_start(start)
    last = msk_day_start(end)
    while cursor <= last:
        days.append(cash_day_key(cursor))
        cursor += 86400
    turnover_by_day = {day: 0 for day in days}
    refund_by_day = {day: 0 for day in days}
    turnover = 0
    payments = 0
    for amount, stamp in paid_rows:
        value = int(amount) if int(amount) > 0 else price
        day = cash_day_key(int(stamp))
        if day in turnover_by_day:
            turnover_by_day[day] += value
        turnover += value
        payments += 1
    refunds = 0
    chargebacks = 0
    for amount, stamp in charge_rows:
        value = int(amount) if int(amount) > 0 else price
        day = cash_day_key(int(stamp))
        if day in refund_by_day:
            refund_by_day[day] += value
        refunds += value
        chargebacks += 1
    manual_count = 0
    for amount, stamp in manual_rows:
        value = max(0, int(amount))
        day = cash_day_key(int(stamp))
        if day in refund_by_day:
            refund_by_day[day] += value
        refunds += value
        manual_count += 1
    return {
        "price": price,
        "turnover": turnover,
        "refunds": refunds,
        "net": turnover - refunds,
        "payments": payments,
        "chargebacks": chargebacks,
        "manual_refunds": manual_count,
        "lifetime_turnover": int(lifetime[0] or 0),
        "lifetime_payments": int(lifetime[1] or 0),
        "days": days,
        "turnover_series": [turnover_by_day[day] for day in days],
        "refund_series": [refund_by_day[day] for day in days],
    }


def cash_chart_svg(days: list[str], turnover: list[int], refunds: list[int]) -> str:
    width, height = 920, 168
    pad_l, pad_r, pad_t, pad_b = 40, 16, 12, 28
    plot_w = width - pad_l - pad_r
    plot_h = height - pad_t - pad_b
    peak = max([1] + turnover + refunds)
    def point(index: int, value: int) -> tuple[float, float]:
        if len(days) <= 1:
            x = pad_l + plot_w / 2
        else:
            x = pad_l + plot_w * index / (len(days) - 1)
        y = pad_t + plot_h * (1 - (value / peak))
        return x, y

    def polyline(values: list[int]) -> str:
        if not values:
            return ""
        return " ".join("%.1f,%.1f" % point(i, value) for i, value in enumerate(values))

    grid = []
    for step in range(3):
        y = pad_t + plot_h * step / 2
        label = int(round(peak * (1 - step / 2)))
        grid.append(
            "<line x1='%d' y1='%.1f' x2='%d' y2='%.1f' stroke='#1a3555' stroke-width='1'/>"
            "<text x='6' y='%.1f' fill='#7f96b0' font-size='10'>%s</text>"
            % (pad_l, y, width - pad_r, y, y + 3, label)
        )
    labels = []
    if days:
        step = max(1, len(days) // 7)
        for index, day in enumerate(days):
            if index % step != 0 and index != len(days) - 1:
                continue
            x, _ = point(index, 0)
            labels.append(
                "<text x='%.1f' y='%d' text-anchor='middle' fill='#7f96b0' font-size='10'>%s</text>"
                % (x, height - 8, html.escape(cash_day_label(day)))
            )
    turn_pts = polyline(turnover)
    ref_pts = polyline(refunds)
    return """
<svg class="cash-chart" viewBox="0 0 {w} {h}" role="img" aria-label="Оборот и возвраты по дням">
{grid}
<polyline fill="none" stroke="#4f8cff" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" points="{turn}"></polyline>
<polyline fill="none" stroke="#ff5d7a" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" points="{ref}"></polyline>
{labels}
</svg>
""".format(w=width, h=height, grid="".join(grid), turn=turn_pts, ref=ref_pts, labels="".join(labels))


def xplm_cash_page(query: str = "", notice: str = "", error: str = "") -> tuple[int, str, bytes]:
    if not is_xplm():
        return stats_page(notice=notice, error=error)
    start, end, preset, from_day, to_day = parse_cash_period(query)
    metrics = xplm_cash_metrics(start, end)
    banner = ""
    if notice:
        banner += "<p class='ok'>%s</p>" % html.escape(notice)
    if error:
        banner += "<p class='err'>%s</p>" % html.escape(error)
    def range_link(key: str, label: str) -> str:
        mark = " class='on'" if preset == key else ""
        return "<a href='/admin/cash?range=%s'%s>%s</a>" % (key, mark, label)

    body = """
<style>
main.xp-admin:has(.cash-screen){{padding-bottom:8px}}
main.xp-admin:has(.cash-screen) .xp-header{{min-height:64px;margin-bottom:6px}}
main.xp-admin:has(.cash-screen) .adminnav{{margin-bottom:8px;gap:8px 16px}}
.cash-screen{{display:flex;flex-direction:column;gap:8px;min-height:0}}
.cash-screen .toolbar{{margin:0;gap:10px;align-items:baseline}}
.cash-screen .toolbar h1{{font-size:22px;margin:0;line-height:1.1}}
.cash-screen .cash-lead{{margin:0;color:var(--ink-2);font-size:12px;line-height:1.35}}
.cash-screen .cash-filters{{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:0}}
.cash-screen .cash-filters a,.cash-screen .cash-filters button{{
  display:inline-flex;align-items:center;justify-content:center;min-height:32px;padding:6px 12px;border-radius:999px;
  border:1px solid #2a4d73;background:#071628;color:#d7e6f7;text-decoration:none;font-size:12px
}}
.cash-screen .cash-filters a.on{{background:#1a4d8c;border-color:#4f8cff;color:#fff}}
.cash-screen .cash-filters form{{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:0}}
.cash-screen .cash-filters label{{display:inline-flex;align-items:center;gap:6px;font-size:12px;color:#9eb2c9}}
.cash-screen .cash-filters input[type=date]{{min-height:32px;padding:4px 8px;border-radius:8px;border:1px solid #2a4d73;background:#03111f;color:#e8f2ff;font-size:12px}}
.cash-screen .cash-cards{{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin:0}}
.cash-screen .cash-card{{padding:12px 14px;border-radius:14px;border:1px solid #3a2b74;background:linear-gradient(160deg,#2a1760,#1a0f3d 55%,#120a2c);box-shadow:inset 0 1px 0 #6d4dff33}}
.cash-screen .cash-card .muted{{color:#b7a8e8;margin:0 0 4px;font-size:11px}}
.cash-screen .cash-card .figure{{font-size:22px;font-weight:800;color:#f4efff;letter-spacing:-.02em;line-height:1.15}}
.cash-screen .cash-card .note{{margin:4px 0 0;color:#9b8cc8;font-size:11px}}
.cash-screen .cash-panel{{padding:12px 14px;border:1px solid #1d3b5d;border-radius:14px;background:linear-gradient(180deg,#07182c,#04101f);margin:0}}
.cash-screen .cash-legend{{display:flex;flex-wrap:wrap;gap:12px;margin:0 0 6px;color:#9eb2c9;font-size:12px}}
.cash-screen .cash-legend span{{display:inline-flex;align-items:center;gap:6px}}
.cash-screen .cash-legend i{{width:8px;height:8px;border-radius:50%;display:inline-block}}
.cash-screen .cash-chart{{width:100%;max-height:min(28vh,180px);height:auto;display:block}}
.cash-screen .cash-refund{{display:flex;flex-wrap:wrap;gap:10px 16px;align-items:end;justify-content:space-between}}
.cash-screen .cash-refund .cash-refund-copy{{flex:1 1 180px;min-width:0}}
.cash-screen .cash-refund h2{{font-size:14px;margin:0 0 2px}}
.cash-screen .cash-refund .muted{{margin:0;font-size:11px}}
.cash-screen .cash-refund form{{margin:0;padding:0;border:0;background:transparent;box-shadow:none}}
.cash-screen .cash-refund .row{{display:flex;flex-wrap:wrap;gap:8px;align-items:end}}
.cash-screen .cash-refund label{{display:flex;flex-direction:column;gap:4px;font-size:11px;color:#9eb2c9}}
.cash-screen .cash-refund input{{min-height:32px;padding:6px 10px;border-radius:8px;border:1px solid #2a4d73;background:#03111f;color:#e8f2ff;font-size:12px;width:7.5rem}}
.cash-screen .cash-refund input[name=note]{{width:11rem}}
.cash-screen .cash-refund button{{min-height:32px;padding:6px 12px;font-size:12px}}
.cash-screen .ok,.cash-screen .err{{margin:0;padding:8px 10px;font-size:12px}}
@media(max-width:900px){{.cash-screen .cash-cards{{grid-template-columns:1fr 1fr}}.cash-screen .cash-chart{{max-height:200px}}}}
@media(max-width:560px){{.cash-screen .cash-cards{{grid-template-columns:1fr}}}}
</style>
{nav}
<div class="cash-screen">
<div class="toolbar">
<h1>Касса</h1>
<a href="/admin/logout">Выйти</a>
</div>
<p class="cash-lead">Оборот X-Plm по подтверждённым оплатам {price} ₽. Только рубли, без внешнего API.</p>
{banner}
<div class="cash-filters">
{link7}{link30}
<form method="get" action="/admin/cash">
<input type="hidden" name="range" value="custom">
<label>С <input type="date" name="from" value="{from_day}" required></label>
<label>По <input type="date" name="to" value="{to_day}" required></label>
<button type="submit">Период</button>
</form>
</div>
<div class="cash-cards">
<article class="cash-card"><p class="muted">Оборот за период</p><p class="figure">{turnover}</p><p class="note">{payments} платежей</p></article>
<article class="cash-card"><p class="muted">Возвраты</p><p class="figure">{refunds}</p><p class="note">чарджбек {chargebacks}, вручную {manual}</p></article>
<article class="cash-card"><p class="muted">Чистыми</p><p class="figure">{net}</p><p class="note">оборот минус возвраты</p></article>
<article class="cash-card"><p class="muted">Всего за всё время</p><p class="figure">{lifetime}</p><p class="note">{lifetime_n} платежей</p></article>
</div>
<section class="cash-panel">
<div class="cash-legend">
<span><i style="background:#4f8cff"></i>Оборот</span>
<span><i style="background:#ff5d7a"></i>Возвраты</span>
<span>{from_day} — {to_day}</span>
</div>
{chart}
</section>
<section class="cash-panel cash-refund">
<div class="cash-refund-copy">
<h2>Ручной возврат</h2>
<p class="muted">Без счёта Platega. По умолчанию {price} ₽.</p>
</div>
<form class="extend" method="post" action="/admin/cash/refund">
<div class="row">
<label>Сумма, ₽ <input name="amount" type="number" min="1" max="100000" step="1" value="{price}" required></label>
<label>Комментарий <input name="note" maxlength="120" placeholder="по заявке / вручную"></label>
<button type="submit">Записать</button>
</div>
</form>
</section>
</div>
""".format(
        nav=admin_nav("cash"),
        banner=banner,
        price=metrics["price"],
        link7=range_link("7", "7 дней"),
        link30=range_link("30", "30 дней"),
        from_day=html.escape(from_day),
        to_day=html.escape(to_day),
        turnover=html.escape(rub_text(metrics["turnover"])),
        payments=metrics["payments"],
        refunds=html.escape(rub_text(metrics["refunds"])),
        chargebacks=metrics["chargebacks"],
        manual=metrics["manual_refunds"],
        net=html.escape(rub_text(metrics["net"])),
        lifetime=html.escape(rub_text(metrics["lifetime_turnover"])),
        lifetime_n=metrics["lifetime_payments"],
        chart=cash_chart_svg(metrics["days"], metrics["turnover_series"], metrics["refund_series"]),
    )
    return page("X-Plm — касса", body, 400 if error else 200, wide=True)


def xplm_stats_page(notice: str = "", error: str = "") -> tuple[int, str, bytes]:
    totals = account_totals("xplm")
    conn = db()
    keys = {user_key(row[0]) for row in conn.execute("SELECT uuid FROM users WHERE brand='xplm'")}
    conn.close()
    people = live_people()
    online = sum(1 for key, item in people.items() if key in keys and item["online"])
    banner = ""
    if notice:
        banner += "<p class='ok'>%s</p>" % html.escape(notice)
    if error:
        banner += "<p class='err'>%s</p>" % html.escape(error)
    body = """
{nav}
<div class="toolbar">
<h1>Статистика</h1>
<a href="/admin/logout">Выйти</a>
</div>
<p class="lead">Только просмотр участников.</p>
<div class="healthrow">
{online}
{active}
{joined}
{left}
{paid}
{paid_month}
{activity}
</div>
{banner}
""".format(
        nav=admin_nav("stats"),
        activity=activity_cards(totals),
        online=card("Онлайн", str(online)),
        active=card(
            "Активные аккаунты",
            "%d / %d" % (totals["active"], totals["registered"]),
            "активные / зарегистрированные",
        ),
        joined=card("Пришло", str(totals["joined_month"]), "сегодня %d" % totals["joined_day"]),
        left=card("Ушло", str(totals["left_month"]), "сегодня %d, неделю без оплаты" % totals["left_day"]),
        paid=card("Оплаченные", str(totals["paid_total"]), manual_note(totals["manual_total"], "всего")),
        paid_month=card("Оплачено за месяц", str(totals["paid_month"]), manual_note(totals["manual_month"])),
        banner=banner,
    )
    return page("K-Pax — статистика", body, 400 if error else 200, wide=True)


def stats_page(notice: str = "", error: str = "") -> tuple[int, str, bytes]:
    if is_xplm():
        return xplm_stats_page(notice=notice, error=error)
    totals = account_totals()
    people = live_people()
    online = sum(1 for item in people.values() if item["online"])
    month = month_key()
    protos = usage_by_proto(month)
    peak = peak_today()
    banner = ""
    if notice:
        banner += "<p class='ok'>%s</p>" % html.escape(notice)
    if error:
        banner += "<p class='err'>%s</p>" % html.escape(error)
    now = time.time()
    with DEVICE_LOCK:
        health = {host: dict(sample) for host, sample in NODE_HEALTH.items()}
    busiest = None
    current_rx = 0.0
    current_tx = 0.0
    for node in CFG["nodes"]:
        if is_front_node(node):
            continue
        sample = health.get(node["host"])
        if not sample or now - sample["seen"] > 30:
            continue
        speed = max(sample["rx"], sample["tx"])
        current_rx += sample["rx"]
        current_tx += sample["tx"]
        if busiest is None or speed > busiest[0]:
            busiest = (speed, node_title(node), sample["load"], sample["cores"], sample["online"])
    proto_now: dict[str, int] = {}
    for item in people.values():
        if item["online"] and item["proto"]:
            proto_now[item["proto"]] = proto_now.get(item["proto"], 0) + 1
    if protos:
        total_bytes = sum(amount for _, amount in protos) or 1
        month_proto = "".join(
            card(
                proto_label(proto),
                bytes_text(amount),
                "%s%% за месяц" % int(round(100 * amount / total_bytes)),
            )
            for proto, amount in protos
        )
    else:
        month_proto = card("Трафик", "—", "за этот месяц ещё нет")
    if proto_now:
        now_proto = "".join(
            card(proto_label(proto), str(count), "онлайн сейчас")
            for proto, count in sorted(proto_now.items(), key=lambda pair: (-pair[1], pair[0]))
        )
    else:
        now_proto = card("Сейчас", "0", "никто не подключён")
    if peak["speed"]:
        peak_speed = "%s, %s" % (mbps_text(peak["speed"][0]), host_title(peak["speed"][1]))
    else:
        peak_speed = "ещё копится"
    if peak["load"]:
        peak_cpu = "%s из %s, %s" % (
            ("%.2f" % peak["load"][1]).replace(".", ","),
            peak["load"][2],
            host_title(peak["load"][3]),
        )
    else:
        peak_cpu = "ещё копится"
    peak_users = str(peak["users"]) if peak["samples"] else "ещё копится"
    busy_note = "нет свежих данных"
    if busiest:
        busy_note = "%s, %s онлайн, процессор %s из %s" % (
            mbps_text(busiest[0]),
            busiest[4],
            ("%.2f" % busiest[2]).replace(".", ","),
            busiest[3],
        )
    body = """
{nav}
<div class="toolbar">
<h1>Статистика</h1>
<a href="/admin/logout">Выйти</a>
</div>
<p class="lead">Серверы сейчас, люди и канал за сегодня. Трафик по людям считается с момента включения этой страницы.</p>
{health}
<div class="healthrow">
{online}
{active}
{joined}
{left}
{paid}
{paid_month}
{activity}
{peak_users}
{peak_speed}
{peak_cpu}
{busy}
{rx}
{tx}
</div>
<h2>Протоколы</h2>
<p class="statline">Спрос за месяц по трафику</p>
<div class="healthrow">{month_proto}</div>
<p class="statline">Кто подключён сейчас</p>
<div class="healthrow">{now_proto}</div>
<h2>Состав ссылки</h2>
<p class="statline">Одна ссылка, но каждое приложение получает свой набор строк</p>
{menu}
{banner}
""".format(
        nav=admin_nav("stats"),
        health=health_cards(),
        activity=activity_cards(totals),
        online=card("Онлайн", str(online)),
        active=card(
            "Активные аккаунты",
            "%d / %d" % (totals["active"], totals["registered"]),
            "активные / зарегистрированные",
        ),
        joined=card("Пришло", str(totals["joined_month"]), "сегодня %d" % totals["joined_day"]),
        left=card("Ушло", str(totals["left_month"]), "сегодня %d, неделю без оплаты" % totals["left_day"]),
        paid=card("Оплаченные", str(totals["paid_total"]), manual_note(totals["manual_total"], "всего")),
        paid_month=card("Оплачено за месяц", str(totals["paid_month"]), manual_note(totals["manual_month"])),
        peak_users=card("Пик онлайн сегодня", peak_users),
        peak_speed=card("Пик канала сегодня", peak_speed),
        peak_cpu=card("Пик процессора сегодня", peak_cpu),
        busy=card("Больше всех загружен", busiest[1] if busiest else "—", busy_note),
        rx=card("Вход сейчас", mbps_text(current_rx) + " Мбит/с", "сумма серверов"),
        tx=card("Выход сейчас", mbps_text(current_tx) + " Мбит/с", "сумма серверов"),
        month_proto=month_proto,
        now_proto=now_proto,
        menu=subscription_menu(),
        banner=banner,
    )
    return page("K-Pax — статистика", body, 400 if error else 200, wide=True)


def promo_partner_url(code: str, promo_brand: str) -> str:
    host = BRANDS.get(promo_brand, BRANDS["kpax"])["host"]
    return "https://%s/?promo=%s" % (host, code)


def deactivate_promo(raw: str) -> str:
    """Turn the code off for new redemptions. Past uses keep their days."""
    code = normalize_promo(raw)
    with LOCK:
        conn = db()
        if is_xplm():
            cur = conn.execute(
                "UPDATE promos SET active=0 WHERE code=? AND brand='xplm' AND active=1",
                (code,),
            )
        else:
            cur = conn.execute(
                "UPDATE promos SET active=0 WHERE code=? AND active=1",
                (code,),
            )
        conn.commit()
        conn.close()
    if cur.rowcount < 1:
        raise ValueError("Такого промокода нет.")
    return code


def promo_rows(only_brand: str = "") -> list[sqlite3.Row]:
    conn = db()
    if only_brand:
        rows = conn.execute(
            """
            SELECT p.code, p.days, p.max_uses, p.used, p.active, p.brand, p.created_at,
                   (SELECT MAX(u.created_at) FROM promo_uses u WHERE u.code=p.code) AS last_use
            FROM promos p WHERE p.brand=? AND p.active=1 ORDER BY p.created_at DESC LIMIT 100
            """,
            (only_brand,),
        ).fetchall()
    else:
        rows = conn.execute(
            """
            SELECT p.code, p.days, p.max_uses, p.used, p.active, p.brand, p.created_at,
                   (SELECT MAX(u.created_at) FROM promo_uses u WHERE u.code=p.code) AS last_use
            FROM promos p WHERE p.active=1 ORDER BY p.created_at DESC LIMIT 100
            """
        ).fetchall()
    conn.close()
    return list(rows)


def promos_page(notice: str = "", error: str = "") -> tuple[int, str, bytes]:
    only = "xplm" if is_xplm() else ""
    rows = promo_rows(only)
    body_rows = []
    for row in rows:
        bid = str(row["brand"] or "kpax")
        state = "активен" if int(row["used"]) < int(row["max_uses"]) else "лимит"
        days = int(row["days"])
        days_note = "только учёт" if days == 0 else ("%d дн." % days)
        last = int(row["last_use"] or 0)
        last_note = fmt(last) if last else "—"
        link = promo_partner_url(str(row["code"]), bid)
        short = "/?promo=" + str(row["code"])
        body_rows.append(
            "<tr><td><code>%s</code></td><td>%s</td><td>%s</td><td>%d / %d</td>"
            "<td>%s</td><td>%s</td><td><a class='cell-link' href='%s' title='%s'>%s</a></td>"
            "<td>"
            "<form class='inline-del' method='post' action='/admin/promo/delete'>"
            "<input type='hidden' name='code' value='%s'>"
            "<button type='submit' class='ghost'>Удалить</button>"
            "</form>"
            "</td></tr>"
            % (
                html.escape(row["code"]),
                html.escape(BRANDS.get(bid, BRANDS["kpax"])["name"]),
                days_note,
                int(row["used"]),
                int(row["max_uses"]),
                state,
                html.escape(last_note),
                html.escape(link, quote=True),
                html.escape(link, quote=True),
                html.escape(short),
                html.escape(row["code"], quote=True),
            )
        )
    table = (
        "<div class='tablewrap adminlist promos'><table>"
        "<thead><tr>"
        "<th>Код</th><th>Сайт</th><th>Дни</th><th>Использовано</th>"
        "<th>Статус</th><th>Последний</th><th>Ссылка</th><th></th>"
        "</tr></thead><tbody>%s</tbody></table></div>"
        % ("".join(body_rows) or "<tr><td colspan='8'>Промокодов пока нет.</td></tr>")
    )
    if is_xplm():
        create = """
<form class="extend createbar" method="post" action="/admin/promo">
<div class="row">
<input name="code" maxlength="32" placeholder="КОД" required>
<input name="days" type="number" min="0" max="365" value="0" required title="0 = только учёт">
<input name="max_uses" type="number" min="1" max="10000" value="1000" required>
<input type="hidden" name="brand" value="xplm">
<button type="submit">Создать</button>
</div>
</form>
"""
    else:
        create = """
<form class="extend createbar" method="post" action="/admin/promo">
<div class="row">
<input name="code" maxlength="32" placeholder="КОД" required>
<input name="days" type="number" min="0" max="365" value="0" required title="0 = только учёт">
<input name="max_uses" type="number" min="1" max="10000" value="1000" required>
<select name="brand" aria-label="Сайт"><option value="kpax">K-Pax</option><option value="xplm">X-Plm</option></select>
<button type="submit">Создать</button>
</div>
</form>
"""
    note = "<p class='ok'>%s</p>" % html.escape(notice) if notice else ""
    err = "<p class='err'>%s</p>" % html.escape(error) if error else ""
    body = """
{nav}
<div class="toolbar">
<p class="lead">Промокоды: {count}. 0 дней — только учёт без бонуса. Ссылка: сайт/?promo=КОД.</p>
<a href="/admin/logout">Выйти</a>
</div>
{note}{err}
{create}
{table}
""".format(
        nav=admin_nav("promos"),
        count=len(rows),
        note=note,
        err=err,
        create=create,
        table=table,
    )
    return page("K-Pax — промокоды", body, 400 if error else 200, wide=True)


def stats_page_with_notice(notice: str = "", error: str = "") -> tuple[int, str, bytes]:
    return stats_page(notice=notice, error=error)


def person_rows() -> list[dict]:
    month = month_key()
    usage = usage_by_user(month)
    people = live_people()
    conn = db()
    if is_xplm():
        users = conn.execute("SELECT * FROM users WHERE brand='xplm'").fetchall()
    else:
        users = conn.execute("SELECT * FROM users").fetchall()
    paid_counts = {
        int(row[0]): int(row[1])
        for row in conn.execute(
            """
            SELECT user_id, COUNT(*) FROM platega_invoices
            WHERE status='CONFIRMED' GROUP BY user_id
            """
        )
    }
    last_paid = {
        int(row[0]): int(row[1])
        for row in conn.execute(
            """
            SELECT user_id, MAX(updated_at) FROM platega_invoices
            WHERE status='CONFIRMED' GROUP BY user_id
            """
        )
    }
    platform_db: dict[str, dict[str, float]] = {}
    since = now_ts() - int(CLIENT_TTL)
    try:
        for uk, plat, last_at in conn.execute(
            """
            SELECT user_key, platform, MAX(created_at)
            FROM client_events
            WHERE platform IN ('android', 'ios', 'windows')
              AND created_at >= ?
            GROUP BY user_key, platform
            """,
            (since,),
        ):
            platform_db.setdefault(str(uk), {})[str(plat)] = float(last_at or 0)
    except sqlite3.Error:
        platform_db = {}
    conn.close()
    rows = []
    for user in users:
        key = user_key(user["uuid"])
        live = people.get(key) or {}
        up, down = usage.get(key, (0, 0))
        online = bool(live.get("online"))
        speed = float(live.get("speed") or 0)
        platforms = recent_platforms(key, platform_db)
        rows.append(
            {
                "public_id": user["public_id"],
                "contact": user["contact"],
                "brand": str(user["brand"] or "kpax"),
                "token": user["token"],
                "enabled": bool(user["active"]),
                "active": bool(user["active"]) and int(user["expires_at"]) > now_ts(),
                "expires_at": int(user["expires_at"]),
                "online": online,
                "speed": speed,
                "traffic": up + down,
                "up": up,
                "down": down,
                "server": host_title(live.get("host") or "") if online and live.get("host") else "—",
                "proto": proto_label(live["proto"]) if online and live.get("proto") else "—",
                "up_bps": float(live.get("up_bps") or 0),
                "down_bps": float(live.get("down_bps") or 0),
                "devices": int(live.get("devices") or 0),
                "paid": paid_counts.get(int(user["id"]), 0),
                "last_paid": last_paid.get(int(user["id"]), 0),
                "platforms": platforms,
                "os": ",".join(platforms),
            }
        )
    return rows


def sort_people(rows: list[dict], sort: str, direction: str) -> list[dict]:
    def key(row: dict):
        if sort == "speed":
            return row["speed"]
        if sort == "traffic":
            return row["traffic"]
        if sort == "until":
            return row["expires_at"]
        if sort == "id":
            # KP- and XP- share one sequence: order by the number, not by the brand prefix.
            digits = re.sub(r"\D", "", str(row["public_id"]))
            return int(digits) if digits else 0
        if sort == "contact":
            return row["contact"].lower()
        if sort == "os":
            return row.get("os") or ""
        if sort == "status":
            return 1 if row["enabled"] else 0
        if sort == "paid":
            return row["paid"]
        if sort == "last_paid":
            return row["last_paid"]
        if sort == "server":
            return row["server"]
        if sort == "proto":
            return row["proto"]
        return (1 if row["online"] else 0, row["speed"], row["traffic"])

    return sorted(rows, key=key, reverse=direction == "desc")


def users_page(query: str, notice: str = "", error: str = "") -> tuple[int, str, bytes]:
    params = parse_qs(query)
    sort = (params.get("sort") or ["id"])[0]
    direction = (params.get("dir") or ["desc"])[0]
    needle = (params.get("q") or [""])[0].strip()
    if sort not in USER_SORTS:
        sort = "id"
    if direction not in ("asc", "desc"):
        direction = "desc"
    try:
        page_n = int((params.get("page") or ["1"])[0])
    except ValueError:
        page_n = 1
    rows = sort_people(person_rows(), sort, direction)
    folded = needle.lower().lstrip("@")
    if folded:
        rows = [
            row
            for row in rows
            if folded in (row["contact"] + " " + row["public_id"]).lower().lstrip("@")
        ]
    pages = max(1, (len(rows) + PAGE_SIZE - 1) // PAGE_SIZE)
    page_n = min(max(1, page_n), pages)
    chunk = rows[(page_n - 1) * PAGE_SIZE : page_n * PAGE_SIZE]

    def href_for(key: str, nxt: str, number: int) -> str:
        link = "/admin/users?sort=%s&dir=%s&page=%d" % (key, nxt, number)
        if needle:
            link += "&q=" + quote(needle)
        return link

    def th(label: str, key: str) -> str:
        nxt = "asc" if sort == key and direction == "desc" else "desc"
        mark = ""
        if sort == key:
            mark = " ▼" if direction == "desc" else " ▲"
        return "<th><a href='%s'>%s%s</a></th>" % (href_for(key, nxt, 1), html.escape(label), mark)

    body_rows = []
    for row in chunk:
        detail = "/admin/user/" + quote(row["public_id"])
        account = "активен" if row["enabled"] else "выключен"
        presence = "онлайн" if row["online"] else "не в сети"
        speed = bps_text(row["speed"]) if row["online"] else "—"
        last = fmt(int(row["last_paid"])) if row["last_paid"] else "—"
        body_rows.append(
            "<tr><td><a href='%s'><b>%s</b></a></td><td>%s</td><td class='os-cell'>%s</td>"
            "<td>%s</td><td>%d</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td>"
            "<td>%s</td><td>%s</td><td>%s</td></tr>"
            % (
                html.escape(detail, quote=True),
                html.escape(row["public_id"]),
                html.escape(row["contact"]) + (brand_badge(row["brand"]) if not is_xplm() else ""),
                platforms_cell(list(row.get("platforms") or [])),
                account,
                int(row["paid"]),
                html.escape(last),
                presence,
                html.escape(row["server"]),
                html.escape(row["proto"]),
                speed,
                bytes_text(row["traffic"]),
                html.escape(fmt(row["expires_at"])),
            )
        )
    links = []
    for number in range(1, pages + 1):
        if number == page_n:
            links.append("<span>%d</span>" % number)
        else:
            links.append("<a href='%s'>%d</a>" % (href_for(sort, direction, number), number))
    pager = "<nav class='pager'>%s</nav>" % "".join(links) if pages > 1 else ""
    table = (
        "<div class='tablewrap people'><table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>%s"
        % (
            "".join(
                [
                    th("Номер", "id"),
                    th("Контакт", "contact"),
                    th("ОС", "os"),
                    th("Статус", "status"),
                    th("Оплаты", "paid"),
                    th("Последняя оплата", "last_paid"),
                    th("Сейчас", "online"),
                    th("Сервер", "server"),
                    th("Протокол", "proto"),
                    th("Скорость", "speed"),
                    th("Трафик за месяц", "traffic"),
                    th("До", "until"),
                ]
            ),
            "".join(body_rows) or "<tr><td colspan='12'>Пока пусто.</td></tr>",
            pager,
        )
    )
    note = "<p class='ok'>%s</p>" % html.escape(notice) if notice else ""
    err = "<p class='err'>%s</p>" % html.escape(error) if error else ""
    body = """
{nav}
<div class="toolbar">
<p class="lead">Аккаунты: {count}. По {size} на странице. Номер открывает профиль.</p>
<a href="/admin/logout">Выйти</a>
</div>
{note}{err}
<form class="extend" method="get" action="/admin/users">
<input id="q" name="q" type="search" value="{needle}" placeholder="Поиск по почте или нику" autocomplete="off" enterkeyhint="search">
<input type="hidden" name="sort" value="{sort}">
<input type="hidden" name="dir" value="{direction}">
</form>
{table}
""".format(
        nav=admin_nav("users"),
        count=len(person_rows()),
        size=PAGE_SIZE,
        note=note,
        err=err,
        needle=html.escape(needle, quote=True),
        sort=html.escape(sort, quote=True),
        direction=html.escape(direction, quote=True),
        table=table,
    )
    return page("K-Pax — участники", body, 400 if error else 200, wide=True)


def _autotest_badge(status: str, note: str = "") -> str:
    kind = _clip_text(status or "skip", 16).lower()
    if kind not in ("ok", "fail", "pending", "skip"):
        kind = "skip"
    label = {"ok": "ok", "fail": "fail", "pending": "…", "skip": "skip"}[kind]
    title = html.escape(note or kind, quote=True)
    return (
        "<span class='badge-autotest %s' title='%s'>%s</span>"
        % (html.escape(kind, quote=True), title, html.escape(label))
    )


def _severity_badge(severity: str) -> str:
    kind = "error" if severity == "error" else "info"
    return "<span class='badge-sev %s'>%s</span>" % (kind, html.escape(kind))


def _client_event_node_label(row) -> str:
    return " ".join(
        part
        for part in (
            str(row["country_id"] or ""),
            str(row["kind"] or ""),
            (":" + str(int(row["port"]))) if int(row["port"] or 0) else "",
        )
        if part
    )


def _client_event_summary(row, *, limit: int = 88) -> str:
    event = str(row["event"] or "")
    host = str(row["host"] or "").strip()
    port = int(row["port"] or 0)
    if host and port:
        endpoint = "%s:%d" % (host, port)
    elif host:
        endpoint = host
    elif port:
        endpoint = ":%d" % port
    else:
        endpoint = _client_event_node_label(row)
    err = _clip_text(str(row["error_code"] or row["error"] or ""), 40)
    bits = [bit for bit in (event, endpoint, err) if bit]
    return _clip_text(" · ".join(bits), limit)


def _client_events_qs(
    *,
    public_id: str = "",
    event_filter: str = "",
    brand_filter: str = "",
    hours: int = 48,
    sort: str = "errors_first",
    severity_filter: str = "",
    view: str = "",
    page: int | None = None,
    ipage: int | None = None,
) -> str:
    parts: list[str] = []
    if public_id:
        parts.append("q=" + quote(public_id))
    if event_filter:
        parts.append("event=" + quote(event_filter))
    if brand_filter and not is_xplm():
        parts.append("brand=" + quote(brand_filter))
    if severity_filter:
        parts.append("severity=" + quote(severity_filter))
    if view:
        parts.append("view=" + quote(view))
    parts.append("hours=%d" % hours)
    parts.append("sort=" + quote(sort))
    if page is not None and page > 1:
        parts.append("page=%d" % page)
    if ipage is not None and ipage > 1:
        parts.append("ipage=%d" % ipage)
    return "&".join(parts)


def _admin_pager(make_href, page_n: int, pages: int) -> str:
    if pages <= 1:
        return ""
    links: list[str] = []
    if page_n > 1:
        links.append("<a href='%s'>‹</a>" % html.escape(make_href(page_n - 1), quote=True))
    window = 7
    start = max(1, page_n - window // 2)
    end = min(pages, start + window - 1)
    start = max(1, end - window + 1)
    if start > 1:
        links.append("<a href='%s'>1</a>" % html.escape(make_href(1), quote=True))
        if start > 2:
            links.append("<span>…</span>")
    for number in range(start, end + 1):
        if number == page_n:
            links.append("<span>%d</span>" % number)
        else:
            links.append(
                "<a href='%s'>%d</a>"
                % (html.escape(make_href(number), quote=True), number)
            )
    if end < pages:
        if end < pages - 1:
            links.append("<span>…</span>")
        links.append(
            "<a href='%s'>%d</a>" % (html.escape(make_href(pages), quote=True), pages)
        )
    if page_n < pages:
        links.append("<a href='%s'>›</a>" % html.escape(make_href(page_n + 1), quote=True))
    return "<nav class='pager'>%s</nav>" % "".join(links)


def _resolve_event_severity(row) -> str:
    severity = str(row["severity"] or client_event_severity(str(row["event"] or "")))
    if severity not in ("error", "info"):
        severity = client_event_severity(str(row["event"] or ""))
    return severity


def client_events_page(query: str) -> tuple[int, str, bytes]:
    params = parse_qs(query)
    event_filter = _clip_text((params.get("event") or [""])[0], 32)
    if event_filter and event_filter not in CLIENT_EVENT_NAMES:
        event_filter = ""
    brand_filter = _clip_text((params.get("brand") or [""])[0], 16).lower()
    if brand_filter and brand_filter not in BRANDS:
        brand_filter = ""
    if is_xplm() and not brand_filter:
        brand_filter = "xplm"
    public_id = _clip_text((params.get("q") or [""])[0], 32).upper()
    if public_id and not re.fullmatch(PUBLIC_ID_RE, public_id):
        public_id = ""
    try:
        hours = int((params.get("hours") or ["48"])[0])
    except ValueError:
        hours = 48
    if hours not in (6, 24, 48, 168):
        hours = 48
    severity_filter = _clip_text((params.get("severity") or [""])[0], 16).lower()
    if severity_filter not in ("", "error", "info"):
        severity_filter = ""
    view = _clip_text((params.get("view") or [""])[0], 16).lower()
    if view not in ("", "incidents"):
        view = ""
    sort = _clip_text((params.get("sort") or ["errors_first"])[0], 16).lower()
    if sort not in ("errors_first", "time"):
        sort = "errors_first"
    try:
        page_n = int((params.get("page") or ["1"])[0])
    except ValueError:
        page_n = 1
    try:
        ipage_n = int((params.get("ipage") or ["1"])[0])
    except ValueError:
        ipage_n = 1
    since = now_ts() - hours * 3600
    key_filter = ""
    if public_id:
        with LOCK:
            conn = db()
            user = conn.execute(
                "SELECT uuid, brand FROM users WHERE public_id=? LIMIT 1",
                (public_id,),
            ).fetchone()
            conn.close()
        if user is not None and (not is_xplm() or str(user["brand"] or "kpax") == "xplm"):
            key_filter = user_key(str(user["uuid"]))
        else:
            key_filter = "__missing__"
    clauses = ["e.created_at >= ?"]
    args: list = [since]
    if brand_filter:
        clauses.append("e.brand = ?")
        args.append(brand_filter)
    if event_filter:
        clauses.append("e.event = ?")
        args.append(event_filter)
    if severity_filter:
        clauses.append("e.severity = ?")
        args.append(severity_filter)
    if key_filter:
        clauses.append("e.user_key = ?")
        args.append(key_filter)
    where = " AND ".join(clauses)
    if sort == "time":
        order_sql = "ORDER BY e.created_at DESC, e.id DESC"
    else:
        order_sql = (
            "ORDER BY CASE WHEN e.severity='error' THEN 0 ELSE 1 END, "
            "e.created_at DESC, e.id DESC"
        )
    incident_clauses = ["i.created_at >= ?"]
    incident_args: list = [since]
    if brand_filter:
        incident_clauses.append("i.brand = ?")
        incident_args.append(brand_filter)
    if key_filter:
        incident_clauses.append("i.user_key = ?")
        incident_args.append(key_filter)
    incident_where = " AND ".join(incident_clauses)
    if sort == "time":
        incident_order = "ORDER BY i.created_at DESC, i.id DESC"
    else:
        incident_order = (
            "ORDER BY CASE i.autotest_status "
            "WHEN 'fail' THEN 0 WHEN 'pending' THEN 1 WHEN 'skip' THEN 2 ELSE 3 END, "
            "i.created_at DESC, i.id DESC"
        )
    show_incidents = severity_filter == "error" or view == "incidents"
    with LOCK:
        conn = db()
        purge_old_client_events(conn)
        event_total = int(
            conn.execute(
                "SELECT COUNT(*) FROM client_events e WHERE %s" % where,
                args,
            ).fetchone()[0]
        )
        event_pages = max(1, (event_total + PAGE_SIZE - 1) // PAGE_SIZE)
        page_n = min(max(1, page_n), event_pages)
        event_offset = (page_n - 1) * PAGE_SIZE
        rows = conn.execute(
            """
            SELECT e.*, u.public_id AS public_id
            FROM client_events e
            LEFT JOIN users u
              ON e.user_key = 'kp-' || substr(replace(u.uuid, '-', ''), 1, 8)
            WHERE %s
            %s
            LIMIT ? OFFSET ?
            """
            % (where, order_sql),
            args + [PAGE_SIZE, event_offset],
        ).fetchall()
        incident_total = 0
        incident_pages = 1
        incident_rows = []
        if show_incidents:
            incident_total = int(
                conn.execute(
                    "SELECT COUNT(*) FROM client_incidents i WHERE %s" % incident_where,
                    incident_args,
                ).fetchone()[0]
            )
            incident_pages = max(1, (incident_total + PAGE_SIZE - 1) // PAGE_SIZE)
            ipage_n = min(max(1, ipage_n), incident_pages)
            incident_offset = (ipage_n - 1) * PAGE_SIZE
            incident_rows = conn.execute(
                """
                SELECT i.*, u.public_id AS public_id
                FROM client_incidents i
                LEFT JOIN users u
                  ON i.user_key = 'kp-' || substr(replace(u.uuid, '-', ''), 1, 8)
                WHERE %s
                %s
                LIMIT ? OFFSET ?
                """
                % (incident_where, incident_order),
                incident_args + [PAGE_SIZE, incident_offset],
            ).fetchall()
        else:
            ipage_n = 1
        auto_rows = conn.execute(
            """
            SELECT user_key, trigger_event, host, port, autotest_status, autotest_note
            FROM client_incidents
            WHERE created_at >= ?
            ORDER BY created_at DESC, id DESC
            LIMIT 400
            """,
            (since,),
        ).fetchall()
        conn.commit()
        conn.close()
    autotest_map: dict[tuple[str, str, str, int], tuple[str, str]] = {}
    for item in auto_rows:
        map_key = (
            str(item["user_key"] or ""),
            str(item["trigger_event"] or ""),
            str(item["host"] or ""),
            int(item["port"] or 0),
        )
        if map_key not in autotest_map:
            autotest_map[map_key] = (
                str(item["autotest_status"] or "pending"),
                str(item["autotest_note"] or ""),
            )

    def list_href(*, page: int | None = None, ipage: int | None = None) -> str:
        return "/admin/client-events?" + _client_events_qs(
            public_id=public_id,
            event_filter=event_filter,
            brand_filter=brand_filter,
            hours=hours,
            sort=sort,
            severity_filter=severity_filter,
            view=view,
            page=page_n if page is None else page,
            ipage=ipage_n if ipage is None else ipage,
        )

    body_rows = []
    for row in rows:
        event_id = int(row["id"])
        detail_href = "/admin/client-events/%d" % event_id
        pid = str(row["public_id"] or "")
        user_href = "/admin/user/" + quote(pid) if pid else ""
        pid_cell = (
            "<a href='%s'><b>%s</b></a>"
            % (html.escape(user_href, quote=True), html.escape(pid))
            if user_href
            else html.escape(str(row["user_key"] or ""))
        )
        severity = _resolve_event_severity(row)
        auto_status, auto_note = autotest_map.get(
            (
                str(row["user_key"] or ""),
                str(row["event"] or ""),
                str(row["host"] or ""),
                int(row["port"] or 0),
            ),
            ("", ""),
        )
        auto_cell = _autotest_badge(auto_status, auto_note) if auto_status else "—"
        tr_class = " class='error'" if severity == "error" else ""
        summary = _client_event_summary(row)
        body_rows.append(
            "<tr%s>"
            "<td><a class='cell-link' href='%s'>%s</a></td>"
            "<td>%s</td><td>%s</td><td>%s</td><td>%s</td>"
            "<td>%s</td><td>%s</td><td>%s</td><td>%s</td>"
            "<td class='summary'><a href='%s'>%s</a></td>"
            "<td>%s</td><td>%s</td>"
            "</tr>"
            % (
                tr_class,
                html.escape(detail_href, quote=True),
                html.escape(fmt(int(row["created_at"]))),
                pid_cell,
                html.escape(str(row["brand"] or "")),
                _severity_badge(severity),
                html.escape(str(row["event"] or "")),
                html.escape(_client_event_node_label(row)),
                html.escape(str(row["host"] or "")),
                html.escape(str(row["platform"] or "")),
                html.escape(str(row["app_version"] or "")),
                html.escape(detail_href, quote=True),
                html.escape(summary) if summary else "—",
                auto_cell,
                html.escape(str(row["client_ip"] or "")),
            )
        )
    event_pager = _admin_pager(
        lambda n: list_href(page=n, ipage=ipage_n),
        page_n,
        event_pages,
    )
    table = (
        "<div class='tablewrap adminlist events'><table><thead><tr>"
        "<th>Время</th><th>Участник</th><th>Бренд</th><th>Sev</th><th>Событие</th>"
        "<th>Узел</th><th>Host</th><th>Платформа</th><th>Версия</th>"
        "<th>Кратко</th><th>Автотест</th><th>IP</th>"
        "</tr></thead><tbody>%s</tbody></table></div>%s"
        % (
            "".join(body_rows) or "<tr><td colspan='12'>Пока пусто.</td></tr>",
            event_pager,
        )
    )
    incidents_block = ""
    if show_incidents:
        incident_body = []
        for item in incident_rows:
            pid = str(item["public_id"] or "")
            user_href = "/admin/user/" + quote(pid) if pid else ""
            pid_cell = (
                "<a href='%s'><b>%s</b></a>"
                % (html.escape(user_href, quote=True), html.escape(pid))
                if user_href
                else html.escape(str(item["user_key"] or ""))
            )
            summary = _clip_text(
                str(item["trigger_event"] or "")
                + (
                    " · " + str(item["error_code"] or item["error"] or "")
                    if (item["error_code"] or item["error"])
                    else ""
                ),
                72,
            )
            node = " ".join(
                part
                for part in (
                    str(item["country_id"] or ""),
                    str(item["host"] or ""),
                    (":" + str(item["port"])) if int(item["port"] or 0) else "",
                )
                if part
            )
            related = ""
            for ev in rows:
                if (
                    str(ev["user_key"] or "") == str(item["user_key"] or "")
                    and str(ev["event"] or "") == str(item["trigger_event"] or "")
                    and str(ev["host"] or "") == str(item["host"] or "")
                    and int(ev["port"] or 0) == int(item["port"] or 0)
                ):
                    related = "/admin/client-events/%d" % int(ev["id"])
                    break
            time_cell = html.escape(fmt(int(item["created_at"])))
            if related:
                time_cell = (
                    "<a class='cell-link' href='%s'>%s</a>"
                    % (html.escape(related, quote=True), time_cell)
                )
            incident_body.append(
                "<tr class='error'>"
                "<td>%s</td><td>%s</td><td>%s</td><td>%s</td>"
                "<td class='summary'>%s</td><td>%s</td><td>%s</td>"
                "</tr>"
                % (
                    time_cell,
                    pid_cell,
                    html.escape(str(item["brand"] or "")),
                    html.escape(str(item["trigger_event"] or "")),
                    html.escape(summary) if summary else "—",
                    _autotest_badge(
                        str(item["autotest_status"] or "pending"),
                        str(item["autotest_note"] or ""),
                    ),
                    html.escape(node),
                )
            )
        incident_pager = _admin_pager(
            lambda n: list_href(page=page_n, ipage=n),
            ipage_n,
            incident_pages,
        )
        incidents_table = (
            "<div class='tablewrap adminlist'><table><thead><tr>"
            "<th>Время</th><th>Участник</th><th>Бренд</th><th>Триггер</th>"
            "<th>Кратко</th><th>Автотест</th><th>Узел</th>"
            "</tr></thead><tbody>%s</tbody></table></div>%s"
            % (
                "".join(incident_body)
                or "<tr><td colspan='7'>Инцидентов пока нет.</td></tr>",
                incident_pager,
            )
        )
        incidents_block = (
            "<div class='incident-summary'>"
            "<p class='lead'>Инциденты: %d за окно · стр. %d/%d · по %d.</p>%s</div>"
            % (incident_total, ipage_n, incident_pages, PAGE_SIZE, incidents_table)
        )
    event_opts = ['<option value="">все</option>']
    for name in sorted(CLIENT_EVENT_NAMES):
        mark = " selected" if name == event_filter else ""
        event_opts.append(
            "<option value='%s'%s>%s</option>"
            % (html.escape(name, quote=True), mark, html.escape(name))
        )
    brand_opts = ['<option value="">все</option>']
    if not is_xplm():
        for bid, meta in BRANDS.items():
            mark = " selected" if bid == brand_filter else ""
            brand_opts.append(
                "<option value='%s'%s>%s</option>"
                % (html.escape(bid, quote=True), mark, html.escape(meta["name"]))
            )
    hour_opts = []
    for value, label in ((6, "6ч"), (24, "24ч"), (48, "48ч"), (168, "7д")):
        mark = " selected" if value == hours else ""
        hour_opts.append("<option value='%d'%s>%s</option>" % (value, mark, label))
    severity_opts = [
        "<option value=''%s>все</option>" % (" selected" if not severity_filter else ""),
        "<option value='error'%s>ошибки</option>"
        % (" selected" if severity_filter == "error" else ""),
        "<option value='info'%s>info</option>"
        % (" selected" if severity_filter == "info" else ""),
    ]
    sort_opts = [
        "<option value='errors_first'%s>ошибки↑</option>"
        % (" selected" if sort == "errors_first" else ""),
        "<option value='time'%s>время</option>"
        % (" selected" if sort == "time" else ""),
    ]
    brand_field = ""
    if not is_xplm():
        brand_field = (
            "<label>Бренд <select name='brand'>%s</select></label>" % "".join(brand_opts)
        )
    view_hidden = (
        "<input type='hidden' name='view' value='incidents'>" if view == "incidents" else ""
    )
    incidents_href = "/admin/client-events?" + _client_events_qs(
        public_id=public_id,
        event_filter=event_filter,
        brand_filter=brand_filter,
        hours=hours,
        sort=sort,
        severity_filter="error",
        view="incidents",
    )
    all_href = "/admin/client-events?" + _client_events_qs(
        public_id=public_id,
        event_filter=event_filter,
        brand_filter=brand_filter,
        hours=hours,
        sort=sort,
    )
    body = """
{nav}
<div class="toolbar">
<p class="lead">События клиента: {total} за {hours} ч · стр. {page}/{pages} · по {size}. Клик по времени/кратко — детали.</p>
<a href="/admin/logout">Выйти</a>
</div>
<p class="row">
<a href="{incidents_href}">Инциденты</a>
<a href="{all_href}">Все события</a>
</p>
<form class="extend createbar eventfilters" method="get" action="/admin/client-events">
{view_hidden}
<div class="row">
<input name="q" type="search" value="{needle}" placeholder="KP-… / XP-…" autocomplete="off">
<label>Событие <select name="event">{event_opts}</select></label>
<label>Sev <select name="severity">{severity_opts}</select></label>
<label>Сорт <select name="sort">{sort_opts}</select></label>
{brand_field}
<label>Окно <select name="hours">{hour_opts}</select></label>
<button type="submit">Показать</button>
</div>
</form>
{incidents_block}
{table}
""".format(
        nav=admin_nav("client-events"),
        total=event_total,
        hours=hours,
        page=page_n,
        pages=event_pages,
        size=PAGE_SIZE,
        needle=html.escape(public_id, quote=True),
        event_opts="".join(event_opts),
        severity_opts="".join(severity_opts),
        sort_opts="".join(sort_opts),
        brand_field=brand_field,
        hour_opts="".join(hour_opts),
        view_hidden=view_hidden,
        incidents_href=html.escape(incidents_href, quote=True),
        all_href=html.escape(all_href, quote=True),
        incidents_block=incidents_block,
        table=table,
    )
    return page("K-Pax — события клиента", body, 200, wide=True)


def client_event_detail_page(event_id: int) -> tuple[int, str, bytes]:
    if event_id <= 0:
        return page("K-Pax — событие", "<p>Событие не найдено.</p>", 404, wide=True)
    with LOCK:
        conn = db()
        row = conn.execute(
            """
            SELECT e.*, u.public_id AS public_id
            FROM client_events e
            LEFT JOIN users u
              ON e.user_key = 'kp-' || substr(replace(u.uuid, '-', ''), 1, 8)
            WHERE e.id=?
            LIMIT 1
            """,
            (event_id,),
        ).fetchone()
        if row is None:
            conn.close()
            return page("K-Pax — событие", "<p>Событие не найдено.</p>", 404, wide=True)
        if is_xplm() and str(row["brand"] or "kpax") != "xplm":
            conn.close()
            return page("K-Pax — событие", "<p>Событие не найдено.</p>", 404, wide=True)
        incident = conn.execute(
            """
            SELECT *
            FROM client_incidents
            WHERE user_key=? AND trigger_event=? AND host=? AND port=?
            ORDER BY ABS(created_at - ?) ASC, id DESC
            LIMIT 1
            """,
            (
                str(row["user_key"] or ""),
                str(row["event"] or ""),
                str(row["host"] or ""),
                int(row["port"] or 0),
                int(row["created_at"] or 0),
            ),
        ).fetchone()
        related = conn.execute(
            """
            SELECT e.*, u.public_id AS public_id
            FROM client_events e
            LEFT JOIN users u
              ON e.user_key = 'kp-' || substr(replace(u.uuid, '-', ''), 1, 8)
            WHERE e.id != ?
              AND (
                e.user_key = ?
                OR (e.session_id != '' AND e.session_id = ?)
              )
            ORDER BY e.created_at DESC, e.id DESC
            LIMIT 12
            """,
            (
                event_id,
                str(row["user_key"] or ""),
                str(row["session_id"] or ""),
            ),
        ).fetchall()
        conn.close()
    severity = _resolve_event_severity(row)
    description = client_event_description(
        {
            "event": row["event"],
            "country_id": row["country_id"],
            "port": row["port"],
            "kind": row["kind"],
            "error": row["error"],
            "error_code": row["error_code"],
        }
    )
    pid = str(row["public_id"] or "")
    pid_html = (
        "<a href='/admin/user/%s'><b>%s</b></a>"
        % (html.escape(quote(pid), quote=True), html.escape(pid))
        if pid
        else html.escape(str(row["user_key"] or ""))
    )
    err_full = str(row["error"] or "")
    err_code = str(row["error_code"] or "")
    incident_html = "<p class='muted'>Связанного инцидента нет.</p>"
    if incident is not None:
        incident_html = (
            "<dl class='kv'>"
            "<dt>Статус</dt><dd>%s</dd>"
            "<dt>Заметка</dt><dd>%s</dd>"
            "<dt>Создан</dt><dd>%s</dd>"
            "<dt>Описание</dt><dd>%s</dd>"
            "</dl>"
            % (
                _autotest_badge(
                    str(incident["autotest_status"] or "pending"),
                    str(incident["autotest_note"] or ""),
                ),
                html.escape(str(incident["autotest_note"] or "—")),
                html.escape(fmt(int(incident["created_at"]))),
                html.escape(str(incident["description"] or "—")),
            )
        )
    related_rows = []
    for item in related:
        href = "/admin/client-events/%d" % int(item["id"])
        related_rows.append(
            "<tr%s><td><a class='cell-link' href='%s'>%s</a></td>"
            "<td>%s</td><td>%s</td><td class='summary'>%s</td></tr>"
            % (
                " class='error'" if _resolve_event_severity(item) == "error" else "",
                html.escape(href, quote=True),
                html.escape(fmt(int(item["created_at"]))),
                html.escape(str(item["event"] or "")),
                html.escape(_client_event_node_label(item)),
                html.escape(_client_event_summary(item, limit=64)),
            )
        )
    related_table = (
        "<div class='tablewrap adminlist'><table><thead><tr>"
        "<th>Время</th><th>Событие</th><th>Узел</th><th>Кратко</th>"
        "</tr></thead><tbody>%s</tbody></table></div>"
        % (
            "".join(related_rows)
            or "<tr><td colspan='4'>Нет связанных событий.</td></tr>"
        )
    )
    body = """
{nav}
<div class="toolbar">
<p class="lead">Событие #{eid}</p>
<a href="/admin/client-events">← К списку</a>
</div>
<div class="event-detail">
<dl class="kv">
<dt>Время</dt><dd>{time}</dd>
<dt>Участник</dt><dd>{pid}</dd>
<dt>Бренд</dt><dd>{brand}</dd>
<dt>Sev</dt><dd>{sev}</dd>
<dt>Событие</dt><dd>{event}</dd>
<dt>Узел</dt><dd>{node}</dd>
<dt>Host</dt><dd>{host}</dd>
<dt>Port</dt><dd>{port}</dd>
<dt>Платформа</dt><dd>{platform}</dd>
<dt>Версия</dt><dd>{version}</dd>
<dt>IP</dt><dd>{ip}</dd>
<dt>Session</dt><dd>{session}</dd>
<dt>error_code</dt><dd>{err_code}</dd>
</dl>
<h2>Ошибка</h2>
<div class="long">{error}</div>
<h2>Описание</h2>
<div class="long">{description}</div>
<h2>Инцидент / автотест</h2>
{incident}
<h2>Связанные события</h2>
{related}
</div>
""".format(
        nav=admin_nav("client-events"),
        eid=event_id,
        time=html.escape(fmt(int(row["created_at"]))),
        pid=pid_html,
        brand=html.escape(str(row["brand"] or "")),
        sev=_severity_badge(severity),
        event=html.escape(str(row["event"] or "")),
        node=html.escape(_client_event_node_label(row) or "—"),
        host=html.escape(str(row["host"] or "—")),
        port=html.escape(str(int(row["port"] or 0) or "—")),
        platform=html.escape(str(row["platform"] or "—")),
        version=html.escape(str(row["app_version"] or "—")),
        ip=html.escape(str(row["client_ip"] or "—")),
        session=html.escape(str(row["session_id"] or "—")),
        err_code=html.escape(err_code or "—"),
        error=html.escape(err_full or "—"),
        description=html.escape(description or "—"),
        incident=incident_html,
        related=related_table,
    )
    return page("K-Pax — событие #%d" % event_id, body, 200, wide=True)


def user_stats_page(public_id: str, notice: str = "", error: str = "") -> tuple[int, str, bytes]:
    if not re.fullmatch(PUBLIC_ID_RE, public_id):
        return page("K-Pax — участник", "<p>Аккаунт не найден.</p>", 404, wide=True)
    conn = db()
    user = conn.execute("SELECT * FROM users WHERE public_id=?", (public_id,)).fetchone()
    if user is None or (is_xplm() and str(user["brand"] or "kpax") != "xplm"):
        conn.close()
        return page("K-Pax — участник", "<p>Аккаунт не найден.</p>", 404, wide=True)
    key = user_key(user["uuid"])
    month = month_key()
    parts = conn.execute(
        """
        SELECT proto, bytes_up, bytes_down FROM usage_month
        WHERE user_key=? AND month=? ORDER BY (bytes_up + bytes_down) DESC
        """,
        (key, month),
    ).fetchall()
    invited_count = conn.execute(
        "SELECT COUNT(*) FROM referrals WHERE referrer_id=?",
        (user["id"],),
    ).fetchone()[0]
    paid_rows = conn.execute(
        """
        SELECT amount, updated_at FROM platega_invoices
        WHERE user_id=? AND status='CONFIRMED'
        ORDER BY updated_at DESC, id DESC
        """,
        (int(user["id"]),),
    ).fetchall()
    conn.close()
    live = live_people().get(key)
    online = bool(live and live["online"])
    state = "онлайн" if online else "не в сети"
    if user["active"] and int(user["expires_at"]) > now_ts():
        account = "активен"
    else:
        account = "выключен"
    up = sum(int(row["bytes_up"]) for row in parts)
    down = sum(int(row["bytes_down"]) for row in parts)
    proto_rows = "".join(
        "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>"
        % (
            html.escape(proto_label(row["proto"])),
            bytes_text(int(row["bytes_down"])),
            bytes_text(int(row["bytes_up"])),
            bytes_text(int(row["bytes_up"]) + int(row["bytes_down"])),
        )
        for row in parts
    ) or "<tr><td colspan='4'>За этот месяц трафика ещё нет.</td></tr>"
    if online and live:
        speed = "%s к абоненту, %s от абонента" % (bps_text(live["down_bps"]), bps_text(live["up_bps"]))
        server = host_title(live["host"]) if live.get("host") else "—"
        proto = proto_label(live["proto"]) if live.get("proto") else "—"
        devices = str(live["devices"])
    else:
        speed = "—"
        server = "—"
        proto = "—"
        devices = "0"
    paid_count = len(paid_rows)
    paid_sum = sum(int(row["amount"]) for row in paid_rows)
    if paid_rows:
        paylog = (
            "<div class='tablewrap paylog'><table><thead><tr><th>Дата</th><th>Сумма</th><th>Срок</th></tr></thead><tbody>%s</tbody></table></div>"
            % "".join(
                "<tr><td>%s</td><td>%d ₽</td><td>%d дн.</td></tr>"
                % (html.escape(fmt(int(row["updated_at"]))), int(row["amount"]), PAY_DAYS)
                for row in paid_rows
            )
        )
    else:
        paylog = "<p class='muted'>Оплат ещё нет.</p>"
    user_brand = str(user["brand"] or "kpax")
    url = "https://%s/s/%s" % (BRANDS[user_brand]["sub_host"], user["token"])
    note = "<p class='ok'>%s</p>" % html.escape(notice) if notice else ""
    err = "<p class='err'>%s</p>" % html.escape(error) if error else ""
    body = """
{nav}
<h1>{pid}</h1>
<p class="lead">{contact}{badge}</p>
{note}{err}
<div class="healthrow">
{state}
{account}
{speed}
{traffic}
{server}
{proto}
{devices}
{paid}
</div>
<p class="muted">Создан {created}. Доступ до {until}. Приглашено {invited}.</p>
{manage_top}
<h2>Оплаты</h2>
{paylog}
<h2>Трафик за {month}</h2>
<div class="tablewrap"><table><thead><tr><th>Протокол</th><th>К абоненту</th><th>От абонента</th><th>Всего</th></tr></thead><tbody>{protos}</tbody></table></div>
{manage_bottom}
<p><a href="/admin/users">К списку участников</a></p>
""".format(
        nav=admin_nav("users"),
        pid=html.escape(user["public_id"]),
        contact=html.escape(user["contact"]),
        badge=brand_badge(user_brand) if not is_xplm() else "",
        note=note,
        err=err,
        state=card("Сейчас", state),
        account=card("Аккаунт", account),
        speed=card("Скорость", speed),
        traffic=card("Трафик за месяц", bytes_text(up + down), "к абоненту %s, от абонента %s" % (bytes_text(down), bytes_text(up))),
        server=card("Сервер", server),
        proto=card("Протокол", proto),
        devices=card("Устройств онлайн", devices),
        paid=card("Оплаты", str(paid_count), ("%d ₽" % paid_sum) if paid_count else "пока нет"),
        paylog=paylog,
        created=html.escape(fmt(int(user["created_at"]))),
        until=html.escape(fmt(int(user["expires_at"]))),
        invited=int(invited_count),
        month=html.escape(month_label()),
        protos=proto_rows,
        manage_top="" if is_xplm() else MANAGE_TOP.format(
            menu=subscription_menu(),
            url=html.escape(url),
            pid_raw=html.escape(user["public_id"], quote=True),
        ),
        manage_bottom="" if is_xplm() else MANAGE_BOTTOM.format(
            pid=html.escape(user["public_id"]),
            pid_raw=html.escape(user["public_id"], quote=True),
            contact=html.escape(user["contact"]),
        ),
    )
    return page("K-Pax — " + user["public_id"], body, 400 if error else 200, wide=True)


def brand_badge(bid: str) -> str:
    if bid == "kpax":
        return ""
    return " <span class='badge'>%s</span>" % html.escape(BRANDS.get(bid, BRANDS["kpax"])["name"])


MANAGE_TOP = """
<h2>Состав ссылки</h2>
{menu}
<h2>Ссылка</h2>
<div class="linkline"><p class="link">{url}</p>
<button type="button" onclick="navigator.clipboard.writeText(this.previousElementSibling.textContent)">Скопировать</button></div>
<p class="muted">Ссылка у человека не меняется. Если доступ уже выключился, продление включает его снова.</p>
<form class="extend" method="post" action="/admin/extend">
<input type="hidden" name="public_id" value="{pid_raw}">
<div class="row"><input name="days" type="number" min="1" max="365" value="30" required>
<button type="submit">Продлить</button></div>
</form>
"""

MANAGE_BOTTOM = """
<div class="delete-box">
<p>Удаление снимает доступ с узлов и убирает запись из списка участников.</p>
<button class="danger" type="button" id="open-delete">Удалить аккаунт</button>
</div>
<div id="delete-modal" class="modal" hidden>
<div class="sheet" role="dialog" aria-modal="true" aria-labelledby="delete-title">
<button class="x" type="button" id="close-delete" aria-label="Закрыть">×</button>
<h2 id="delete-title">Удалить {pid}?</h2>
<p class="warn">Внимание! Необратимый процесс!</p>
<p>Аккаунт <code>{contact}</code> будет удалён из админки и статистики. Доступ с узлов снимется. Восстановить нельзя.</p>
<form method="post" action="/admin/delete">
<input type="hidden" name="public_id" value="{pid_raw}">
<div class="actions">
<button class="ghost" type="button" id="cancel-delete">Отмена</button>
<button class="danger" type="submit">Удалить навсегда</button>
</div>
</form>
</div>
</div>
<script>
(function () {{
  var modal = document.getElementById("delete-modal");
  var open = document.getElementById("open-delete");
  if (!modal || !open) return;
  function show(on) {{
    modal.hidden = !on;
  }}
  open.addEventListener("click", function () {{ show(true); }});
  document.getElementById("close-delete").addEventListener("click", function () {{ show(false); }});
  document.getElementById("cancel-delete").addEventListener("click", function () {{ show(false); }});
  modal.addEventListener("click", function (event) {{ if (event.target === modal) show(false); }});
  document.addEventListener("keydown", function (event) {{
    if (event.key === "Escape" && !modal.hidden) show(false);
  }});
}})();
</script>
"""


def admin_page(notice: str = "", error: str = "") -> tuple[int, str, bytes]:
    return users_page("", notice, error)


def login_page(error: str = "") -> tuple[int, str, bytes]:
    err = "<p class='err'>%s</p>" % html.escape(error) if error else ""
    code_field = ""
    if totp_secret():
        code_field = (
            '<label for="code">Код из приложения</label>\n'
            '<input id="code" name="code" inputmode="numeric" autocomplete="one-time-code" '
            'maxlength="7" required placeholder="123456">\n'
        )
    body = """
<p class="lead">Вход в учёт аккаунтов.</p>
{err}
<form method="post" action="/admin/login">
<label for="username">Логин</label>
<input id="username" name="username" autocomplete="username" required>
<label for="password">Пароль</label>
<input id="password" name="password" type="password" autocomplete="current-password" required>
{code}<button type="submit">Войти</button>
</form>
""".format(err=err, code=code_field)
    return page("K-Pax — вход", body, 401 if error else 200)


# X-Plm admin is view-only; app login/devices stay open (email accounts).
XPLM_POST_BLOCKED = frozenset(
    (
        "/admin/extend",
        "/admin/delete",
        "/admin/brand-admin",
        "/internal/sessions",
        "/verify/email-fallback",
    )
)


class Handler(BaseHTTPRequestHandler):
    server_version = "K-Pax"

    def version_string(self) -> str:
        return brand()["name"]

    def log_message(self, fmt: str, *args) -> None:
        path = urlparse(self.path).path
        parts = path.split("/")
        if len(parts) > 2 and parts[1] in ("s", "admin"):
            parts[2] = "…"
            path = "/".join(parts)
        print("%s %s%s" % (self.command, "[xplm] " if is_xplm() else "", path), flush=True)

    def serve_site_asset(self, path: str) -> bool:
        """Serve /assets/* and /fonts/* from next to panel.py. Returns True if handled."""
        if path.startswith("/assets/"):
            folder, name = "assets", path[len("/assets/") :]
        elif path.startswith("/fonts/"):
            folder, name = "fonts", path[len("/fonts/") :]
        else:
            return False
        if not name or "/" in name or "\\" in name or name in (".", "..") or not re.fullmatch(
            r"[A-Za-z0-9._-]+", name
        ):
            self.send_bytes(404, "text/plain; charset=utf-8", b"not found\n")
            return True
        full = os.path.join(os.path.dirname(os.path.abspath(__file__)), folder, name)
        try:
            with open(full, "rb") as handle:
                payload = handle.read()
        except OSError:
            self.send_bytes(404, "text/plain; charset=utf-8", b"not found\n")
            return True
        lower = name.lower()
        if lower.endswith(".css"):
            kind = "text/css; charset=utf-8"
        elif lower.endswith(".woff2"):
            kind = "font/woff2"
        elif lower.endswith(".svg"):
            kind = "image/svg+xml"
        elif lower.endswith(".webp"):
            kind = "image/webp"
        elif lower.endswith(".js"):
            kind = "text/javascript; charset=utf-8"
        else:
            kind = "application/octet-stream"
        self.send_bytes(200, kind, payload, index=True, cache="public, max-age=604800")
        return True

    def send_bytes(self, status: int, content_type: str, payload: bytes, extra: dict | None = None, index: bool = False, cache: str = "") -> None:
        textual = content_type.split(";")[0].strip() in (
            "text/html",
            "text/plain",
            "application/json",
            "application/xml",
        )
        if is_xplm() and textual and not urlparse(self.path).path.startswith("/s/"):
            payload = rebrand(payload.decode("utf-8")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", cache or ("public, max-age=300" if index else "no-store"))
        self.send_header("X-Robots-Tag", "index, follow" if index else "noindex")
        for key, value in (extra or {}).items():
            if isinstance(value, (list, tuple)):
                for item in value:
                    self.send_header(key, item)
            else:
                self.send_header(key, value)
        try:
            self.end_headers()
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def setup_brand(self) -> None:
        BRAND_STATE.id = self.edge_brand()

    def do_GET(self) -> None:  # noqa: N802
        self.setup_brand()
        try:
            self.handle_get()
        finally:
            BRAND_STATE.id = "kpax"

    def do_POST(self) -> None:  # noqa: N802
        self.setup_brand()
        try:
            self.handle_post()
        finally:
            BRAND_STATE.id = "kpax"

    def site_host(self) -> str:
        if is_xplm():
            raw = self.headers.get("X-Edge-Host") or ""
        else:
            raw = self.headers.get("X-Forwarded-Host") or self.headers.get("Host") or ""
        return raw.split(",")[0].strip().split(":")[0].lower()

    def redirect_sub_site(self) -> bool:
        """The site lives on the main host. The sub host only serves /s/ links."""
        if self.site_host() != brand()["sub_host"]:
            return False
        path = urlparse(self.path).path
        if path == "/healthz" or path.startswith("/s/") or path.startswith("/internal/"):
            return False
        self.send_response(308 if self.command == "POST" else 301)
        self.send_header("Location", "https://" + brand()["host"] + self.path)
        self.send_header("Cache-Control", "public, max-age=86400")
        self.send_header("Content-Length", "0")
        self.end_headers()
        return True

    def handle_get(self) -> None:
        if self.redirect_sub_site():
            return
        parsed = urlparse(self.path)
        if parsed.path.startswith("/assets/") or parsed.path.startswith("/fonts/"):
            if self.serve_site_asset(parsed.path):
                return
        if is_xplm() and parsed.path in ("/logo.svg", "/logo.png", "/favicon.ico"):
            self.send_bytes(200, "image/svg+xml", XPLM_LOGO_SVG, index=True, cache="public, max-age=86400")
            return
        if is_xplm() and (parsed.path.startswith("/internal/") or parsed.path.startswith("/platega/")):
            self.send_bytes(404, "text/plain; charset=utf-8", b"not found\n")
            return
        if parsed.path == "/logo.png":
            try:
                with open(LOGO_PATH, "rb") as handle:
                    payload = handle.read()
            except OSError:
                self.send_bytes(404, "text/plain; charset=utf-8", b"not found\n")
                return
            self.send_bytes(200, "image/png", payload, index=True, cache="public, max-age=86400")
            return
        if parsed.path == "/robots.txt":
            self.send_bytes(200, "text/plain; charset=utf-8", robots_txt(), index=True, cache="public, max-age=3600")
            return
        if parsed.path == "/sitemap.xml":
            self.send_bytes(200, "application/xml; charset=utf-8", sitemap_xml(), index=True, cache="public, max-age=3600")
            return
        if parsed.path == "/signup":
            target = "/" + (("?" + parsed.query) if parsed.query else "")
            self.send_response(301)
            self.send_header("Location", target)
            self.send_header("Cache-Control", "public, max-age=86400")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if parsed.path == "/":
            query = parse_qs(parsed.query)
            asked = referral_code((query.get("ref") or [""])[0])
            remembered = referral_code(cookie_value(self.headers.get("Cookie"), "kpax_ref"))
            partner_asked = resolve_partner((query.get("p") or [""])[0])
            partner_remembered = resolve_partner(
                cookie_value(self.headers.get("Cookie"), partner_cookie_name())
            )
            partner = partner_asked or partner_remembered
            gift = re.sub(r"[^A-Za-z0-9\-]", "", (query.get("promo") or [""])[0])[:32].upper()
            cap_q = cap_t = ""
            if signup_suspicious(self.client_ip()):
                cap_q, cap_t = issue_captcha()
            status, kind, payload = home(
                ref=asked or remembered,
                partner=partner,
                index=not asked and not gift and not partner_asked,
                captcha_q=cap_q,
                captcha_token=cap_t,
                promo_code=gift,
            )
            cookies = []
            if asked:
                cookies.append(
                    "kpax_ref=%s; Path=/; Max-Age=2592000; SameSite=Lax; Secure" % asked
                )
            if partner_asked:
                cookies.append(
                    "%s=%s; Path=/; Max-Age=2592000; SameSite=Lax; Secure"
                    % (partner_cookie_name(), partner_asked)
                )
            extra = {"Set-Cookie": cookies} if cookies else None
            self.send_bytes(status, kind, payload, extra, index=not asked and not partner_asked)
            return
        if parsed.path == "/pay/done":
            status, kind, payload = pay_result_page(
                "Оплата отправлена",
                "Если банк подтвердил оплату, срок счёта продлится на 30 дней. Ссылка подключения остаётся прежней. Откройте приложение — доступ обновится сам или нажмите «Обновить доступ».",
                open_app=True,
            )
            self.send_bytes(status, kind, payload)
            return
        if parsed.path == "/pay/fail":
            status, kind, payload = pay_result_page(
                "Оплата не прошла",
                "Срок счёта не изменился. Можно вернуться и попробовать ещё раз.",
            )
            self.send_bytes(status, kind, payload)
            return
        if parsed.path == "/status":
            status, kind, payload = public_status_page()
            self.send_bytes(status, kind, payload, index=True)
            return
        if parsed.path == "/pay":
            status, kind, payload = pay_page()
            self.send_bytes(status, kind, payload, index=True)
            return
        if parsed.path == "/faq":
            status, kind, payload = faq_page()
            self.send_bytes(status, kind, payload, index=True)
            return
        if parsed.path == "/terms":
            status, kind, payload = terms_page()
            self.send_bytes(status, kind, payload, index=True)
            return
        if parsed.path == "/privacy":
            status, kind, payload = privacy_page()
            self.send_bytes(status, kind, payload, index=True)
            return
        if parsed.path == "/download/windows":
            self.send_response(302)
            self.send_header(
                "Location",
                XPLM_WINDOWS_APP_ASSET if is_xplm() else WINDOWS_APP_ASSET,
            )
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return
        if parsed.path == "/download/android":
            self.send_response(302)
            self.send_header(
                "Location",
                XPLM_ANDROID_APP_ASSET if is_xplm() else ANDROID_APP_ASSET,
            )
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return
        if parsed.path == "/app/windows":
            if is_xplm():
                # Keep GitHub asset URL for installed clients that only trust
                # github.com; site HTML uses /download/windows (no k-pax in UI).
                payload = json.dumps(
                    {
                        "version": XPLM_WINDOWS_APP_VERSION,
                        "url": XPLM_WINDOWS_APP_ASSET,
                    }
                ).encode()
            else:
                payload = json.dumps(
                    {"version": WINDOWS_APP_VERSION, "url": WINDOWS_APP_ASSET}
                ).encode()
            self.send_bytes(200, "application/json; charset=utf-8", payload)
            return
        if parsed.path == "/app/android":
            if is_xplm():
                payload = json.dumps(
                    {
                        "version": XPLM_ANDROID_APP_VERSION,
                        "url": XPLM_ANDROID_APP_ASSET,
                    }
                ).encode()
            else:
                payload = json.dumps(
                    {"version": ANDROID_APP_VERSION, "url": ANDROID_APP_ASSET}
                ).encode()
            self.send_bytes(200, "application/json; charset=utf-8", payload)
            return
        if parsed.path == "/app/confirm":
            self.app_confirm_click()
            return
        if parsed.path == "/app/login/status":
            self.app_login_status()
            return
        if parsed.path == "/app/devices":
            self.app_devices()
            return
        if parsed.path == "/app/client-events":
            self.send_json(405, {"ok": False, "error": "POST only"})
            return
        if parsed.path == "/healthz":
            self.send_bytes(200, "text/plain; charset=utf-8", b"ok\n")
            return
        if parsed.path in ("/admin", "/admin/"):
            self.show_admin(parsed)
            return
        if parsed.path in ("/admin/stats", "/admin/stats/"):
            self.show_stats()
            return
        if parsed.path in ("/admin/cash", "/admin/cash/"):
            self.show_cash(parsed)
            return
        if parsed.path in ("/admin/users", "/admin/users/"):
            self.show_users(parsed)
            return
        if parsed.path in ("/admin/client-events", "/admin/client-events/"):
            self.show_client_events(parsed)
            return
        event_detail = re.fullmatch(r"/admin/client-events/(\d+)/?", parsed.path)
        if event_detail:
            self.show_client_event_detail(int(event_detail.group(1)))
            return
        if parsed.path in ("/admin/partners", "/admin/partners/"):
            self.show_partners()
            return
        if parsed.path in ("/admin/promos", "/admin/promos/"):
            self.show_promos()
            return
        if parsed.path.startswith("/admin/user/"):
            self.show_user(parsed.path[len("/admin/user/") :], parsed.query)
            return
        if parsed.path == "/admin/logout":
            self.redirect("/admin/", clear_cookie=True)
            return
        if parsed.path in ("/admin/2fa", "/admin/2fa/"):
            if not brand()["admin_totp"]:
                self.redirect("/admin/")
                return
            if not self.logged_in():
                status, kind, payload = login_page()
            else:
                status, kind, payload = totp_page()
            self.send_bytes(status, kind, payload)
            return
        if parsed.path.startswith("/s/"):
            token = parsed.path[len("/s/") :]
            conn = db()
            user = conn.execute("SELECT * FROM users WHERE token=?", (token,)).fetchone()
            conn.close()
            if (
                user is None
                or str(user["brand"] or "kpax") != brand_id()
                or not user["active"]
                or user["expires_at"] <= now_ts()
            ):
                self.send_bytes(403, "text/plain; charset=utf-8", "Подписка недействительна\n".encode())
                return
            agent = self.headers.get("User-Agent") or ""
            remember_client(user["uuid"], agent)
            pinned_hy2 = wants_v2rayng(agent)
            body = subscription_body(
                user,
                pinned_hy2,
                full=wants_kpax_app(agent),
                include_v2rayn_group=not wants_hiddify(agent),
            ).encode()
            title = base64.b64encode(brand()["name"].encode()).decode()
            stem = brand()["name"].lower()
            extra = {
                "profile-title": "base64:" + title,
                "profile-update-interval": "1",
                "subscription-userinfo": "upload=0; download=0; total=0; expire=%d" % user["expires_at"],
                "content-disposition": "attachment; filename=%s.txt" % stem,
            }
            if is_xplm():
                extra["x-xplm-id"] = user["public_id"]
            else:
                extra["x-kpax-id"] = user["public_id"]
            if user_needs_email_link(user) and wants_kpax_app(agent):
                extra["x-kpax-needs-email"] = "1"
            channel = brand().get("channel")
            if channel:
                # Headers are Latin-1: Russian text goes as base64, which Happ and INCY decode.
                extra["announce"] = "base64:" + base64.b64encode(CHANNEL_ANNOUNCE.encode()).decode()
            if wants_incy(agent) or (self.headers.get("x-client") or "").lower() == "incy":
                body = json.dumps(incy_configs(user), ensure_ascii=False).encode()
                extra["content-disposition"] = "attachment; filename=%s.json" % stem
                extra["sort-order"] = "none"
                if channel:
                    extra["announce-url"] = channel
                self.send_bytes(200, "application/json; charset=utf-8", body, extra)
                return
            if wants_happ(agent):
                body = json.dumps(incy_configs(user), ensure_ascii=False).encode()
                extra["content-disposition"] = "attachment; filename=%s.json" % stem
                if brand().get("happ_provider"):
                    extra["providerid"] = brand()["happ_provider"]
                extra["subscriptions-sort-type"] = "without"
                extra["subscription-autoconnect"] = "1"
                extra["ping-type"] = "tcp"
                # Happ shows its own "Renew" banner 3 days before the end and after it.
                extra["sub-expire"] = "1"
                extra["sub-expire-button-link"] = "https://%s/pay" % brand()["host"]
                self.send_bytes(200, "application/json; charset=utf-8", body, extra)
                return
            if wants_v2rayn(agent):
                body = v2rayn_subscription_body(user).encode()
                extra["content-disposition"] = "attachment; filename=%s.txt" % stem
            else:
                extra.update(happ_headers())
            self.send_bytes(200, "text/plain; charset=utf-8", body, extra)
            return
        self.send_bytes(404, "text/plain; charset=utf-8", b"not found\n")

    def peer_ip(self) -> str:
        # Cloudflare sets CF-Connecting-IP to the real client. Caddy then appends the
        # edge IP to X-Forwarded-For, so the last hop is Cloudflare — not the node.
        cf = (self.headers.get("CF-Connecting-IP") or self.headers.get("True-Client-IP") or "").strip()
        if cf:
            return cf
        forwarded = [part.strip() for part in (self.headers.get("X-Forwarded-For") or "").split(",") if part.strip()]
        if forwarded:
            return forwarded[0]
        return self.client_address[0]

    def device_limit(self) -> None:
        nodes = {node["host"] for node in CFG["nodes"]}
        secret = str(CFG.get("limit_secret") or "")
        header = self.headers.get("Authorization") or ""
        token = header[7:] if header.startswith("Bearer ") else ""
        if self.peer_ip() not in nodes or not secret or len(token) != len(secret) or not hmac.compare_digest(token, secret):
            self.send_bytes(403, "application/json", b'{"close":[]}\n')
            return
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 500000:
            self.send_bytes(400, "application/json", b'{"close":[]}\n')
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            reports = payload.get("sessions") or []
        except (json.JSONDecodeError, UnicodeError):
            self.send_bytes(400, "application/json", b'{"close":[]}\n')
            return
        clean = []
        for item in reports[:500]:
            if not isinstance(item, dict):
                continue
            user = str(item.get("user") or "")
            ip = str(item.get("ip") or "")
            ids = [str(value) for value in (item.get("ids") or [])[:40] if str(value)]
            if (
                ids
                and re.fullmatch(r"[A-Za-z0-9_-]{1,40}", user)
                and re.fullmatch(r"[0-9A-Fa-f:.]+", ip)
            ):
                clean.append({"user": user, "ip": ip, "ids": ids})
        flows = []
        for item in (payload.get("flows") or [])[:800]:
            if not isinstance(item, dict):
                continue
            flow_user = str(item.get("user") or "")
            flow_id = str(item.get("id") or "")
            proto = str(item.get("proto") or "other")
            if proto not in PROTO_LABELS:
                proto = "other"
            try:
                up = int(item.get("up") or 0)
                down = int(item.get("down") or 0)
            except (TypeError, ValueError):
                continue
            if (
                re.fullmatch(r"[A-Za-z0-9_-]{1,40}", flow_user)
                and re.fullmatch(r"[A-Za-z0-9_-]{1,80}", flow_id)
                and 0 <= up <= 10**15
                and 0 <= down <= 10**15
            ):
                flows.append({"user": flow_user, "id": flow_id, "up": up, "down": down, "proto": proto})
        now = time.time()
        with DEVICE_LOCK:
            close = admit_devices(clean, now, DEVICE_SEEN)
            remember_health(self.peer_ip(), payload.get("stats"), len({item["user"] for item in clean}), now)
            usage, node_rows, online_minute, online_now = ingest_report(self.peer_ip(), flows, now)
        save_usage(usage, node_rows, online_minute, online_now)
        self.send_bytes(200, "application/json", json.dumps({"close": close}).encode())

    def handle_post(self) -> None:
        if self.redirect_sub_site():
            return
        parsed = urlparse(self.path)
        if is_xplm() and parsed.path in XPLM_POST_BLOCKED:
            self.send_bytes(403, "text/plain; charset=utf-8", "Только просмотр.\n".encode())
            return
        if parsed.path == "/internal/sessions":
            self.device_limit()
            return
        if parsed.path == "/admin/brand-admin":
            self.save_brand_admin()
            return
        if parsed.path == "/admin/login":
            self.login()
            return
        if parsed.path == "/admin/extend":
            self.extend_profile()
            return
        if parsed.path == "/admin/delete":
            self.delete_profile()
            return
        if parsed.path == "/admin/2fa":
            if not brand()["admin_totp"]:
                self.redirect("/admin/")
                return
            self.enroll_totp()
            return
        if parsed.path == "/admin/promo":
            self.create_promo_code()
            return
        if parsed.path == "/admin/promo/delete":
            self.delete_promo_code()
            return
        if parsed.path == "/admin/cash/refund":
            self.record_cash_refund()
            return
        if parsed.path == "/admin/partner":
            self.create_partner_link()
            return
        if parsed.path == "/admin/partner/delete":
            self.delete_partner_link()
            return
        if parsed.path == "/app/start":
            self.app_start()
            return
        if parsed.path == "/app/login":
            self.app_login()
            return
        if parsed.path == "/app/login/code":
            self.app_login_code()
            return
        if parsed.path == "/app/login/status":
            self.app_login_status()
            return
        if parsed.path == "/app/link-email":
            self.app_link_email_start()
            return
        if parsed.path == "/app/link-email/confirm":
            self.app_link_email_confirm()
            return
        if parsed.path == "/app/devices":
            self.app_devices()
            return
        if parsed.path == "/app/devices/kick":
            self.app_devices_kick()
            return
        if parsed.path == "/app/client-events":
            self.app_client_events()
            return
        if parsed.path == "/referral":
            self.referral_lookup()
            return
        if parsed.path == "/restore-mail":
            self.resend_access()
            return
        if parsed.path == "/platega/callback":
            self.platega_callback()
            return
        if parsed.path == "/pay":
            self.start_payment()
            return
        if parsed.path == "/promo":
            self.apply_site_promo()
            return
        if parsed.path == "/verify":
            self.verify_email_code()
            return
        if parsed.path == "/verify/resend":
            self.resend_verify_code()
            return
        if parsed.path == "/verify/email-fallback":
            self.verify_email_fallback()
            return
        if parsed.path != "/signup":
            self.send_bytes(404, "text/plain; charset=utf-8", b"not found\n")
            return
        self.signup()

    def signup(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 4000:
            status, kind, payload = home("Некорректная форма.")
            self.send_bytes(status, kind, payload)
            return
        raw = self.rfile.read(length).decode("utf-8", "replace")
        form = parse_qs(raw)
        if (form.get("company") or [""])[0].strip():
            note_captcha_hit(self.client_ip())
            status, kind, payload = home("Некорректная форма.")
            self.send_bytes(status, kind, payload)
            return
        contact = (form.get("contact") or [""])[0]
        ip = self.client_ip()
        need_cap = signup_suspicious(ip)
        if need_cap and not captcha_ok(
            (form.get("captcha_token") or [""])[0],
            (form.get("captcha") or [""])[0],
        ):
            note_captcha_hit(ip)
            cap_q, cap_t = issue_captcha()
            status, kind, payload = home(
                "Подтвердите, что вы не робот: решите пример.",
                contact=contact,
                captcha_q=cap_q,
                captcha_token=cap_t,
            )
            self.send_bytes(status, kind, payload)
            return
        try:
            normal = normalize_email(contact)
            known = lookup_contact(normal)
        except ValueError as exc:
            cap_q = cap_t = ""
            if need_cap:
                cap_q, cap_t = issue_captcha()
            status, kind, payload = home(
                str(exc),
                contact=contact,
                captcha_q=cap_q,
                captcha_token=cap_t,
            )
            self.send_bytes(status, kind, payload)
            return
        if known is not None:
            if not int(known["verified"] or 0):
                status, kind, payload = pending_verify_page(known)
                self.send_bytes(status, kind, payload)
                return
            status, kind, payload = home(
                notice=account_status(known),
                restore=restore_channel(normal),
                contact=normal,
            )
            self.send_bytes(status, kind, payload)
            return
        ref = referral_code((form.get("ref") or [""])[0]) or referral_code(
            cookie_value(self.headers.get("Cookie"), "kpax_ref")
        )
        partner = resolve_partner((form.get("p") or [""])[0]) or resolve_partner(
            cookie_value(self.headers.get("Cookie"), partner_cookie_name())
        )
        try:
            user = create_user(contact, ip or "unknown", pending_ref=ref, partner=partner)
        except ValueError as exc:
            text = str(exc)
            cap_q = cap_t = ""
            if signup_suspicious(ip):
                cap_q, cap_t = issue_captcha()
            if text == TAKEN:
                status, kind, payload = home(
                    notice="Эта почта уже используется.",
                    restore=restore_channel(normal),
                    contact=normal,
                    captcha_q=cap_q,
                    captcha_token=cap_t,
                )
            else:
                status, kind, payload = home(
                    text,
                    contact=contact,
                    captcha_q=cap_q,
                    captcha_token=cap_t,
                )
            self.send_bytes(status, kind, payload)
            return
        except Exception as exc:  # noqa: BLE001
            print("signup failed", exc, flush=True)
            status, kind, payload = home("Не получилось выдать доступ. Попробуйте через минуту.")
            self.send_bytes(status, kind, payload)
            return
        notice = (
            "Код отправлен на почту. Проверьте «Спам»."
            if not str(user["contact"]).startswith("@")
            else ""
        )
        status, kind, payload = pending_verify_page(user, notice=notice)
        self.send_bytes(status, kind, payload)

    def verify_email_code(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 4000:
            status, kind, payload = home("Некорректная форма.")
            self.send_bytes(status, kind, payload)
            return
        form = parse_qs(self.rfile.read(length).decode("utf-8", "replace"))
        token = (form.get("token") or [""])[0].strip()
        code = (form.get("code") or [""])[0].strip()
        user = user_by_verify_token(token)
        if user is None:
            status, kind, payload = home("Сессия подтверждения устарела. Зарегистрируйтесь снова.")
            self.send_bytes(status, kind, payload)
            return
        if str(user["contact"]).startswith("@"):
            status, kind, payload = pending_verify_page(user, error="Для этого аккаунта нужен Telegram-бот.")
            self.send_bytes(status, kind, payload)
            return
        ip = self.client_ip()
        if signup_suspicious(ip) and not captcha_ok(
            (form.get("captcha_token") or [""])[0],
            (form.get("captcha") or [""])[0],
        ):
            note_captcha_hit(ip)
            cap_q, cap_t = issue_captcha()
            status, kind, payload = pending_verify_page(
                user,
                error="Подтвердите, что вы не робот.",
                captcha_q=cap_q,
                captcha_token=cap_t,
            )
            self.send_bytes(status, kind, payload)
            return
        sent_at = int(user["verify_sent_at"] or 0)
        if not sent_at or now_ts() - sent_at > VERIFY_TTL:
            status, kind, payload = pending_verify_page(
                user,
                error="Код устарел. Нажмите «Отправить код ещё раз».",
            )
            self.send_bytes(status, kind, payload)
            return
        if not code or not hmac.compare_digest(hash_verify_code(code), str(user["verify_code"] or "")):
            note_captcha_hit(ip)
            cap_q = cap_t = ""
            if signup_suspicious(ip):
                cap_q, cap_t = issue_captcha()
            status, kind, payload = pending_verify_page(
                user,
                error="Неверный код.",
                captcha_q=cap_q,
                captcha_token=cap_t,
            )
            self.send_bytes(status, kind, payload)
            return
        try:
            activated, invited, promo_note = activate_user(user)
        except Exception as exc:  # noqa: BLE001
            print("activate failed", type(exc).__name__, flush=True)
            status, kind, payload = pending_verify_page(user, error="Не получилось активировать. Попробуйте через минуту.")
            self.send_bytes(status, kind, payload)
            return
        mailed = deliver_access_mail(activated)
        status, kind, payload = welcome(activated, invited, mailed, promo_note)
        self.send_bytes(status, kind, payload)

    def resend_verify_code(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        form = parse_qs(self.rfile.read(length).decode("utf-8", "replace")) if length > 0 else {}
        token = (form.get("token") or [""])[0].strip()
        user = user_by_verify_token(token)
        if user is None:
            status, kind, payload = home("Сессия подтверждения устарела. Зарегистрируйтесь снова.")
            self.send_bytes(status, kind, payload)
            return
        if str(user["contact"]).startswith("@"):
            status, kind, payload = pending_verify_page(user)
            self.send_bytes(status, kind, payload)
            return
        last = int(user["verify_sent_at"] or 0)
        if last and now_ts() - last < 60:
            status, kind, payload = pending_verify_page(user, error="Подождите минуту перед повторной отправкой.")
            self.send_bytes(status, kind, payload)
            return
        code = refresh_verify_challenge(user)
        user = user_by_verify_token(token) or user
        ok = deliver_verify_mail(user, code)
        status, kind, payload = pending_verify_page(
            user,
            notice="Код отправлен ещё раз." if ok else "",
            error="" if ok else "Не получилось отправить письмо. Попробуйте позже.",
        )
        self.send_bytes(status, kind, payload)

    def verify_email_fallback(self) -> None:
        """Telegram pending → switch contact to email and send code (TG may be blocked)."""
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 4000:
            status, kind, payload = home("Некорректная форма.")
            self.send_bytes(status, kind, payload)
            return
        form = parse_qs(self.rfile.read(length).decode("utf-8", "replace"))
        token = (form.get("token") or [""])[0].strip()
        email_raw = (form.get("email") or [""])[0]
        user = user_by_verify_token(token)
        if user is None or not str(user["contact"]).startswith("@"):
            status, kind, payload = home("Сессия подтверждения устарела. Зарегистрируйтесь снова.")
            self.send_bytes(status, kind, payload)
            return
        try:
            email = normalize_contact(email_raw)
            if email.startswith("@"):
                raise ValueError("Укажите почту.")
        except ValueError as exc:
            status, kind, payload = pending_verify_page(user, error=str(exc))
            self.send_bytes(status, kind, payload)
            return
        taken = lookup_contact(email)
        if taken is not None and int(taken["id"]) != int(user["id"]):
            status, kind, payload = pending_verify_page(user, error="Эта почта уже используется.")
            self.send_bytes(status, kind, payload)
            return
        code = new_email_code()
        nick = str(user["contact"] or "")
        with LOCK:
            conn = db()
            conn.execute(
                """
                UPDATE users SET contact=?, telegram_nick=?, verify_code=?, verify_sent_at=?
                WHERE id=? AND verified=0
                """,
                (email, nick, hash_verify_code(code), now_ts(), int(user["id"])),
            )
            conn.commit()
            fresh = conn.execute("SELECT * FROM users WHERE id=?", (int(user["id"]),)).fetchone()
            conn.close()
        if fresh is None:
            status, kind, payload = home("Сессия подтверждения устарела.")
            self.send_bytes(status, kind, payload)
            return
        ok = deliver_verify_mail(fresh, code)
        status, kind, payload = pending_verify_page(
            fresh,
            notice="Код отправлен на почту." if ok else "",
            error="" if ok else "Не получилось отправить письмо.",
        )
        self.send_bytes(status, kind, payload)

    def send_json(self, status: int, payload: dict) -> None:
        self.send_bytes(status, "application/json", json.dumps(payload, ensure_ascii=False).encode())

    def app_start(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 2000:
            self.send_json(400, {"error": "Укажите почту: name@mail.ru."})
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            contact = normalize_email(str(payload.get("contact") or ""))
            ref = referral_code(str(payload.get("ref") or ""))
        except (json.JSONDecodeError, UnicodeError, ValueError) as exc:
            message = str(exc) if isinstance(exc, ValueError) else "Укажите почту: name@mail.ru."
            self.send_json(400, {"error": message})
            return
        known = lookup_contact(contact)
        if known is not None:
            if not int(known["verified"] or 0):
                self.send_json(
                    200,
                    {
                        "created": False,
                        "pending_verify": True,
                        "public_id": known["public_id"],
                        "expires_at": int(known["expires_at"]),
                        "channel": "email",
                        "error": "Введите код из письма в приложении или на сайте.",
                    },
                )
                return
            self.send_json(
                200,
                {
                    "created": False,
                    "public_id": known["public_id"],
                    "expires_at": int(known["expires_at"]),
                    "active": bool(known["active"]) and int(known["expires_at"]) > now_ts(),
                    "channel": "email",
                    "needs_email_link": user_needs_email_link(known),
                },
            )
            return
        partner = resolve_partner(str(payload.get("p") or payload.get("partner") or "")) or resolve_partner(
            cookie_value(self.headers.get("Cookie"), partner_cookie_name())
        )
        try:
            user = create_user(contact, self.client_ip(), pending_ref=ref, partner=partner)
        except ValueError as exc:
            self.send_json(400, {"error": str(exc)})
            return
        except Exception as exc:  # noqa: BLE001
            print("app start failed", exc, flush=True)
            self.send_json(500, {"error": "Не получилось выдать доступ. Попробуйте через минуту."})
            return
        self.send_json(
            200,
            {
                "created": True,
                "pending_verify": True,
                "public_id": user["public_id"],
                "expires_at": int(user["expires_at"]),
                "channel": "email",
                "error": "Код отправлен на почту. Введите его в приложении.",
            },
        )

    def app_login(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 2000:
            self.send_json(400, {"error": "Укажите почту: name@mail.ru."})
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Укажите почту: name@mail.ru.")
            raw_contact = str(payload.get("contact") or "")
            ref = referral_code(str(payload.get("ref") or ""))
            # New accounts: email only. Legacy @nick login only if the account already exists.
            try:
                contact = normalize_email(raw_contact)
            except ValueError:
                contact = normalize_contact(raw_contact)
                if not contact_is_telegram(contact):
                    raise
                existing = lookup_contact(contact)
                if existing is None:
                    raise ValueError(
                        "Новые аккаунты — только по почте. Укажите name@mail.ru."
                    ) from None
        except (json.JSONDecodeError, UnicodeError, ValueError) as exc:
            message = str(exc) if isinstance(exc, ValueError) else "Укажите почту: name@mail.ru."
            self.send_json(400, {"error": message})
            return
        channel = "telegram" if contact_is_telegram(contact) else "email"
        partner = resolve_partner(str(payload.get("p") or payload.get("partner") or "")) or resolve_partner(
            cookie_value(self.headers.get("Cookie"), partner_cookie_name())
        )
        created = False
        user = lookup_contact(contact)
        if user is None:
            if channel == "telegram":
                self.send_json(
                    400,
                    {"error": "Новые аккаунты — только по почте. Укажите name@mail.ru."},
                )
                return
            try:
                user = create_user(contact, self.client_ip(), pending_ref=ref, partner=partner)
                created = True
            except ValueError as exc:
                self.send_json(400, {"error": str(exc)})
                return
            except Exception as exc:  # noqa: BLE001
                print("app login create failed", type(exc).__name__, flush=True)
                self.send_json(500, {"error": "Не получилось начать вход. Попробуйте через минуту."})
                return
        email_code = ""
        code_hash = ""
        if channel == "email":
            email_code = new_email_code()
            code_hash = hash_verify_code(email_code)
        session = create_app_login(int(user["id"]), code_hash=code_hash)
        bot_url = bot_app_login_url(session) if channel == "telegram" else ""
        if channel == "email":
            mailed = deliver_app_login_mail(
                contact,
                session,
                str(user["public_id"]),
                created=created,
                code=email_code,
            )
            if not mailed:
                self.send_json(
                    500,
                    {"error": "Не получилось отправить письмо. Проверьте адрес или попробуйте позже."},
                )
                return
        if channel == "telegram":
            hint = (
                "Откройте бота и нажмите «Подтвердить» — доступ появится в приложении. "
                "Потом привяжите почту в профиле."
            )
        else:
            hint = (
                "Введите код из письма в приложении. Можно также нажать кнопку в письме."
                if created
                else "Введите код из письма в приложении."
            )
        self.send_json(
            200,
            {
                "created": created,
                "pending_verify": True,
                "session": session,
                "channel": channel,
                "bot_url": bot_url,
                "public_id": user["public_id"],
                "expires_at": int(user["expires_at"]),
                "hint": hint,
                "needs_email_link": user_needs_email_link(user),
            },
        )

    def app_login_code(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 2000:
            self.send_json(400, {"status": "error", "error": "Укажите код из письма."})
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            session = str((payload or {}).get("session") or "").strip()
            code = str((payload or {}).get("code") or "").strip()
        except (json.JSONDecodeError, UnicodeError, TypeError):
            self.send_json(400, {"status": "error", "error": "Укажите код из письма."})
            return
        if not session or not code:
            self.send_json(400, {"status": "error", "error": "Укажите код из письма."})
            return
        row = app_login_row(session)
        if row is None or app_login_expired(row):
            self.send_json(400, {"status": "expired", "error": "Сессия устарела. Запросите вход ещё раз."})
            return
        stored = str(row["code_hash"] or "")
        if not stored or not hmac.compare_digest(hash_verify_code(code), stored):
            self.send_json(400, {"status": "error", "error": "Неверный код."})
            return
        user, error = finish_app_login(session)
        if error:
            self.send_json(400, {"status": "error", "error": error})
            return
        status, ready = consume_app_login(session)
        if status != "ready":
            self.send_json(200, {"status": "pending"})
            return
        self.send_json(200, ready)

    def app_link_email_start(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 2000:
            self.send_json(400, {"ok": False, "error": "Укажите почту."})
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            token = str((payload or {}).get("token") or "").strip()
            email = normalize_email(str((payload or {}).get("email") or ""))
        except (json.JSONDecodeError, UnicodeError, ValueError, TypeError) as exc:
            message = str(exc) if isinstance(exc, ValueError) else "Укажите почту."
            self.send_json(400, {"ok": False, "error": message})
            return
        user = user_by_sub_token(token)
        if user is None or not int(user["verified"] or 0):
            self.send_json(404, {"ok": False, "error": "Аккаунт не найден."})
            return
        if not user_needs_email_link(user):
            self.send_json(200, {"ok": True, "already": True})
            return
        taken = lookup_contact(email)
        if taken is not None and int(taken["id"]) != int(user["id"]):
            self.send_json(
                400,
                {
                    "ok": False,
                    "error": "Эта почта уже используется другим аккаунтом. Напишите на support@%s"
                    % brand()["host"],
                },
            )
            return
        code = new_email_code()
        with LOCK:
            conn = db()
            conn.execute(
                """
                UPDATE users SET verify_code=?, verify_sent_at=?, verify_token=?
                WHERE id=? AND brand=?
                """,
                (
                    hash_verify_code(code),
                    now_ts(),
                    "link:" + email,
                    int(user["id"]),
                    brand_id(),
                ),
            )
            conn.commit()
            conn.close()
        ok = deliver_verify_mail(user, code)
        if not ok:
            # deliver uses contact; TG contact cannot receive mail — send to new email
            mail = brand_mail()
            if mail:
                try:
                    send_mail(
                        mail,
                        email,
                        "Код подтверждения K-Pax",
                        "Код подтверждения K-Pax: %s\n\n"
                        "Введите его в приложении, чтобы привязать почту к аккаунту.\n"
                        "Если вы не запрашивали это — удалите письмо." % code,
                    )
                    ok = True
                except Exception as exc:  # noqa: BLE001
                    print("link email mail failed", type(exc).__name__, flush=True)
                    ok = False
        if not ok:
            self.send_json(500, {"ok": False, "error": "Не получилось отправить письмо."})
            return
        self.send_json(200, {"ok": True, "hint": "Код отправлен на почту."})

    def app_link_email_confirm(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 2000:
            self.send_json(400, {"ok": False, "error": "Укажите код."})
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            token = str((payload or {}).get("token") or "").strip()
            code = str((payload or {}).get("code") or "").strip()
        except (json.JSONDecodeError, UnicodeError, TypeError):
            self.send_json(400, {"ok": False, "error": "Укажите код."})
            return
        user = user_by_sub_token(token)
        if user is None or not int(user["verified"] or 0):
            self.send_json(404, {"ok": False, "error": "Аккаунт не найден."})
            return
        pending = str(user["verify_token"] or "")
        if not pending.startswith("link:"):
            self.send_json(400, {"ok": False, "error": "Сначала запросите код на почту."})
            return
        email = pending[5:]
        sent_at = int(user["verify_sent_at"] or 0)
        if not sent_at or now_ts() - sent_at > VERIFY_TTL:
            self.send_json(400, {"ok": False, "error": "Код устарел. Запросите новый."})
            return
        if not code or not hmac.compare_digest(
            hash_verify_code(code), str(user["verify_code"] or "")
        ):
            self.send_json(400, {"ok": False, "error": "Неверный код."})
            return
        try:
            fresh = bind_email_to_telegram_user(user, email)
        except ValueError as exc:
            self.send_json(400, {"ok": False, "error": str(exc)})
            return
        with LOCK:
            conn = db()
            conn.execute(
                """
                UPDATE users SET verify_code='', verify_token='', verify_sent_at=0
                WHERE id=? AND brand=?
                """,
                (int(fresh["id"]), brand_id()),
            )
            conn.commit()
            conn.close()
        self.send_json(
            200,
            {
                "ok": True,
                "contact": str(fresh["contact"]),
                "needs_email_link": False,
            },
        )

    def app_login_status(self) -> None:
        token = (self.headers.get("X-Session") or self.headers.get("X-App-Session") or "").strip()
        if not token and self.command != "GET":
            length = int(self.headers.get("Content-Length") or "0")
            if length <= 0 or length > 2000:
                self.send_json(400, {"status": "expired", "error": "Нет сессии."})
                return
            try:
                payload = json.loads(self.rfile.read(length).decode("utf-8"))
                token = str((payload or {}).get("session") or "").strip()
            except (json.JSONDecodeError, UnicodeError, TypeError):
                self.send_json(400, {"status": "expired", "error": "Нет сессии."})
                return
        if not token:
            token = (parse_qs(urlparse(self.path).query).get("session") or [""])[0].strip()
            if token:
                print("[deprecated] /app/login/status session in query; prefer POST body or X-Session", flush=True)
        if not token:
            self.send_json(400, {"status": "expired", "error": "Нет сессии."})
            return
        status, payload = consume_app_login(token)
        code = 200 if status != "expired" else 200
        self.send_json(code, payload)

    def app_devices(self) -> None:
        token = (self.headers.get("X-Token") or self.headers.get("X-App-Token") or "").strip()
        if not token and self.command != "GET":
            length = int(self.headers.get("Content-Length") or "0")
            if 0 < length <= 2000:
                try:
                    body = json.loads(self.rfile.read(length).decode("utf-8"))
                    token = str((body or {}).get("token") or "").strip()
                except (json.JSONDecodeError, UnicodeError, TypeError):
                    token = ""
        if not token:
            token = (parse_qs(urlparse(self.path).query).get("token") or [""])[0].strip()
            if token:
                print("[deprecated] /app/devices token in query; prefer POST body or X-Token", flush=True)
        payload, error = devices_for_token(token)
        if error or payload is None:
            self.send_json(404, {"error": "Ссылка не найдена.", "devices": []})
            return
        self.send_json(200, payload)

    def app_client_events(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > CLIENT_EVENTS_BODY_MAX:
            self.send_json(400, {"ok": False, "error": "bad_body"})
            return
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(body, dict):
                raise ValueError("bad_body")
        except (json.JSONDecodeError, UnicodeError, TypeError, ValueError):
            self.send_json(400, {"ok": False, "error": "bad_json"})
            return
        token = (self.headers.get("X-Token") or self.headers.get("X-App-Token") or "").strip()
        if not token:
            token = str(body.get("token") or "").strip()
        session_id = str(body.get("session_id") or "").strip()
        events = body.get("events")
        if not isinstance(events, list):
            self.send_json(400, {"ok": False, "error": "bad_events"})
            return
        payload, status, error = ingest_client_events(
            token,
            session_id,
            events,
            self.client_ip(),
        )
        if payload is None:
            if status == 429:
                self.send_json(429, {"ok": False, "error": "rate_limited"})
                return
            if status == 404:
                self.send_json(404, {"ok": False, "error": "not_found"})
                return
            self.send_json(400, {"ok": False, "error": error or "bad_request"})
            return
        self.send_json(200, payload)

    def app_devices_kick(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 2000:
            self.send_json(400, {"ok": False, "error": "Нет данных."})
            return
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            token = str((body or {}).get("token") or "").strip()
            device_id = str((body or {}).get("device_id") or "").strip()
        except (json.JSONDecodeError, UnicodeError, TypeError):
            self.send_json(400, {"ok": False, "error": "Нет данных."})
            return
        ok, error = kick_device_for_token(token, device_id)
        if not ok:
            self.send_json(400, {"ok": False, "error": error or "Не удалось отключить."})
            return
        self.send_json(200, {"ok": True})

    def app_confirm_click(self) -> None:
        token = (parse_qs(urlparse(self.path).query).get("t") or [""])[0].strip()
        user, error = finish_app_login(token)
        if error:
            status, kind, payload = app_confirm_page(error=error)
            self.send_bytes(status, kind, payload)
            return
        status, kind, payload = app_confirm_page(
            notice="Всё готово. Закройте эту вкладку и вернитесь в приложение K-Pax — доступ подгрузится сам."
        )
        self.send_bytes(status, kind, payload)
        print("app login confirmed", user["public_id"] if user else "?", flush=True)

    def referral_lookup(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 2000:
            self.send_json(400, {"found": False, "error": "Укажите почту или Telegram."})
            return
        ip = self.client_ip()
        if referral_limited(ip):
            self.send_json(429, {"found": False, "error": "Слишком много попыток. Попробуйте позже."})
            return
        note_referral_lookup(ip)
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Укажите почту или Telegram.")
            contact = normalize_contact(str(payload.get("contact") or ""))
        except (json.JSONDecodeError, UnicodeError, ValueError) as exc:
            message = str(exc) if isinstance(exc, ValueError) else "Укажите почту или Telegram."
            self.send_json(400, {"found": False, "error": message})
            return
        known = lookup_contact(contact)
        if known is None:
            self.send_json(
                200,
                {
                    "found": False,
                    "error": "Этой почты ещё нет. Закройте окно и нажмите «Получить ссылку».",
                    "signup": True,
                },
            )
            return
        self.send_json(
            200,
            {"found": True, "url": "https://k-pax.space/?ref=" + known["public_id"]},
        )

    def resend_access(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 2000:
            self.send_json(400, {"sent": False, "error": "Укажите почту."})
            return
        ip = self.client_ip()
        if resend_limited(ip):
            self.send_json(429, {"sent": False, "error": "Слишком много попыток. Попробуйте позже."})
            return
        note_resend(ip)
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Укажите почту.")
            contact = normalize_contact(str(payload.get("contact") or ""))
        except (json.JSONDecodeError, UnicodeError, ValueError) as exc:
            message = str(exc) if isinstance(exc, ValueError) else "Укажите почту."
            self.send_json(400, {"sent": False, "error": message})
            return
        if contact.startswith("@"):
            self.send_json(400, {"sent": False, "error": "Для Telegram откройте бота @KPax_Space_bot."})
            return
        user = user_for_restore(contact)
        if user is None:
            self.send_json(200, {"sent": False, "error": "Эта почта не указана в K-Pax."})
            return
        if not restore_allowed(contact, "email"):
            self.send_json(200, {"sent": False, "error": "Ссылка уже отправлена. Подождите и нажмите ещё раз."})
            return
        mail = CFG.get("mail_restore")
        if not isinstance(mail, dict) or not mail.get("user"):
            self.send_json(500, {"sent": False, "error": "Не получилось отправить письмо. Попробуйте через минуту."})
            return
        try:
            send_restore_mail(mail, contact, access_message(user))
            note_restore(contact, "email")
        except Exception as exc:  # noqa: BLE001
            print("resend mail failed", user["public_id"], type(exc).__name__, flush=True)
            self.send_json(500, {"sent": False, "error": "Не получилось отправить письмо. Попробуйте через минуту."})
            return
        print("resent", user["public_id"], flush=True)
        self.send_json(200, {"sent": True})

    def apply_site_promo(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 4000:
            status, kind, payload = home(promo_error="Некорректная форма.")
            self.send_bytes(status, kind, payload)
            return
        raw = self.rfile.read(length).decode("utf-8", "replace")
        form = parse_qs(raw)
        contact = (form.get("contact") or [""])[0]
        code_raw = (form.get("code") or [""])[0]
        if (form.get("company") or [""])[0].strip():
            status, kind, payload = home(promo_error="Некорректная форма.", promo_contact=contact, promo_code=code_raw)
            self.send_bytes(status, kind, payload)
            return
        ip = self.client_ip()
        if promo_limited(ip):
            status, kind, payload = home(
                promo_error="Слишком много попыток. Попробуйте позже.",
                promo_contact=contact,
                promo_code=code_raw,
            )
            self.send_bytes(status, kind, payload)
            return
        note_promo_try(ip)
        try:
            normal = normalize_contact(contact)
            promo_ready(code_raw)
        except ValueError as exc:
            status, kind, payload = home(
                promo_error=str(exc),
                promo_contact=contact,
                promo_code=code_raw,
            )
            self.send_bytes(status, kind, payload)
            return
        known = user_by_contact(normal)
        if known is None:
            if too_many(ip):
                status, kind, payload = home(
                    promo_error="Слишком много попыток. Попробуйте позже.",
                    promo_contact=normal,
                    promo_code=code_raw,
                )
                self.send_bytes(status, kind, payload)
                return
            ref = referral_code(cookie_value(self.headers.get("Cookie"), "kpax_ref"))
            partner = resolve_partner(
                cookie_value(self.headers.get("Cookie"), partner_cookie_name())
            )
            try:
                user = create_user(
                    normal,
                    ip or "unknown",
                    pending_ref=ref,
                    pending_promo=code_raw.strip()[:32],
                    partner=partner,
                )
            except ValueError as exc:
                status, kind, payload = home(
                    promo_error=str(exc),
                    promo_contact=normal,
                    promo_code=code_raw,
                )
                self.send_bytes(status, kind, payload)
                return
            except Exception as exc:  # noqa: BLE001
                print("promo signup failed", type(exc).__name__, flush=True)
                status, kind, payload = home(
                    promo_error="Не получилось применить промокод. Попробуйте через минуту.",
                    promo_contact=normal,
                    promo_code=code_raw,
                )
                self.send_bytes(status, kind, payload)
                return
            notice = (
                "Промокод сохранится после подтверждения. Код отправлен на почту."
                if not str(user["contact"]).startswith("@")
                else "Промокод сохранится после подтверждения в боте."
            )
            status, kind, payload = pending_verify_page(user, notice=notice)
            self.send_bytes(status, kind, payload)
            return
        if not int(known["verified"] or 0):
            status, kind, payload = pending_verify_page(
                known,
                notice="Сначала подтвердите контакт — промокод можно ввести после активации.",
            )
            self.send_bytes(status, kind, payload)
            return
        try:
            message = redeem_promo(known, code_raw)
        except ValueError as exc:
            status, kind, payload = home(
                promo_error=str(exc),
                promo_contact=normal,
                promo_code=code_raw,
            )
            self.send_bytes(status, kind, payload)
            return
        status, kind, payload = home(
            promo_notice=message,
            promo_contact=normal,
            index=True,
        )
        self.send_bytes(status, kind, payload, index=True)

    def start_payment(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 4000:
            status, kind, payload = pay_page("Некорректная форма.")
            self.send_bytes(status, kind, payload)
            return
        raw = self.rfile.read(length).decode("utf-8", "replace")
        form = parse_qs(raw)
        contact = (form.get("contact") or [""])[0]
        if (form.get("company") or [""])[0].strip():
            status, kind, payload = pay_page("Некорректная форма.", contact)
            self.send_bytes(status, kind, payload)
            return
        ip = self.client_ip()
        if pay_limited(ip):
            status, kind, payload = pay_page("Слишком много попыток. Попробуйте позже.", contact)
            self.send_bytes(status, kind, payload)
            return
        try:
            normal = normalize_contact(contact)
        except ValueError as exc:
            status, kind, payload = pay_page(str(exc), contact)
            self.send_bytes(status, kind, payload)
            return
        user = user_by_contact(normal)
        if user is None:
            status, kind, payload = pay_page(
                "Этой почты или ника ещё нет. Сначала получите ссылку на главной.",
                normal,
            )
            self.send_bytes(status, kind, payload)
            return
        if not int(user["verified"] or 0):
            status, kind, payload = pending_verify_page(user)
            self.send_bytes(status, kind, payload)
            return
        outcome, detail = begin_payment(user, ip)
        if outcome != "ok":
            status, kind, payload = pay_page(detail, normal)
            self.send_bytes(status, kind, payload)
            return
        self.send_response(303)
        self.send_header("Location", detail)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def platega_callback(self) -> None:
        merchant = self.headers.get("X-MerchantId") or ""
        secret = self.headers.get("X-Secret") or ""
        shop = platega_header_brand(merchant, secret)
        if shop is None:
            self.send_bytes(401, "text/plain; charset=utf-8", b"unauthorized\n")
            return
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0 or length > 8000:
            self.send_bytes(400, "text/plain; charset=utf-8", b"bad request\n")
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("payload")
            outcome = accept_platega_callback(payload, shop)
        except Exception as exc:  # noqa: BLE001
            print("platega callback failed", type(exc).__name__, flush=True)
            self.send_bytes(500, "text/plain; charset=utf-8", b"error\n")
            return
        if outcome == "unconfirmed":
            self.send_bytes(500, "text/plain; charset=utf-8", b"error\n")
            return
        self.send_bytes(200, "text/plain; charset=utf-8", b"ok\n")

    def client_ip(self) -> str:
        if is_xplm():
            edge_client = (self.headers.get("X-Edge-Client") or "").strip()
            if re.fullmatch(r"[0-9A-Fa-f:.]{3,45}", edge_client):
                return edge_client
        return (self.headers.get("X-Forwarded-For") or self.client_address[0]).split(",")[0].strip() or "unknown"

    def edge_brand(self) -> str:
        """X-Plm traffic arrives through its own server with a shared secret."""
        secret = self.headers.get("X-Plm-Edge") or ""
        if not secret:
            return "kpax"
        cfg = brand_cfg("xplm")
        expected = str(cfg.get("edge_secret") or "")
        allowed = {str(item) for item in (cfg.get("edge_ips") or [])}
        if STAGE:
            allowed |= {"127.0.0.1"}
        if not expected or len(secret) != len(expected) or not hmac.compare_digest(secret, expected):
            return "kpax"
        if self.peer_ip() not in allowed:
            return "kpax"
        return "xplm"

    def logged_in(self) -> bool:
        raw = self.headers.get("Cookie") or ""
        for part in raw.split(";"):
            name, _, value = part.strip().partition("=")
            if name == brand()["cookie"] and session_ok(value):
                return True
        return False

    def redirect(self, location: str, cookie: str = "", clear_cookie: bool = False) -> None:
        self.send_response(303)
        name = brand()["cookie"]
        if cookie:
            self.send_header(
                "Set-Cookie",
                "%s=%s; HttpOnly; Secure; SameSite=Strict; Path=/admin; Max-Age=%d" % (name, cookie, 14 * 86400),
            )
        if clear_cookie:
            self.send_header("Set-Cookie", "%s=; HttpOnly; Secure; SameSite=Strict; Path=/admin; Max-Age=0" % name)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def show_admin(self, parsed) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        ok = (parse_qs(parsed.query).get("ok") or [""])[0]
        if re.fullmatch(PUBLIC_ID_RE, ok):
            self.redirect("/admin/users?ok=%s" % quote(ok))
            return
        self.redirect("/admin/stats")

    def show_stats(self) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        status, kind, payload = stats_page()
        self.send_bytes(status, kind, payload)

    def show_cash(self, parsed) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        if not is_xplm():
            self.redirect("/admin/stats")
            return
        qs = parse_qs(parsed.query)
        notice = ""
        if (qs.get("ok") or [""])[0] == "refund":
            notice = "Ручной возврат записан."
        status, kind, payload = xplm_cash_page(parsed.query, notice=notice)
        self.send_bytes(status, kind, payload)

    def record_cash_refund(self) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        if not is_xplm():
            self.redirect("/admin/stats")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        form = parse_qs(raw)
        raw_amount = (form.get("amount") or [""])[0].strip()
        note = re.sub(r"\s+", " ", (form.get("note") or [""])[0].strip())[:120]
        try:
            amount = int(raw_amount)
        except ValueError:
            amount = 0
        if amount < 1 or amount > 100000:
            status, kind, payload = xplm_cash_page(error="Укажите сумму возврата от 1 до 100000 ₽.")
            self.send_bytes(status, kind, payload)
            return
        with LOCK:
            conn = db()
            conn.execute(
                "INSERT INTO cash_refunds(brand, amount, note, created_at) VALUES('xplm', ?, ?, ?)",
                (amount, note, now_ts()),
            )
            conn.commit()
            conn.close()
        self.redirect("/admin/cash?ok=refund")

    def show_users(self, parsed) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        qs = parse_qs(parsed.query)
        ok = (qs.get("ok") or [""])[0]
        deleted = (qs.get("deleted") or [""])[0]
        if re.fullmatch(PUBLIC_ID_RE, deleted):
            notice = "Удалён: " + deleted
        elif re.fullmatch(PUBLIC_ID_RE, ok):
            notice = "Продлено: " + ok
        else:
            notice = ""
        status, kind, payload = users_page(parsed.query, notice)
        self.send_bytes(status, kind, payload)

    def show_client_events(self, parsed) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        status, kind, payload = client_events_page(parsed.query)
        self.send_bytes(status, kind, payload)

    def show_client_event_detail(self, event_id: int) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        status, kind, payload = client_event_detail_page(event_id)
        self.send_bytes(status, kind, payload)

    def show_user(self, public_id: str, query: str) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        notice = "Срок продлён." if (parse_qs(query).get("ok") or [""])[0] == "1" else ""
        status, kind, payload = user_stats_page(public_id.split("?", 1)[0], notice)
        self.send_bytes(status, kind, payload)

    def login(self) -> None:
        ip = self.client_ip()
        if login_blocked(ip):
            status, kind, payload = login_page("Слишком много попыток. Подождите 15 минут.")
            self.send_bytes(status, kind, payload)
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        form = parse_qs(raw)
        username = (form.get("username") or [""])[0]
        password = (form.get("password") or [""])[0]
        code = (form.get("code") or [""])[0]
        if user_ok(username) and password_ok(password):
            if not totp_secret() or totp_accept(code):
                self.redirect("/admin/stats", cookie=make_session())
                return
            note_login_fail(ip)
            time.sleep(0.4)
            print("admin login bad code", flush=True)
            status, kind, payload = login_page("Неверный или уже использованный код. Дождитесь следующего.")
            self.send_bytes(status, kind, payload)
            return
        note_login_fail(ip)
        time.sleep(0.4)
        status, kind, payload = login_page("Неверный логин или пароль.")
        self.send_bytes(status, kind, payload)

    def save_brand_admin(self) -> None:
        if not self.logged_in():
            self.redirect("/admin/")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        form = parse_qs(raw)
        bid = (form.get("brand") or [""])[0]
        if bid not in BRANDS or bid == "kpax":
            status, kind, payload = totp_page(error="Неизвестный сайт.")
            self.send_bytes(status, kind, payload)
            return
        try:
            set_brand_admin(bid, (form.get("username") or [""])[0], (form.get("password") or [""])[0])
        except ValueError as exc:
            status, kind, payload = totp_page(error=str(exc))
            self.send_bytes(status, kind, payload)
            return
        print("brand admin saved", bid, flush=True)
        status, kind, payload = totp_page(notice="Вход в админку %s сохранён." % BRANDS[bid]["name"])
        self.send_bytes(status, kind, payload)

    def enroll_totp(self) -> None:
        if not self.logged_in():
            self.redirect("/admin/")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        code = (parse_qs(raw).get("code") or [""])[0]
        if totp_secret():
            status, kind, payload = totp_page()
            self.send_bytes(status, kind, payload)
            return
        pending = admin_setting("totp_pending")
        counter = totp_match(pending, code) if pending else None
        if counter is None:
            status, kind, payload = totp_page(error="Код не подошёл. Проверьте время на телефоне и введите свежий код.")
            self.send_bytes(status, kind, payload)
            return
        enable_totp(pending)
        set_admin_setting("totp_last", str(counter))
        print("admin 2fa enabled", flush=True)
        self.redirect("/admin/", clear_cookie=True)

    def extend_profile(self) -> None:
        if not self.logged_in():
            self.redirect("/admin/")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        form = parse_qs(raw)
        public_id = (form.get("public_id") or [""])[0].strip()
        try:
            days = int((form.get("days") or ["0"])[0])
            user = extend_user(public_id, days)
            record_manual_extension(int(user["id"]), days)
        except ValueError as exc:
            status, kind, payload = user_stats_page(public_id, error=str(exc))
            self.send_bytes(status, kind, payload)
            return
        except Exception as exc:  # noqa: BLE001
            print("extend failed", public_id, exc, flush=True)
            status, kind, payload = user_stats_page(public_id, error="Не получилось продлить. Попробуйте через минуту.")
            self.send_bytes(status, kind, payload)
            return
        self.redirect("/admin/user/%s?ok=1" % quote(public_id))

    def delete_profile(self) -> None:
        if not self.logged_in():
            self.redirect("/admin/")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        form = parse_qs(raw)
        public_id = (form.get("public_id") or [""])[0].strip()
        if not re.fullmatch(PUBLIC_ID_RE, public_id):
            status, kind, payload = users_page("", error="Некорректный номер.")
            self.send_bytes(status, kind, payload)
            return
        try:
            delete_user(public_id)
        except ValueError:
            status, kind, payload = users_page("", error="Аккаунт уже не найден.")
            self.send_bytes(status, kind, payload)
            return
        except Exception as exc:  # noqa: BLE001
            print("admin delete failed", public_id, type(exc).__name__, flush=True)
            status, kind, payload = user_stats_page(
                public_id,
                error="Не получилось удалить. Попробуйте через минуту.",
            )
            self.send_bytes(status, kind, payload)
            return
        print("admin deleted", public_id, flush=True)
        self.redirect("/admin/users?deleted=%s" % quote(public_id))

    def show_partners(self) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        status, kind, payload = partners_page()
        self.send_bytes(status, kind, payload)

    def show_promos(self) -> None:
        if not self.logged_in():
            status, kind, payload = login_page()
            self.send_bytes(status, kind, payload)
            return
        status, kind, payload = promos_page()
        self.send_bytes(status, kind, payload)

    def create_promo_code(self) -> None:
        if not self.logged_in():
            self.redirect("/admin/")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        form = parse_qs(raw)
        try:
            days = int((form.get("days") or ["0"])[0])
            max_uses = int((form.get("max_uses") or ["0"])[0])
            promo_brand = brand_id() if is_xplm() else (form.get("brand") or ["kpax"])[0]
            code = create_promo(
                (form.get("code") or [""])[0],
                days,
                max_uses,
                promo_brand,
            )
        except ValueError as exc:
            status, kind, payload = promos_page(error=str(exc))
            self.send_bytes(status, kind, payload)
            return
        except Exception as exc:  # noqa: BLE001
            print("promo create failed", type(exc).__name__, flush=True)
            status, kind, payload = promos_page(error="Не получилось создать промокод.")
            self.send_bytes(status, kind, payload)
            return
        link = promo_partner_url(code, promo_brand)
        status, kind, payload = promos_page(notice="Промокод создан: %s. Ссылка: %s" % (code, link))
        self.send_bytes(status, kind, payload)

    def delete_promo_code(self) -> None:
        if not self.logged_in():
            self.redirect("/admin/")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        form = parse_qs(raw)
        try:
            code = deactivate_promo((form.get("code") or [""])[0])
        except ValueError as exc:
            status, kind, payload = promos_page(error=str(exc))
            self.send_bytes(status, kind, payload)
            return
        except Exception as exc:  # noqa: BLE001
            print("promo delete failed", type(exc).__name__, flush=True)
            status, kind, payload = promos_page(error="Не получилось удалить промокод.")
            self.send_bytes(status, kind, payload)
            return
        print("promo deleted", brand_id(), code, flush=True)
        status, kind, payload = promos_page(
            notice="Промокод удалён: %s. Новые вводы не сработают, уже активировавшим доступ сохранён."
            % code
        )
        self.send_bytes(status, kind, payload)

    def create_partner_link(self) -> None:
        if not self.logged_in():
            self.redirect("/admin/")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        form = parse_qs(raw)
        try:
            code = create_partner((form.get("code") or [""])[0], brand_id())
        except ValueError as exc:
            status, kind, payload = partners_page(error=str(exc))
            self.send_bytes(status, kind, payload)
            return
        except Exception as exc:  # noqa: BLE001
            print("partner create failed", type(exc).__name__, flush=True)
            status, kind, payload = partners_page(error="Не получилось создать партнёрскую ссылку.")
            self.send_bytes(status, kind, payload)
            return
        link = partner_url(code, brand_id())
        print("partner", brand_id(), code, flush=True)
        status, kind, payload = partners_page(notice="Ссылка: %s" % link)
        self.send_bytes(status, kind, payload)

    def delete_partner_link(self) -> None:
        if not self.logged_in():
            self.redirect("/admin/")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length).decode("utf-8", "replace") if 0 < length <= 2000 else ""
        form = parse_qs(raw)
        try:
            code = deactivate_partner((form.get("code") or [""])[0], brand_id())
        except ValueError as exc:
            status, kind, payload = partners_page(error=str(exc))
            self.send_bytes(status, kind, payload)
            return
        except Exception as exc:  # noqa: BLE001
            print("partner delete failed", type(exc).__name__, flush=True)
            status, kind, payload = partners_page(error="Не получилось удалить ссылку.")
            self.send_bytes(status, kind, payload)
            return
        print("partner deleted", brand_id(), code, flush=True)
        status, kind, payload = partners_page(notice="Ссылка удалена: %s" % code)
        self.send_bytes(status, kind, payload)


def days_remaining(expires_at: int) -> int:
    left = int(expires_at) - now_ts()
    if left <= 0:
        return 0
    return (left + 86399) // 86400


def access_message(user: sqlite3.Row) -> str:
    url = sub_url(user["token"])
    text = (
        "Ссылка доступа K-Pax.\n"
        "Осталось %d дн.\n"
        "%s\n\n"
        "%s\n\n"
        "%s"
    ) % (
        days_remaining(int(user["expires_at"])),
        url,
        deep_link_text(url),
        online_devices_line(user),
    )
    bid = str(user["brand"] or "kpax") if "brand" in user.keys() else "kpax"
    if BRANDS.get(bid, {}).get("channel"):
        text += "\n\n" + CHANNEL_LINE
    return text


def paid_count_for(user_id: int) -> int:
    conn = db()
    count = conn.execute(
        "SELECT COUNT(*) FROM platega_invoices WHERE user_id=? AND status='CONFIRMED'",
        (user_id,),
    ).fetchone()[0]
    conn.close()
    return int(count)


def status_message(user: sqlite3.Row) -> str:
    left = days_remaining(int(user["expires_at"]))
    active = bool(user["active"]) and int(user["expires_at"]) > now_ts()
    paid_n = paid_count_for(int(user["id"]))
    until_bonus = LOYALTY_EVERY - (paid_n % LOYALTY_EVERY) or LOYALTY_EVERY
    loyalty = "До бонуса лояльности (+%d дн.): ещё %d оплат" % (
        LOYALTY_BONUS_DAYS,
        until_bonus,
    )
    return (
        "Счёт %s\n"
        "Статус: %s\n"
        "Доступ до %s\n"
        "Осталось %d дн.\n"
        "Оплат: %d\n"
        "%s\n"
        "%s\n"
        "Без автопродления.\n"
        "Приложение: %s\n"
        "Пригласить друга: https://k-pax.space/?ref=%s"
    ) % (
        user["public_id"],
        "активен" if active else "выключен",
        fmt(int(user["expires_at"])),
        left,
        paid_n,
        online_devices_line(user),
        loyalty,
        APPS_HINT,
        user["public_id"],
    )


def normalize_promo(raw: str) -> str:
    code = re.sub(r"[^A-Za-z0-9\-]", "", (raw or "").strip().upper())
    if not code or len(code) > 32:
        raise ValueError("Укажите промокод.")
    return code


def promo_ready(raw_code: str) -> str:
    """Check the code can still be used. Does not consume it."""
    code = normalize_promo(raw_code)
    conn = db()
    promo = conn.execute("SELECT * FROM promos WHERE code=?", (code,)).fetchone()
    conn.close()
    if promo is None or not promo["active"] or str(promo["brand"] or "kpax") != brand_id():
        raise ValueError("Такого промокода нет.")
    if int(promo["used"]) >= int(promo["max_uses"]):
        raise ValueError("Этот промокод уже использовали.")
    return code


def redeem_promo(user: sqlite3.Row, raw_code: str) -> str:
    code = normalize_promo(raw_code)
    with LOCK:
        conn = db()
        conn.execute("BEGIN IMMEDIATE")
        promo = conn.execute("SELECT * FROM promos WHERE code=?", (code,)).fetchone()
        user_brand = str(user["brand"] or "kpax") if "brand" in user.keys() else "kpax"
        if promo is None or not promo["active"] or str(promo["brand"] or "kpax") != user_brand:
            conn.rollback()
            conn.close()
            raise ValueError("Такого промокода нет.")
        if int(promo["used"]) >= int(promo["max_uses"]):
            conn.rollback()
            conn.close()
            raise ValueError("Этот промокод уже использовали.")
        used = conn.execute(
            "SELECT 1 FROM promo_uses WHERE code=? AND user_id=?",
            (code, int(user["id"])),
        ).fetchone()
        if used is not None:
            conn.rollback()
            conn.close()
            raise ValueError("Вы уже вводили этот промокод.")
        days = int(promo["days"])
        conn.execute(
            "INSERT INTO promo_uses(code, user_id, created_at) VALUES(?, ?, ?)",
            (code, int(user["id"]), now_ts()),
        )
        conn.execute("UPDATE promos SET used=used+1 WHERE code=?", (code,))
        conn.commit()
        conn.close()
    print("promo", user["public_id"], code, days, flush=True)
    if days <= 0:
        return "Промокод принят."
    extended = extend_user(user["public_id"], days)
    return "Промокод принят. Добавлено %d дн. Доступ до %s." % (
        days,
        fmt(int(extended["expires_at"])),
    )


def create_promo(code: str, days: int, max_uses: int, promo_brand: str = "kpax") -> str:
    code = normalize_promo(code)
    if days < 0 or days > 365 or max_uses < 1 or max_uses > 10000:
        raise ValueError("Срок 0–365 дней (0 = только учёт), использований 1–10000.")
    if promo_brand not in BRANDS:
        raise ValueError("Неизвестный бренд.")
    with LOCK:
        conn = db()
        try:
            conn.execute(
                "INSERT INTO promos(code, days, max_uses, used, active, created_at, brand) VALUES(?, ?, ?, 0, 1, ?, ?)",
                (code, days, max_uses, now_ts(), promo_brand),
            )
            conn.commit()
        except sqlite3.IntegrityError as exc:
            conn.rollback()
            raise ValueError("Такой промокод уже есть.") from exc
        finally:
            conn.close()
    return code


WINBACK_DAYS = 7
REMIND_BRAND = {
    "kpax": {"name": "K-Pax", "site": "https://k-pax.space", "price": 110, "support": "support@k-pax.space"},
    "xplm": {"name": "X-Plm", "site": "https://x-plm.online", "price": 299, "support": "support@x-plm.online"},
}


def reminder_text(user: sqlite3.Row, stage: str, code: str = "") -> tuple[str, str]:
    """Subject and body of one expiry letter, written per brand."""
    bid = str(user["brand"] or "kpax")
    b = REMIND_BRAND.get(bid, REMIND_BRAND["kpax"])
    until = fmt(int(user["expires_at"]))
    pay = "%s/pay" % b["site"]
    tail = "Ссылка подключения не меняется: после оплаты всё заработает само.\nВопросы: %s\n\n— %s" % (b["support"], b["name"])
    if BRANDS.get(bid, {}).get("channel"):
        tail = tail.replace("\n\n— ", "\n" + CHANNEL_LINE + "\n\n— ")
    if stage == "soon":
        left = days_remaining(int(user["expires_at"]))
        subject = "%s: подписка заканчивается через %d дн." % (b["name"], left)
        body = (
            "Здравствуйте!\n\n"
            "Подписка %s на счёте %s заканчивается %s.\n\n"
            "Продлить на 30 дней — %d ₽, разовая оплата через СБП, без автопродления:\n%s\n\n%s"
        ) % (b["name"], user["public_id"], until, b["price"], pay, tail)
    elif stage == "ended":
        subject = "%s: срок подписки закончился" % b["name"]
        body = (
            "Здравствуйте!\n\n"
            "Срок подписки %s на счёте %s закончился %s, подключение остановлено.\n\n"
            "Вернуть доступ на 30 дней — %d ₽, разовая оплата через СБП:\n%s\n\n%s"
        ) % (b["name"], user["public_id"], until, b["price"], pay, tail)
    else:
        subject = "%s: %d дней в подарок" % (b["name"], WINBACK_DAYS)
        body = (
            "Здравствуйте!\n\n"
            "Подписка %s на счёте %s закончилась несколько дней назад. Возвращайтесь — дарим %d дней.\n\n"
            "Ваш промокод: %s\n"
            "Откройте ссылку, введите эту почту и нажмите «Применить»:\n%s/?promo=%s#promo\n\n"
            "Код личный и срабатывает один раз. Дальше — %d ₽ за 30 дней, без автопродления.\n\n%s"
        ) % (b["name"], user["public_id"], WINBACK_DAYS, code, b["site"], code, b["price"], tail)
    return subject, body


def reminder_reachable(user: sqlite3.Row) -> bool:
    contact = str(user["contact"] or "")
    bid = str(user["brand"] or "kpax")
    by_mail = bool(contact) and not contact.startswith("@") and brand_mail(bid) is not None
    return by_mail or (bool(user["telegram_chat_id"]) and bid == "kpax")


def send_reminder(user: sqlite3.Row, subject: str, body: str) -> bool:
    bid = str(user["brand"] or "kpax")
    contact = str(user["contact"] or "")
    sent = False
    with brand_context(bid):
        mail = brand_mail()
        if contact and not contact.startswith("@") and mail:
            send_mail(mail, contact, subject, body)
            sent = True
    chat_id = user["telegram_chat_id"]
    if chat_id and bid == "kpax":
        try:
            telegram_reply(int(chat_id), body.replace("введите эту почту", "введите свою почту или Telegram"), MAIN_KEYBOARD)
            sent = True
        except Exception as exc:  # noqa: BLE001
            print("remind telegram failed", user["public_id"], type(exc).__name__, flush=True)
    return sent


def winback_code(user: sqlite3.Row) -> str:
    for _ in range(5):
        code = "BACK" + "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(6))
        try:
            return create_promo(code, WINBACK_DAYS, 1, str(user["brand"] or "kpax"))
        except ValueError:
            continue
    raise RuntimeError("promo code")


def remind_stage(stage: str, low: int, high: int) -> None:
    conn = db()
    rows = conn.execute(
        """
        SELECT * FROM users
        WHERE verified=1 AND expires_at>? AND expires_at<=?
        ORDER BY expires_at LIMIT 100
        """,
        (low, high),
    ).fetchall()
    conn.close()
    kind = {"soon": "remind", "ended": "remind_ended", "winback": "remind_winback"}[stage]
    for user in rows:
        if stage == "soon" and not int(user["active"] or 0):
            continue
        if not reminder_reachable(user):
            continue
        if not notice_once(int(user["id"]), kind, str(int(user["expires_at"]))):
            continue
        try:
            code = winback_code(user) if stage == "winback" else ""
            subject, body = reminder_text(user, stage, code)
            if send_reminder(user, subject, body):
                print("remind", stage, user["public_id"], flush=True)
        except Exception as exc:  # noqa: BLE001
            print("remind failed", stage, user["public_id"], type(exc).__name__, flush=True)


def remind_due() -> None:
    """Three letters around the end date: up to ~3.5 days before, on the day, 3 days after with a gift code."""
    now = now_ts()
    # Include same-day / day-1/2 expiries; notice_once keeps one "soon" letter per expiry stamp.
    remind_stage("soon", now, now + 3 * 86400 + 12 * 3600)
    remind_stage("ended", now - 86400, now)
    remind_stage("winback", now - 4 * 86400, now - 3 * 86400)


def user_for_restore(contact: str) -> sqlite3.Row | None:
    conn = db()
    row = conn.execute(
        """
        SELECT public_id, token, contact, uuid, expires_at, active, verified, brand
        FROM users WHERE lower(contact)=lower(?) AND verified=1 AND brand=? LIMIT 1
        """,
        (contact, brand_id()),
    ).fetchone()
    conn.close()
    return row


def restore_key(channel: str) -> str:
    return channel if brand_id() == "kpax" else channel + ":" + brand_id()


def restore_allowed(contact: str, channel: str) -> bool:
    since = now_ts() - 3600
    conn = db()
    count = conn.execute(
        "SELECT COUNT(*) FROM restore_log WHERE lower(contact)=lower(?) AND channel=? AND created_at>?",
        (contact, restore_key(channel), since),
    ).fetchone()[0]
    conn.close()
    return count < 3


def note_restore(contact: str, channel: str) -> None:
    conn = db()
    conn.execute(
        "INSERT INTO restore_log(contact, channel, created_at) VALUES(?, ?, ?)",
        (contact, restore_key(channel), now_ts()),
    )
    conn.commit()
    conn.close()


def telegram_api(token: str, method: str, payload: dict | None = None) -> dict:
    if not token:
        return {}
    data = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(
        "https://api.telegram.org/bot" + token + "/" + method,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST" if data is not None else "GET",
    )
    with urllib.request.urlopen(request, timeout=40) as response:
        body = json.loads(response.read().decode())
    if not body.get("ok"):
        raise RuntimeError("telegram " + method)
    return body


def telegram_reply(chat_id: int, text: str, markup: dict | None = None) -> int | None:
    payload = {"chat_id": chat_id, "text": text, "disable_web_page_preview": True}
    if markup is not None:
        payload["reply_markup"] = markup
    body = telegram_api(
        str(CFG.get("telegram_restore_token") or ""),
        "sendMessage",
        payload,
    )
    result = body.get("result") if isinstance(body, dict) else None
    if isinstance(result, dict) and isinstance(result.get("message_id"), int):
        return int(result["message_id"])
    return None


def telegram_delete(chat_id: int, message_id: int | None) -> None:
    if not isinstance(message_id, int):
        return
    try:
        telegram_api(
            str(CFG.get("telegram_restore_token") or ""),
            "deleteMessage",
            {"chat_id": chat_id, "message_id": message_id},
        )
    except Exception:
        pass


def clear_tg_wait(chat_id: int) -> dict | None:
    return TG_WAIT.pop(chat_id, None)


def tg_wait_expired(wait: dict) -> bool:
    return now_ts() - int(wait.get("at") or 0) > TG_WAIT_TTL


def ask_promo_code(chat_id: int, trigger_id: int | None = None) -> None:
    clear_tg_wait(chat_id)
    prompt_id = telegram_reply(chat_id, "Введите промокод", MAIN_KEYBOARD)
    TG_WAIT[chat_id] = {
        "kind": "promo",
        "prompt_id": prompt_id,
        "trigger_id": trigger_id,
        "at": now_ts(),
    }


def ask_gift_contact(chat_id: int, trigger_id: int | None = None) -> None:
    clear_tg_wait(chat_id)
    prompt_id = telegram_reply(
        chat_id,
        "Введите почту или Telegram друга — оплатим его счёт на 30 дней за 110 ₽, без автопродления.",
        MAIN_KEYBOARD,
    )
    TG_WAIT[chat_id] = {
        "kind": "gift",
        "prompt_id": prompt_id,
        "trigger_id": trigger_id,
        "at": now_ts(),
    }


def apply_promo_reply(chat_id: int, sender: dict, code: str, user_msg_id: int | None) -> None:
    wait = clear_tg_wait(chat_id) or {}
    user = telegram_user_from_sender(sender, chat_id)
    if user is None:
        telegram_delete(chat_id, wait.get("trigger_id"))
        telegram_delete(chat_id, wait.get("prompt_id"))
        telegram_delete(chat_id, user_msg_id)
        telegram_reply(chat_id, "Промокод можно ввести с Telegram, который указан в K-Pax.", MAIN_KEYBOARD)
        return
    try:
        result = redeem_promo(user, code)
    except ValueError as exc:
        result = str(exc)
    telegram_delete(chat_id, wait.get("trigger_id"))
    telegram_delete(chat_id, wait.get("prompt_id"))
    telegram_delete(chat_id, user_msg_id)
    telegram_reply(chat_id, result, MAIN_KEYBOARD)


def apply_gift_reply(chat_id: int, raw_contact: str, user_msg_id: int | None) -> None:
    wait = clear_tg_wait(chat_id) or {}
    telegram_delete(chat_id, wait.get("trigger_id"))
    telegram_delete(chat_id, wait.get("prompt_id"))
    telegram_delete(chat_id, user_msg_id)
    try:
        normal = normalize_contact(raw_contact)
    except ValueError as exc:
        telegram_reply(chat_id, str(exc), MAIN_KEYBOARD)
        return
    friend = user_by_contact(normal)
    if friend is None:
        telegram_reply(
            chat_id,
            "Этой почты или ника ещё нет в K-Pax. Друг сначала получает ссылку на сайте.",
            MAIN_KEYBOARD,
        )
        return
    outcome, detail = begin_payment(friend, "tg-gift:%d" % chat_id)
    if outcome == "ok":
        telegram_reply(
            chat_id,
            "Счёт на 110 ₽ для %s готов. Оплата через СБП, без автопродления. Ссылка живёт около 15 минут."
            % friend["public_id"],
            pay_link_markup(detail),
        )
    else:
        telegram_reply(chat_id, detail, MAIN_KEYBOARD)


def bot_send_pay(chat_id: int, username: str) -> None:
    telegram_reply(chat_id, BOT_OFFER, MAIN_KEYBOARD)
    outcome, detail = telegram_pay_for(chat_id, username, "tg:%d" % chat_id)
    if outcome == "ok":
        telegram_reply(
            chat_id,
            "Счёт на 110 ₽ готов. Оплата через СБП продлевает ту же ссылку на 30 дней, без автопродления. Ссылка живёт около 15 минут.",
            pay_link_markup(detail),
        )
    else:
        telegram_reply(chat_id, detail, PAY_MARKUP)


def bot_send_profile(chat_id: int, sender: dict) -> None:
    user = telegram_user_from_sender(sender, chat_id)
    if user is None:
        telegram_reply(
            chat_id,
            "Профиль виден, если Telegram указан в K-Pax. Иначе откройте сайт или напишите с почты на access@k-pax.space.",
            MAIN_KEYBOARD,
        )
        return
    telegram_reply(chat_id, status_message(user), MAIN_KEYBOARD)


def bot_activate_pending(chat_id: int, user: sqlite3.Row) -> bool:
    """Activate pending TG signup once the matching account opens the bot."""
    try:
        activated, invited, promo_note = activate_user(user)
    except Exception as exc:  # noqa: BLE001
        print("tg activate failed", type(exc).__name__, flush=True)
        telegram_reply(
            chat_id,
            "Не получилось активировать. Попробуйте через минуту или подтвердите почтой на сайте.",
            MAIN_KEYBOARD,
        )
        return False
    parts = [access_message(activated)]
    if invited:
        parts.insert(0, "Реферальный бонус начислен пригласившему.")
    if promo_note:
        parts.insert(0, promo_note)
    telegram_reply(chat_id, "\n\n".join(parts), MAIN_KEYBOARD)
    print("tg verified", activated["public_id"], flush=True)
    return True


def bot_verify_start(chat_id: int, sender: dict, payload: str) -> None:
    token = payload[2:] if payload.startswith("v_") else ""
    user = user_by_verify_token(token)
    if user is None:
        telegram_reply(
            chat_id,
            "Ссылка подтверждения устарела. Зарегистрируйтесь снова на https://k-pax.space",
            MAIN_KEYBOARD,
        )
        return
    contact = str(user["contact"] or "")
    if not contact.startswith("@"):
        telegram_reply(
            chat_id,
            "Этот аккаунт подтверждается кодом на почту. Откройте сайт k-pax.space.",
            MAIN_KEYBOARD,
        )
        return
    username = str(sender.get("username") or "")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{4,31}", username) or ("@" + username).lower() != contact.lower():
        telegram_reply(
            chat_id,
            "Откройте бота с Telegram %s — тем же ником, что указали на сайте." % contact,
            MAIN_KEYBOARD,
        )
        return
    remember_telegram_chat(contact, chat_id)
    bot_activate_pending(chat_id, user)


def bot_app_login_sender_ok(user: sqlite3.Row, sender: dict) -> tuple[str, str]:
    """Return (contact, error). Empty error means the Telegram nick matches."""
    contact = str(user["contact"] or "")
    if not contact.startswith("@"):
        return contact, "Этот аккаунт подтверждается письмом. Откройте почту и нажмите кнопку в письме."
    username = str(sender.get("username") or "")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{4,31}", username) or ("@" + username).lower() != contact.lower():
        return (
            contact,
            "Откройте бота с Telegram %s — тем же ником, что указали в приложении." % contact,
        )
    return contact, ""


def bot_app_login_start(chat_id: int, sender: dict, payload: str) -> None:
    token = payload[2:] if payload.startswith("a_") else ""
    row = app_login_row(token)
    if row is None or app_login_expired(row):
        telegram_reply(
            chat_id,
            "Вход устарел. Откройте приложение K-Pax и запросите вход снова.",
            MAIN_KEYBOARD,
        )
        return
    conn = db()
    user = conn.execute(
        "SELECT * FROM users WHERE id=? AND brand=? LIMIT 1",
        (int(row["user_id"]), brand_id()),
    ).fetchone()
    conn.close()
    if user is None:
        telegram_reply(chat_id, "Аккаунт не найден.", MAIN_KEYBOARD)
        return
    contact, error = bot_app_login_sender_ok(user, sender)
    if error:
        telegram_reply(chat_id, error, MAIN_KEYBOARD)
        return
    remember_telegram_chat(contact, chat_id)
    if not int(user["verified"] or 0):
        telegram_reply(
            chat_id,
            "Спасибо за регистрацию в K-Pax.\n\n"
            "14 дней бесплатно, без привязки карты. Нажмите «Подтвердить» — "
            "приложение подхватит доступ само.",
            app_login_confirm_markup(token),
        )
        return
    _, error = finish_app_login(token)
    if error:
        telegram_reply(chat_id, error, MAIN_KEYBOARD)
        return
    telegram_reply(
        chat_id,
        "Готово. Вернитесь в приложение K-Pax — ссылка подгрузится сама.",
        MAIN_KEYBOARD,
    )
    print("app login tg confirmed", user["public_id"], flush=True)


def bot_app_login_confirm(chat_id: int, sender: dict, token: str) -> None:
    row = app_login_row(token)
    if row is None or app_login_expired(row):
        telegram_reply(
            chat_id,
            "Вход устарел. Откройте приложение K-Pax и запросите вход снова.",
            MAIN_KEYBOARD,
        )
        return
    conn = db()
    user = conn.execute(
        "SELECT * FROM users WHERE id=? AND brand=? LIMIT 1",
        (int(row["user_id"]), brand_id()),
    ).fetchone()
    conn.close()
    if user is None:
        telegram_reply(chat_id, "Аккаунт не найден.", MAIN_KEYBOARD)
        return
    contact, error = bot_app_login_sender_ok(user, sender)
    if error:
        telegram_reply(chat_id, error, MAIN_KEYBOARD)
        return
    remember_telegram_chat(contact, chat_id)
    _, error = finish_app_login(token)
    if error:
        telegram_reply(chat_id, error, MAIN_KEYBOARD)
        return
    telegram_reply(
        chat_id,
        "Готово. Вернитесь в приложение K-Pax — ссылка подгрузится сама.",
        MAIN_KEYBOARD,
    )
    print("app login tg confirmed", user["public_id"], flush=True)


def bot_send_link(chat_id: int, sender: dict) -> None:
    username = str(sender.get("username") or "")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{4,31}", username):
        telegram_reply(
            chat_id,
            "Чтобы вернуть ссылку, поставьте @username или напишите с почты на access@k-pax.space.",
            MAIN_KEYBOARD,
        )
        return
    contact = "@" + username
    remember_telegram_chat(contact, chat_id)
    pending = user_by_contact(contact)
    if pending is not None and not int(pending["verified"] or 0):
        bot_activate_pending(chat_id, pending)
        return
    user = user_for_restore(contact)
    if user is None:
        telegram_reply(
            chat_id,
            "Этот Telegram не указан в K-Pax. Напишите с аккаунта, который вводили на сайте.",
            MAIN_KEYBOARD,
        )
        return
    if not restore_allowed(contact, "telegram"):
        telegram_reply(chat_id, "Ссылка уже отправлена. Подождите и напишите ещё раз.", MAIN_KEYBOARD)
        return
    telegram_reply(chat_id, access_message(user), MAIN_KEYBOARD)
    note_restore(contact, "telegram")
    print("restored", user["public_id"], "telegram", flush=True)


PAY_MARKUP = {
    "inline_keyboard": [
        [{"text": "Оплатить 110 ₽", "callback_data": "pay"}],
        [{"text": "Оплатить на сайте", "url": SITE + "/pay"}],
    ]
}

MAIN_KEYBOARD = {
    "keyboard": [
        [{"text": "✨ Оплатить"}],
        [{"text": "👤 Профиль"}, {"text": "🔗 Ссылка"}],
        [{"text": "🎁 Оплатить другу"}, {"text": "🏷 Промокод"}],
        [{"text": "🟢 Статус сети"}, {"text": "ⓘ Info"}],
        [{"text": "📣 Новости и +7 дней"}],
    ],
    "resize_keyboard": True,
    "is_persistent": True,
}

BTN_PAY = "✨ Оплатить"
BTN_PROFILE = "👤 Профиль"
BTN_LINK = "🔗 Ссылка"
BTN_GIFT = "🎁 Оплатить другу"
BTN_PROMO = "🏷 Промокод"
BTN_NET = "🟢 Статус сети"
BTN_INFO = "ⓘ Info"
BTN_NEWS = "📣 Новости и +7 дней"
CHANNEL_ANNOUNCE = "Новости, статус серверов и промокод на +7 дней — в нашем канале t.me/kpaxvpn"
CHANNEL_LINE = "Новости, статус серверов и промокод на +7 дней — в канале K-Pax: https://t.me/kpaxvpn"


def pay_link_markup(url: str) -> dict:
    return {
        "inline_keyboard": [[{"text": "Оплатить 110 ₽", "url": url}]],
    }


BOT_OFFER = """K-Pax — подключение для работы в интернете без рекламы. Между устройством и сетью создаётся безопасное соединение.

Оплата: 110 ₽ за 30 дней, без автопродления, карта не привязывается.
Что входит:
— 2 устройства, одна ссылка на телефон и компьютер;
— оплата продлевает ту же ссылку на 30 дней;
— рекламные сети и трекеры отключаются;
— торренты на подключении не работают;
— каждая 6-я оплата — бонус +7 дней.

Приложение: %s

До первой оплаты — 14 дней бесплатно, без привязки карты.
Способы: СБП НСПК (QR и ссылка из банковского приложения).

Если Telegram указан в K-Pax — нажмите «Оплатить».
Если регистрировались почтой — «Оплатить на сайте».
Соглашение: https://k-pax.space/terms
Конфиденциальность: https://k-pax.space/privacy
Возврат: https://k-pax.space/terms#refund
Поддержка: support@k-pax.space""" % APPS_HINT

BOT_DESCRIPTION = (
    "K-Pax — подключение для работы в интернете без рекламы. "
    "Между вашим устройством и сетью создаётся безопасное соединение.\n"
    "14 дней бесплатно, без привязки карты. Без автопродления."
)

BOT_INFO = """K-Pax — интернет без рекламы.

110 ₽ / 30 дней · без автопродления · карта не привязывается
2 устройства · торренты не работают
Каждая 6-я оплата: +7 дней

Приложение: %s

Соглашение: https://k-pax.space/terms
Конфиденциальность: https://k-pax.space/privacy
Возврат: https://k-pax.space/terms#refund
Статус сети: https://k-pax.space/status
Поддержка: support@k-pax.space
Бот: @KPax_Space_bot""" % APPS_HINT


TERMS_TEXT = """Пользовательское соглашение: https://k-pax.space/terms
Конфиденциальность: https://k-pax.space/privacy
Возврат: https://k-pax.space/terms#refund"""


def command_name(text: str) -> str:
    parts = text.strip().split(maxsplit=1)
    if not parts or not parts[0].startswith("/"):
        return ""
    return parts[0].split("@", 1)[0].lower()


def telegram_answer(callback_id: str, text: str = "", alert: bool = False) -> None:
    payload: dict = {"callback_query_id": callback_id}
    if text:
        payload["text"] = text[:180]
        payload["show_alert"] = alert
    telegram_api(
        str(CFG.get("telegram_restore_token") or ""),
        "answerCallbackQuery",
        payload,
    )


def telegram_pay_for(chat_id: int, username: str, rate_key: str) -> tuple[str, str]:
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{4,31}", username):
        return (
            "error",
            "В этом Telegram нет @username. Если регистрировались почтой — откройте оплату на сайте.",
        )
    contact = "@" + username
    remember_telegram_chat(contact, chat_id)
    user = user_by_contact(contact)
    if user is None:
        return (
            "error",
            "Этот Telegram не указан в K-Pax. Если регистрировались почтой — оплатите на сайте.",
        )
    return begin_payment(user, rate_key)


def telegram_user_from_sender(sender: dict, chat_id: int) -> sqlite3.Row | None:
    username = str(sender.get("username") or "")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{4,31}", username):
        return None
    contact = "@" + username
    remember_telegram_chat(contact, chat_id)
    return user_by_contact(contact)


def handle_telegram_update(update: dict) -> None:
    callback = update.get("callback_query")
    if isinstance(callback, dict):
        callback_id = str(callback.get("id") or "")
        data = str(callback.get("data") or "")
        message = callback.get("message") or {}
        chat = message.get("chat") or {}
        sender = callback.get("from") or {}
        chat_id = chat.get("id")
        if data == "promo" and isinstance(chat_id, int) and not sender.get("is_bot"):
            if callback_id:
                telegram_answer(callback_id)
            ask_promo_code(chat_id, message.get("message_id") if isinstance(message.get("message_id"), int) else None)
            return
        if data.startswith("ac:") and isinstance(chat_id, int) and not sender.get("is_bot"):
            if callback_id:
                telegram_answer(callback_id)
            bot_app_login_confirm(chat_id, sender, data[3:])
            return
        if data == "pay" and isinstance(chat_id, int) and not sender.get("is_bot"):
            clear_tg_wait(chat_id)
            username = str(sender.get("username") or "")
            outcome, detail = telegram_pay_for(chat_id, username, "tg:%d" % chat_id)
            if outcome == "ok":
                if callback_id:
                    telegram_answer(callback_id)
                telegram_reply(
                    chat_id,
                    "Счёт на 110 ₽ готов. Оплата через СБП продлевает ту же ссылку на 30 дней, без автопродления. Ссылка живёт около 15 минут.",
                    pay_link_markup(detail),
                )
            else:
                if callback_id:
                    telegram_answer(callback_id)
                telegram_reply(chat_id, detail, PAY_MARKUP)
            return
        if callback_id:
            telegram_answer(callback_id)
        return
    message = update.get("message")
    if not isinstance(message, dict):
        return
    chat = message.get("chat") or {}
    if chat.get("type") != "private":
        return
    sender = message.get("from") or {}
    if sender.get("is_bot"):
        return
    chat_id = chat.get("id")
    if not isinstance(chat_id, int):
        return
    text = str(message.get("text") or "")
    stripped = text.strip()
    user_msg_id = message.get("message_id") if isinstance(message.get("message_id"), int) else None
    command = command_name(text)
    button = stripped if stripped in {
        BTN_PAY, BTN_PROFILE, BTN_LINK, BTN_GIFT, BTN_PROMO, BTN_NET, BTN_INFO, BTN_NEWS,
    } else ""
    waiting = TG_WAIT.get(chat_id)
    if waiting and tg_wait_expired(waiting):
        clear_tg_wait(chat_id)
        waiting = None
    if waiting and waiting.get("kind") == "promo" and not command and not button:
        apply_promo_reply(chat_id, sender, stripped, user_msg_id)
        return
    if waiting and waiting.get("kind") == "gift" and not command and not button:
        apply_gift_reply(chat_id, stripped, user_msg_id)
        return
    if command or button:
        clear_tg_wait(chat_id)
    if command in {"/pay", "/oplata"} or button == BTN_PAY:
        bot_send_pay(chat_id, str(sender.get("username") or ""))
        return
    if command == "/status" or button == BTN_PROFILE:
        bot_send_profile(chat_id, sender)
        return
    if command == "/start":
        parts = text.strip().split(maxsplit=1)
        payload = parts[1].strip() if len(parts) > 1 else ""
        if payload.startswith("v_"):
            bot_verify_start(chat_id, sender, payload)
            return
        if payload.startswith("a_"):
            bot_app_login_start(chat_id, sender, payload)
            return
        telegram_reply(
            chat_id,
            "Кнопки внизу всегда под рукой. «Ссылка» вернёт доступ, «Оплатить» — счёт без автопродления.\n\n"
            + CHANNEL_LINE,
            MAIN_KEYBOARD,
        )
        bot_send_link(chat_id, sender)
        return
    if button == BTN_NEWS or command == "/news":
        telegram_reply(
            chat_id,
            "Канал K-Pax: новости, итоги дня и статус серверов.\n"
            "В закрепе — промокод на +7 дней. Ввести его можно кнопкой «🏷 Промокод».",
            {"inline_keyboard": [[{"text": "Открыть канал", "url": BRANDS["kpax"]["channel"]}]]},
        )
        return
    if button == BTN_LINK:
        bot_send_link(chat_id, sender)
        return
    if button == BTN_GIFT:
        ask_gift_contact(chat_id, user_msg_id)
        return
    if button == BTN_NET:
        telegram_reply(
            chat_id,
            "Статус сети: https://k-pax.space/status\nСтраны и адреса серверов здесь не публикуем.\n"
            "Сообщения о работах и сбоях — в канале: https://t.me/kpaxvpn",
            MAIN_KEYBOARD,
        )
        return
    if button == BTN_INFO or command in {"/terms", "/help"}:
        if command == "/terms":
            telegram_reply(chat_id, TERMS_TEXT, MAIN_KEYBOARD)
        else:
            telegram_reply(chat_id, BOT_INFO, MAIN_KEYBOARD)
        return
    if command == "/promo" or button == BTN_PROMO:
        parts = text.strip().split(maxsplit=1)
        if command == "/promo" and len(parts) >= 2:
            user = telegram_user_from_sender(sender, chat_id)
            if user is None:
                telegram_reply(
                    chat_id,
                    "Промокод можно ввести с Telegram, который указан в K-Pax.",
                    MAIN_KEYBOARD,
                )
                return
            try:
                telegram_reply(chat_id, redeem_promo(user, parts[1]), MAIN_KEYBOARD)
            except ValueError as exc:
                telegram_reply(chat_id, str(exc), MAIN_KEYBOARD)
            return
        ask_promo_code(chat_id, user_msg_id)
        return
    bot_send_link(chat_id, sender)


def telegram_restore_loop() -> None:
    token = str(CFG.get("telegram_restore_token") or "")
    if not token:
        print("telegram restore off", flush=True)
        return
    for method, payload in (
        ("setMyName", {"name": "K-Pax"}),
        ("setMyDescription", {"description": BOT_DESCRIPTION}),
        ("setMyShortDescription", {"short_description": "K-Pax — подключение для работы в интернете без рекламы. Безопасное соединение. 14 дней бесплатно, без привязки карты."}),
        (
            "setMyCommands",
            {
                "commands": [
                    {"command": "start", "description": "Вернуть ссылку"},
                    {"command": "status", "description": "Срок и оплаты"},
                    {"command": "pay", "description": "Оплатить подписку"},
                    {"command": "promo", "description": "Промокод"},
                    {"command": "terms", "description": "Соглашение, конфиденциальность, возврат"},
                ]
            },
        ),
    ):
        try:
            telegram_api(token, method, payload)
            print("telegram", method, "ok", flush=True)
        except Exception:
            print("telegram", method, "skip", flush=True)
    offset = 0
    try:
        primed = telegram_api(token, "getUpdates", {"timeout": 0, "offset": -1})
        result = primed.get("result") or []
        if result:
            offset = int(result[-1]["update_id"]) + 1
    except Exception:
        print("telegram prime", "skip", flush=True)
    print("telegram restore on", flush=True)
    while True:
        try:
            payload = telegram_api(
                token,
                "getUpdates",
                {"timeout": 25, "offset": offset, "allowed_updates": ["message", "callback_query"]},
            )
            for update in payload.get("result") or []:
                offset = int(update["update_id"]) + 1
                try:
                    handle_telegram_update(update)
                except Exception:
                    print("telegram update", "error", flush=True)
        except Exception:
            print("telegram poll", "error", flush=True)
            time.sleep(5)


def mail_sender_ok(message, sender: str) -> bool:
    blob = " ".join(message.get_all("Authentication-Results") or []).lower()
    domain = sender.split("@", 1)[-1]
    aligned = sender in blob or domain in blob
    return aligned and ("spf=pass" in blob or "dkim=pass" in blob)


def mail_is_local(host: str) -> bool:
    return host in {"127.0.0.1", "localhost"}


STAGE_MAIL: list[tuple[str, str, str]] = []


def send_mail(mail: dict, recipient: str, subject: str, text: str, html_body: str = "") -> None:
    if is_xplm():
        subject = rebrand(subject)
        text = rebrand(text)
        if html_body:
            html_body = rebrand(html_body)
    if STAGE:
        STAGE_MAIL.append((recipient, subject, text))
        print("stage mail", subject, flush=True)
        return
    message = EmailMessage()
    message["From"] = str(mail["user"])
    message["To"] = recipient
    message["Subject"] = subject
    message.set_content(text)
    if html_body:
        message.add_alternative(html_body, subtype="html")
    host = str(mail.get("smtp_host") or mail["imap_host"])
    port = int(mail.get("smtp_port") or (25 if mail_is_local(host) else 587))
    with smtplib.SMTP(host, port, timeout=30) as smtp:
        if not mail_is_local(host):
            smtp.starttls()
            smtp.login(str(mail["user"]), str(mail["password"]))
        smtp.send_message(message)


def send_restore_mail(mail: dict, recipient: str, text: str) -> None:
    send_mail(mail, recipient, "Доступ K-Pax", text)


def deliver_access_mail(user: sqlite3.Row) -> bool:
    """Send the new subscription link when signup used an email address."""
    contact = str(user["contact"] or "")
    if not contact or contact.startswith("@") or not int(user["verified"] or 0):
        return False
    mail = brand_mail()
    if not mail:
        return False
    try:
        send_restore_mail(mail, contact, access_message(user))
        note_restore(contact, "email")
    except Exception as exc:  # noqa: BLE001
        print("signup mail failed", user["public_id"], type(exc).__name__, flush=True)
        return False
    print("mailed", user["public_id"], flush=True)
    return True


def deliver_verify_mail(user: sqlite3.Row, code: str) -> bool:
    contact = str(user["contact"] or "")
    if not contact or contact.startswith("@") or not code:
        return False
    mail = brand_mail()
    if not mail:
        return False
    text = (
        "Код подтверждения K-Pax: %s\n\n"
        "Введите его в приложении или на сайте в течение 30 минут.\n"
        "Если вы не регистрировались — просто удалите письмо."
    ) % code
    try:
        send_mail(mail, contact, "Код подтверждения K-Pax", text)
    except Exception as exc:  # noqa: BLE001
        print("verify mail failed", user["public_id"], type(exc).__name__, flush=True)
        return False
    print("verify mailed", user["public_id"], flush=True)
    return True


def deliver_app_login_mail(
    contact: str,
    session: str,
    public_id: str,
    *,
    created: bool = False,
    code: str = "",
) -> bool:
    if not contact or contact.startswith("@"):
        return False
    mail = brand_mail()
    if not mail:
        return False
    link = app_confirm_url(session)
    code_line = ("Код для приложения: %s\n\n" % code) if code else ""
    code_html = (
        '<p style="margin:0 0 16px;font-size:28px;letter-spacing:4px;font-weight:700">%s</p>'
        % html.escape(code)
        if code
        else ""
    )
    if created:
        subject = "Добро пожаловать в K-Pax"
        btn = "Подключиться"
        text = (
            "Добро пожаловать в K-Pax!\n\n"
            "Аккаунт: %s\n"
            "14 дней бесплатно, без привязки карты.\n"
            "%s"
            "Введите код в приложении или нажмите ссылку (30 минут):\n%s\n\n"
            "Если вы не регистрировались — удалите письмо."
        ) % (public_id, code_line, link)
        lead = "Добро пожаловать в <b>K-Pax</b>. Аккаунт создан."
        sub = "14 дней бесплатно. Введите код в приложении или нажмите кнопку."
    else:
        subject = "Подтвердите вход в K-Pax"
        btn = "Подтвердить"
        text = (
            "Подтвердите вход в приложение K-Pax.\n\n"
            "Аккаунт: %s\n"
            "%s"
            "Введите код в приложении или откройте ссылку (30 минут):\n%s\n\n"
            "Если вы не запрашивали вход — удалите письмо."
        ) % (public_id, code_line, link)
        lead = "Подтвердите вход в приложение <b>K-Pax</b>."
        sub = "Введите код в приложении или нажмите кнопку. Действует 30 минут."
    html_body = """<!doctype html>
<html lang="ru"><body style="margin:0;padding:24px;background:#0e131c;color:#e8eef7;font-family:Segoe UI,Arial,sans-serif">
<p style="margin:0 0 12px">%s</p>
<p style="margin:0 0 12px;color:#93a0b5">Аккаунт: %s</p>
<p style="margin:0 0 12px;color:#93a0b5">%s</p>
%s
<p style="margin:0 0 28px"><a href="%s" style="display:inline-block;padding:14px 22px;background:#3ddc97;color:#062216;text-decoration:none;border-radius:12px;font-weight:700">%s</a></p>
</body></html>""" % (
        lead,
        html.escape(public_id),
        html.escape(sub),
        code_html,
        html.escape(link, quote=True),
        html.escape(btn),
    )
    try:
        send_mail(mail, contact, subject, text, html_body)
    except Exception as exc:  # noqa: BLE001
        print("app login mail failed", public_id, type(exc).__name__, flush=True)
        return False
    print("app login mailed", public_id, flush=True)
    return True


def app_confirm_page(*, error: str = "", notice: str = "") -> tuple[int, str, bytes]:
    err = '<p class="err">%s</p>' % html.escape(error) if error else ""
    note = '<p class="ok">%s</p>' % html.escape(notice) if notice else ""
    open_app = ""
    if notice and not error:
        open_app = """
<p class="muted">Эту вкладку можно закрыть.</p>
<p class="buyrow"><a class="restore" href="kpax://confirmed">Открыть приложение K-Pax</a></p>
<p class="muted">Android: <a href="intent://confirmed#Intent;scheme=kpax;package=space.kpax.app;end">вернуть в K-Pax</a></p>
<script>setTimeout(function(){ try { location.href = 'kpax://confirmed'; } catch (e) {} }, 350);</script>
"""
    body = """
<section class="support paypage">
<h1>Вход в приложение</h1>
{note}{err}
{open_app}
<p class="buyrow"><a class="restore" href="/">На главную</a></p>
</section>
""".format(note=note, err=err, open_app=open_app)
    return page("K-Pax — вход", body, 400 if error else 200, index=False, faq_fab=True)


def poll_mail_restore(mail: dict) -> None:
    host = str(mail["imap_host"])
    if mail_is_local(host):
        client = imaplib.IMAP4(host, int(mail.get("imap_port") or 143))
    else:
        client = imaplib.IMAP4_SSL(host, int(mail.get("imap_port") or 993))
    try:
        client.login(str(mail["user"]), str(mail["password"]))
        client.select(str(mail.get("folder") or "INBOX"))
        status, data = client.search(None, "UNSEEN")
        if status != "OK" or not data or not data[0]:
            return
        for num in data[0].split():
            fetched = client.fetch(num, "(RFC822)")
            raw = b""
            if fetched[0] == "OK":
                for item in fetched[1] or []:
                    if isinstance(item, tuple) and len(item) > 1:
                        raw = item[1]
                        break
            parsed = BytesParser(policy=email_policy).parsebytes(raw or b"")
            sender = parseaddr(parsed.get("From") or "")[1].strip().lower()
            try:
                if not sender or not mail_sender_ok(parsed, sender):
                    print("mail restore unauthenticated", flush=True)
                else:
                    user = user_for_restore(sender)
                    if user is None:
                        send_restore_mail(mail, sender, "Эта почта не указана в K-Pax.")
                    elif not restore_allowed(sender, "email"):
                        send_restore_mail(mail, sender, "Ссылка уже отправлена. Подождите и напишите ещё раз.")
                    else:
                        send_restore_mail(mail, sender, access_message(user))
                        note_restore(sender, "email")
                        print("restored", user["public_id"], "email", flush=True)
            finally:
                client.store(num, "+FLAGS", "\\Seen")
    finally:
        try:
            client.logout()
        except Exception:
            pass


def mail_restore_loop(bid: str = "kpax") -> None:
    BRAND_STATE.id = bid
    mail = brand_mail()
    if not mail or not mail.get("imap_host") or not mail.get("password"):
        print("mail restore off", bid, flush=True)
        return
    print("mail restore on", bid, flush=True)
    while True:
        try:
            poll_mail_restore(mail)
        except Exception:
            print("mail restore", bid, "error", flush=True)
        time.sleep(60)


def node_title(node: dict) -> str:
    if is_front_node(node):
        return str(node.get("name") or "Russia front").strip() or "Russia front"
    titles = {"de": "Германия", "fi": "Финляндия", "bg": "Болгария"}
    return titles.get(str(node.get("id") or "").lower(), str(node.get("name") or node["host"]))


def telegram_send(text: str) -> None:
    token = str(CFG.get("telegram_bot_token") or "")
    chat = str(CFG.get("telegram_chat_id") or "")
    if not token or not chat:
        return
    body = json.dumps({"chat_id": chat, "text": text, "disable_web_page_preview": True}).encode()
    request = urllib.request.Request(
        "https://api.telegram.org/bot" + token + "/sendMessage",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        if response.status != 200:
            raise RuntimeError("telegram status %s" % response.status)


def probe_node(host: str) -> bool:
    try:
        with socket.create_connection((host, NODE_WS_PORT), timeout=PROBE_TIMEOUT):
            return True
    except OSError:
        return False


def probe_media_https(host_ip: str) -> bool:
    """TLS check of media SNI camouflage on a front IP (dual-A)."""
    try:
        context = ssl.create_default_context()
        with socket.create_connection((host_ip, 443), timeout=PROBE_TIMEOUT) as raw:
            with context.wrap_socket(raw, server_hostname=MEDIA_HTTPS_HOST) as sock:
                sock.sendall(
                    (
                        "HEAD / HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n"
                        % MEDIA_HTTPS_HOST
                    ).encode()
                )
                bump = sock.recv(64)
                return bump.startswith(b"HTTP/")
    except OSError:
        return False


def check_alerts() -> None:
    now = time.time()
    if now - PANEL_STARTED < ALERT_AFTER or not CFG.get("telegram_chat_id"):
        return
    with DEVICE_LOCK:
        snapshot = {host: dict(sample) for host, sample in NODE_HEALTH.items()}
    for node in CFG["nodes"]:
        # Intentionally offline (e.g. BG Suspended / maintenance): no Telegram spam.
        if not node_enabled(node):
            host = str(node.get("host") or "")
            if host:
                ALERT_DOWN.discard(host)
                PROBE_DOWN.discard(host)
                PROBE_FAILS[host] = 0
                ALERT_FRONT_PARTIAL.discard(host)
                ALERT_FRONT_LIMIT.discard(host)
                ALERT_MEDIA_HTTPS.discard(host)
                FRONT_PORT_FAILS[host] = 0
                FRONT_PARTIAL_FAILS[host] = 0
                MEDIA_HTTPS_FAILS[host] = 0
            continue
        title = node_title(node)
        if is_front_node(node):
            host = str(node.get("host") or title)
            ok, bad = probe_front_ports(node)
            ports = node.get("front_ports") or {}
            silent = bool(ports) and len(bad) >= len(ports)
            partial = bool(ok) and bool(bad)
            if silent:
                FRONT_PORT_FAILS[host] = FRONT_PORT_FAILS.get(host, 0) + 1
            else:
                FRONT_PORT_FAILS[host] = 0
            if (
                FRONT_PORT_FAILS.get(host, 0) >= PROBE_FAILS_ALERT
                and host not in ALERT_DOWN
            ):
                telegram_send("%s: порты фронта не отвечают (%s)." % (title, ", ".join(bad)))
                ALERT_DOWN.add(host)
                print("alert down", title, flush=True)
            elif not silent and host in ALERT_DOWN:
                telegram_send("%s снова отвечает на front_ports." % title)
                ALERT_DOWN.discard(host)
                print("alert up", title, flush=True)
            if partial:
                FRONT_PARTIAL_FAILS[host] = FRONT_PARTIAL_FAILS.get(host, 0) + 1
            else:
                FRONT_PARTIAL_FAILS[host] = 0
            if (
                FRONT_PARTIAL_FAILS.get(host, 0) >= PROBE_FAILS_ALERT
                and host not in ALERT_FRONT_PARTIAL
            ):
                telegram_send(
                    "%s: часть front_ports недоступна (ок: %s; нет: %s)."
                    % (title, ", ".join(ok), ", ".join(bad))
                )
                ALERT_FRONT_PARTIAL.add(host)
                print("alert front partial", title, flush=True)
            elif not partial and host in ALERT_FRONT_PARTIAL:
                telegram_send("%s: все front_ports снова в порядке." % title)
                ALERT_FRONT_PARTIAL.discard(host)
            # k-pax-limit heartbeats land in NODE_HEALTH[host].
            sample = snapshot.get(host)
            limit_silent = sample is None or now - float(sample["seen"]) > FRONT_LIMIT_AFTER
            if (not silent) and limit_silent and host not in ALERT_FRONT_LIMIT:
                telegram_send(
                    "%s: нет свежих данных нагрузки >%ds (проверьте k-pax-limit)."
                    % (title, FRONT_LIMIT_AFTER)
                )
                ALERT_FRONT_LIMIT.add(host)
                print("alert front limit", title, flush=True)
            elif not limit_silent and host in ALERT_FRONT_LIMIT:
                telegram_send("%s: нагрузка снова приходит с ноды." % title)
                ALERT_FRONT_LIMIT.discard(host)
            if host and not probe_media_https(host):
                MEDIA_HTTPS_FAILS[host] = MEDIA_HTTPS_FAILS.get(host, 0) + 1
            else:
                MEDIA_HTTPS_FAILS[host] = 0
            if (
                MEDIA_HTTPS_FAILS.get(host, 0) >= PROBE_FAILS_ALERT
                and host not in ALERT_MEDIA_HTTPS
            ):
                telegram_send(
                    "%s: HTTPS %s:443 (SNI camouflage) не отвечает."
                    % (title, MEDIA_HTTPS_HOST)
                )
                ALERT_MEDIA_HTTPS.add(host)
                print("alert media https", title, flush=True)
            elif (
                MEDIA_HTTPS_FAILS.get(host, 0) == 0
                and host in ALERT_MEDIA_HTTPS
            ):
                telegram_send("%s: HTTPS %s снова отвечает." % (title, MEDIA_HTTPS_HOST))
                ALERT_MEDIA_HTTPS.discard(host)
            continue
        host = node["host"]
        sample = snapshot.get(host)
        silent = sample is None or now - float(sample["seen"]) > ALERT_AFTER
        if silent and host not in ALERT_DOWN:
            telegram_send("%s недоступна. Нет данных больше %d секунд." % (title, ALERT_AFTER))
            ALERT_DOWN.add(host)
            print("alert down", title, flush=True)
        elif not silent and host in ALERT_DOWN:
            telegram_send("%s снова на связи." % title)
            ALERT_DOWN.discard(host)
            print("alert up", title, flush=True)
        if probe_node(host):
            PROBE_FAILS[host] = 0
            if host in PROBE_DOWN:
                telegram_send("%s: запасной канал снова отвечает." % title)
                PROBE_DOWN.discard(host)
                print("probe up", title, flush=True)
        else:
            PROBE_FAILS[host] = PROBE_FAILS.get(host, 0) + 1
            if PROBE_FAILS[host] >= PROBE_FAILS_ALERT and host not in PROBE_DOWN:
                telegram_send(
                    "%s: запасной канал не отвечает около %d секунд. Основной статус: %s."
                    % (title, PROBE_FAILS[host] * ALERT_EVERY, "нет данных" if silent else "узел на связи")
                )
                PROBE_DOWN.add(host)
                print("probe down", title, flush=True)


def alert_loop() -> None:
    while True:
        time.sleep(ALERT_EVERY)
        try:
            check_alerts()
        except Exception as exc:  # noqa: BLE001
            print("alert loop", type(exc).__name__, flush=True)


def expire_loop() -> None:
    done_day = ""
    try:
        if spare_count() == 0:
            node_maintenance()
    except Exception as exc:  # noqa: BLE001
        print("node maintenance", type(exc).__name__, flush=True)
    while True:
        time.sleep(600)
        try:
            expire_due()
        except Exception as exc:  # noqa: BLE001
            print("expire loop", exc, flush=True)
        now = datetime.now(timezone.utc)
        if (now.hour, now.minute) >= NODE_MAINTENANCE_UTC and now.hour < NODE_MAINTENANCE_UTC[0] + 2 and done_day != now.strftime("%Y-%m-%d"):
            done_day = now.strftime("%Y-%m-%d")
            try:
                node_maintenance()
            except Exception as exc:  # noqa: BLE001
                print("node maintenance", type(exc).__name__, flush=True)
        try:
            purge_stale_unverified()
        except Exception as exc:  # noqa: BLE001
            print("purge pending", type(exc).__name__, flush=True)


def remind_loop() -> None:
    while True:
        time.sleep(3600)
        try:
            remind_due()
        except Exception as exc:  # noqa: BLE001
            print("remind loop", type(exc).__name__, flush=True)


def main() -> None:
    init_db()
    if len(sys.argv) > 1 and sys.argv[1] == "expire":
        expire_due()
        return
    if len(sys.argv) == 3 and sys.argv[1] == "delete":
        delete_user(sys.argv[2])
        print("deleted", sys.argv[2], flush=True)
        return
    if len(sys.argv) in (2, 3) and sys.argv[1] == "reset-2fa":
        target = sys.argv[2] if len(sys.argv) == 3 else "kpax"
        if target not in BRANDS:
            print("unknown brand", target, flush=True)
            return
        with brand_context(target):
            reset_totp()
        print("admin 2fa reset for", target, "- admin sessions closed", flush=True)
        return
    if STAGE:
        print("stage mode: background loops, node pushes and mail are off", flush=True)
    else:
        threading.Thread(target=expire_loop, daemon=True).start()
        threading.Thread(target=remind_loop, daemon=True).start()
        threading.Thread(target=platega_loop, daemon=True).start()
        threading.Thread(target=alert_loop, daemon=True).start()
        threading.Thread(target=telegram_restore_loop, daemon=True).start()
        threading.Thread(target=mail_restore_loop, daemon=True).start()
        threading.Thread(target=mail_restore_loop, args=("xplm",), daemon=True).start()
    # Autotest runs in stage too — ingest may still create incidents locally.
    threading.Thread(target=client_autotest_loop, daemon=True).start()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print("listening %s:%d" % (HOST, PORT), flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
