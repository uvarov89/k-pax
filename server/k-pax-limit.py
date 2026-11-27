#!/usr/bin/env python3
"""Tell the account server which devices are online, then close the extras."""

from __future__ import annotations

import http.client
import json
import os
import re
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

SINGBOX = "/etc/sing-box/config.json"
LIMIT = "/etc/k-pax/limit.json"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
FROM_RE = re.compile(r"\[(\d+) [\d.]+(?:ms|s)\].*inbound connection from (\S+)")
USER_RE = re.compile(r"\[(\d+) [\d.]+(?:ms|s)\].*\[([^\]\s]+)\] inbound connection to ")


def host_of(addr: str) -> str:
    if addr.startswith("["):
        end = addr.find("]")
        return addr[1:end] if end > 1 else addr
    if addr.count(":") == 1:
        return addr.rsplit(":", 1)[0]
    return addr


def attributions(text: str) -> dict[str, str]:
    pending: dict[str, str] = {}
    found: dict[str, str] = {}
    for line in ANSI_RE.sub("", text).splitlines():
        arrived = FROM_RE.search(line)
        if arrived:
            pending[arrived.group(1)] = host_of(arrived.group(2))
            continue
        named = USER_RE.search(line)
        if named and named.group(1) in pending:
            found[pending[named.group(1)]] = named.group(2)
    return found


def clash_api() -> tuple[str, str]:
    cfg = json.load(open(SINGBOX, encoding="utf-8"))
    api = cfg["experimental"]["clash_api"]
    base = str(api["external_controller"])
    if "://" not in base:
        base = "http://" + base
    return base.rstrip("/"), str(api.get("secret") or "")


def request(url: str, secret: str, payload: bytes | None = None, method: str = "GET") -> bytes:
    req = urllib.request.Request(url, data=payload, method=method)
    if secret:
        req.add_header("Authorization", "Bearer " + secret)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=8) as response:
        return response.read()


def panel_post(settings: dict, body: bytes) -> bytes:
    """POST sessions to the panel.

    Optional ``panel_ip`` connects straight to the origin and skips Cloudflare.
    TLS still validates the certificate for the hostname in ``panel`` (SNI/Host).
    """
    url = str(settings["panel"])
    secret = str(settings["secret"])
    connect_ip = str(settings.get("panel_ip") or "").strip()
    if not connect_ip:
        return request(url, secret, body, "POST")
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("panel url")
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    port = parsed.port or 443
    headers = {
        "Host": parsed.hostname,
        "Authorization": "Bearer " + secret,
        "Content-Type": "application/json",
        "Content-Length": str(len(body)),
        "User-Agent": "k-pax-limit",
    }
    context = ssl.create_default_context()
    raw = socket.create_connection((connect_ip, port), timeout=8)
    sock = context.wrap_socket(raw, server_hostname=parsed.hostname)
    conn = http.client.HTTPSConnection(parsed.hostname, port, timeout=8, context=context)
    try:
        conn.sock = sock
        conn.request("POST", path, body=body, headers=headers)
        response = conn.getresponse()
        data = response.read()
        if response.status >= 400:
            raise urllib.error.HTTPError(url, response.status, response.reason, response.headers, None)
        return data
    finally:
        conn.close()


XRAY_RE = re.compile(r"from (\S+) accepted .*?\[([^\]]*)\] email: (kp-[0-9a-f]{8})")
XRAY_API = "127.0.0.1:10085"
XRAY_TOTALS: dict[str, list[int]] = {}
XRAY_PROTO: dict[str, str] = {}
XRAY_LAST_IP: dict[str, str] = {}


def classify(meta: dict) -> str:
    text = (str(meta.get("inbound") or "") + " " + str(meta.get("type") or "")).lower()
    if "hysteria" in text or "hy2" in text:
        return "hy2"
    if "tuic" in text:
        return "tuic"
    if "grpc" in text:
        return "grpc"
    if "ws" in text or "websocket" in text:
        return "message"
    if "reality" in text:
        return "reality"
    if "vless" in text:
        return "vless"
    return "other"


def xray_pairs() -> list[tuple[str, str]]:
    # Keep the window near the panel device TTL so brief XHTTP activity does not linger as "online".
    try:
        result = subprocess.run(
            ["journalctl", "-u", "xray", "--since", "45 sec ago", "-o", "cat", "--no-pager"],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    found: dict[tuple[str, str], None] = {}
    for match in XRAY_RE.finditer(result.stdout or ""):
        ip = host_of(match.group(1))
        route = match.group(2)
        user = match.group(3)
        if ip in ("0.0.0.0", "127.0.0.1", "::", "::1") or ip.startswith("127."):
            continue
        if re.fullmatch(r"[0-9A-Fa-f:.]+", ip) and re.fullmatch(r"kp-[0-9a-f]{8}", user):
            found[(user, ip)] = None
            XRAY_PROTO[user] = "xhttp" if "xhttp" in route else "message"
    return list(found)


def xray_traffic() -> dict[str, list[int]]:
    """Per-user bytes from the Xray stats API, kept as running totals between ticks."""
    try:
        result = subprocess.run(
            ["xray", "api", "statsquery", "--server=" + XRAY_API, "-pattern", "user>>>", "-reset"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        stats = json.loads(result.stdout or "{}").get("stat") or []
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return XRAY_TOTALS
    for item in stats:
        parts = str(item.get("name") or "").split(">>>")
        if len(parts) != 4 or not re.fullmatch(r"kp-[0-9a-f]{8}", parts[1]):
            continue
        try:
            value = int(item.get("value") or 0)
        except (TypeError, ValueError):
            continue
        totals = XRAY_TOTALS.setdefault(parts[1], [0, 0])
        totals[0 if parts[3] == "uplink" else 1] += max(0, value)
    return XRAY_TOTALS


def live_sessions(base: str, secret: str, owners: dict[str, str]) -> tuple[list[dict], list[dict]]:
    raw = json.loads(request(base + "/connections", secret))
    grouped: dict[tuple[str, str], list[str]] = {}
    flows: list[dict] = []
    for item in raw.get("connections") or []:
        meta = item.get("metadata") or {}
        ip = str(meta.get("sourceIP") or "")
        conn_id = str(item.get("id") or "")
        user = owners.get(ip) or ""
        if not (ip and conn_id and user):
            continue
        grouped.setdefault((user, ip), []).append(conn_id)
        try:
            up = max(0, int(item.get("upload") or 0))
            down = max(0, int(item.get("download") or 0))
        except (TypeError, ValueError):
            up = down = 0
        flows.append(
            {
                "user": user,
                "id": conn_id[:64],
                "up": up,
                "down": down,
                "proto": classify(meta),
            }
        )
    sessions = [{"user": user, "ip": ip, "ids": ids[:40]} for (user, ip), ids in list(grouped.items())[:500]]
    return sessions, flows[:500]


def recent_log() -> str:
    result = subprocess.run(
        ["journalctl", "-u", "sing-box", "--since", "3 min ago", "-o", "cat", "--no-pager"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    return result.stdout or ""


IFACE = ""
COUNTERS = {"time": 0.0, "rx": 0, "tx": 0}


def default_iface() -> str:
    global IFACE
    if IFACE:
        return IFACE
    found = re.search(r" dev (\S+)", subprocess.getoutput("ip route get 1.1.1.1"))
    IFACE = found.group(1) if found else "eth0"
    return IFACE


def iface_bytes(name: str) -> tuple[int, int]:
    for line in open("/proc/net/dev", encoding="utf-8"):
        if name + ":" not in line:
            continue
        left, values = line.split(":", 1)
        if left.strip() != name:
            continue
        parts = values.split()
        return int(parts[0]), int(parts[8])
    return 0, 0


def sample_stats() -> dict:
    load = float(open("/proc/loadavg", encoding="utf-8").read().split()[0])
    rx, tx = iface_bytes(default_iface())
    now = time.time()
    rx_mbps = tx_mbps = 0.0
    if COUNTERS["time"]:
        elapsed = now - COUNTERS["time"]
        if elapsed > 0:
            rx_mbps = max(0.0, (rx - COUNTERS["rx"]) * 8 / elapsed / 1_000_000)
            tx_mbps = max(0.0, (tx - COUNTERS["tx"]) * 8 / elapsed / 1_000_000)
    COUNTERS["time"] = now
    COUNTERS["rx"] = rx
    COUNTERS["tx"] = tx
    return {
        "load": round(load, 2),
        "cores": os.cpu_count() or 1,
        "rx_mbps": round(rx_mbps, 1),
        "tx_mbps": round(tx_mbps, 1),
    }


def tick() -> None:
    settings = json.load(open(LIMIT, encoding="utf-8"))
    base, secret = clash_api()
    sessions, flows = live_sessions(base, secret, attributions(recent_log()))
    # Xray (WS and XHTTP) devices count for online and the device limit; they cannot be closed from here.
    pairs = xray_pairs()
    for user, ip in pairs:
        XRAY_LAST_IP[user] = ip
        sessions.append({"user": user, "ip": ip, "ids": ["x-" + user]})
    before = {user: sum(values) for user, values in XRAY_TOTALS.items()}
    totals = xray_traffic()
    seen = {user for user, _ip in pairs}
    active_xray: set[str] = set(seen)
    for user, values in totals.items():
        grew = sum(values) > before.get(user, 0)
        if grew:
            active_xray.add(user)
        if user not in seen and grew and user in XRAY_LAST_IP:
            sessions.append({"user": user, "ip": XRAY_LAST_IP[user], "ids": ["x-" + user]})
    # Only report flows for users active this tick. XRAY_TOTALS is cumulative for the
    # process lifetime; dumping every key made the panel treat idle history as online.
    for user in active_xray:
        up, down = totals.get(user, [0, 0])
        flows.append({"user": user, "id": "xray-" + user, "up": up, "down": down, "proto": XRAY_PROTO.get(user, "xhttp")})
    body = json.dumps(
        {"sessions": sessions[:500], "flows": flows[:800], "stats": sample_stats()}
    ).encode()
    answer = json.loads(panel_post(settings, body))
    closed = 0
    for conn_id in answer.get("close") or []:
        if str(conn_id).startswith("x-"):
            continue
        request(base + "/connections/" + str(conn_id), secret, method="DELETE")
        closed += 1
    print("sessions %d (xray %d) closed %d" % (len(sessions), len(pairs), closed), flush=True)


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "self-test":
        sample = "\n".join(
            [
                "\x1b[36mINFO\x1b[0m[0004] [\x1b[38;5;38m111\x1b[0m 0ms] inbound/hysteria2[hy2]: inbound connection from 203.0.113.5:4000",
                "\x1b[36mINFO\x1b[0m[0004] [\x1b[38;5;38m111\x1b[0m 0ms] inbound/hysteria2[hy2]: [kp-aaaa] inbound connection to one.example:443",
                "INFO[0013] [222 1.2s] inbound/vless[vless-reality]: inbound connection from [2001:db8::5]:4000",
                "INFO[0013] [222 1.2s] inbound/vless[vless-reality]: [kp-bbbb] inbound connection to two.example:443",
            ]
        )
        got = attributions(sample)
        assert got == {"203.0.113.5": "kp-aaaa", "2001:db8::5": "kp-bbbb"}, got
        xray_line = "2026/10/27 07:43:40.682746 from 198.51.100.7:51000 accepted tcp:www.gstatic.com:443 [xhttp-tls >> direct] email: kp-0123abcd"
        match = XRAY_RE.search(xray_line)
        assert match and match.group(3) == "kp-0123abcd" and "xhttp" in match.group(2), match
        assert XRAY_RE.search("from 198.51.100.7:0 accepted tcp:1.1.1.1:443 [direct] email: kp-0123abcd").group(2) == "direct"
        print("ok")
        return
    while True:
        try:
            tick()
        except Exception as exc:  # noqa: BLE001 — keep the loop alive, without dumping addresses
            print("tick failed: " + type(exc).__name__, flush=True)
        time.sleep(5)


if __name__ == "__main__":
    main()
