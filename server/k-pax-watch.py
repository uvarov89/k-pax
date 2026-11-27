#!/usr/bin/env python3
"""Runs on exit nodes: checks the K-Pax and X-Plm sites and mail from outside, alerts the operator in Telegram."""

from __future__ import annotations

import json
import os
import socket
import ssl
import sys
import urllib.request

CONFIG_PATH = "/etc/k-pax-watch.json"
STATE_PATH = "/var/lib/k-pax-watch/state.json"
FAILS_ALERT = 2
GROUPS = (
    ("kpax", "K-Pax: сайт", ("https://k-pax.space/healthz", "https://sub.k-pax.space/healthz")),
    ("xplm", "X-Plm: сайт", ("https://x-plm.online/healthz", "https://sub.x-plm.online/healthz")),
    ("xplm-mail", "X-Plm: почта", ("smtp://mail.x-plm.online:25", "imaps://mail.x-plm.online:993")),
)


def check_http(url: str) -> str:
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "k-pax-watch"})
        with urllib.request.urlopen(request, timeout=10) as response:
            body = response.read(64).decode("utf-8", "replace").strip()
            if response.status != 200 or body != "ok":
                return "ответ %d" % response.status
            return ""
    except Exception as exc:  # noqa: BLE001
        code = getattr(exc, "code", None)
        return "ответ %d" % code if code else type(exc).__name__


def check_smtp(host: str, port: int) -> str:
    try:
        with socket.create_connection((host, port), timeout=10) as sock:
            banner = sock.recv(128).decode("ascii", "replace")
            return "" if banner.startswith("220") else "нет приветствия"
    except Exception as exc:  # noqa: BLE001
        return type(exc).__name__


def check_imaps(host: str, port: int) -> str:
    try:
        context = ssl.create_default_context()
        with socket.create_connection((host, port), timeout=10) as sock:
            with context.wrap_socket(sock, server_hostname=host) as tls:
                banner = tls.recv(128).decode("ascii", "replace")
                return "" if banner.startswith("* OK") else "нет приветствия"
    except ssl.SSLCertVerificationError:
        return "сертификат"
    except Exception as exc:  # noqa: BLE001
        return type(exc).__name__


def check(target: str) -> str:
    """Empty string when healthy, otherwise a short reason."""
    if target.startswith("http"):
        return check_http(target)
    scheme, rest = target.split("://", 1)
    host, port = rest.rsplit(":", 1)
    return check_smtp(host, int(port)) if scheme == "smtp" else check_imaps(host, int(port))


def send(cfg: dict, text: str) -> None:
    body = json.dumps({"chat_id": cfg["chat"], "text": text, "disable_web_page_preview": True}).encode()
    request = urllib.request.Request(
        "https://api.telegram.org/bot" + cfg["token"] + "/sendMessage",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        response.read()


def notify(cfg: dict, text: str) -> bool:
    try:
        send(cfg, text)
        return True
    except Exception as exc:  # noqa: BLE001
        print("telegram failed", type(exc).__name__, flush=True)
        return False


def load_state() -> dict:
    try:
        with open(STATE_PATH, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return {}
    if "fails" in state:
        return {"kpax": {"fails": int(state.get("fails", 0)), "down": bool(state.get("down"))}}
    return state


def save_state(state: dict) -> None:
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle)
    os.replace(tmp, STATE_PATH)


def label(target: str) -> str:
    return target.split("://", 1)[1].split("/", 1)[0]


def main() -> None:
    with open(CONFIG_PATH, encoding="utf-8") as handle:
        cfg = json.load(handle)
    name = str(cfg.get("name") or "узел")
    if len(sys.argv) > 1 and sys.argv[1] == "test":
        send(cfg, "Проверка K-Pax и X-Plm с узла «%s» подключена." % name)
        print("test sent")
        return
    state = load_state()
    for key, title, targets in GROUPS:
        if not cfg.get("smtp", True):
            targets = tuple(target for target in targets if not target.startswith("smtp://"))
        slot = state.get(key) or {"fails": 0, "down": False}
        problems = [(target, reason) for target in targets if (reason := check(target))]
        if problems:
            slot["fails"] = int(slot.get("fails", 0)) + 1
            detail = "; ".join("%s — %s" % (label(target), reason) for target, reason in problems)
            print(key, "fail", slot["fails"], detail, flush=True)
            if slot["fails"] >= FAILS_ALERT and not slot.get("down"):
                text = "%s не отвечает с узла «%s» (%d проверки подряд). %s" % (title, name, slot["fails"], detail)
                slot["down"] = notify(cfg, text)
        elif slot.get("down"):
            if notify(cfg, "%s снова отвечает (узел «%s»)." % (title, name)):
                slot = {"fails": 0, "down": False}
        else:
            slot = {"fails": 0, "down": False}
        state[key] = slot
    save_state(state)


if __name__ == "__main__":
    main()
