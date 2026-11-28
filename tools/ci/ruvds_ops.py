#!/usr/bin/env python3
"""Scoped RuVDS API helper. Prints status/balance; reboot only with numeric id.

Env: RUVDS_API_TOKEN, RUVDS_SERVER_IDS (optional ru=123,fi=456), ACTION, TARGET
Never prints tokens or admin passwords.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

TOKEN = os.environ.get("RUVDS_API_TOKEN") or ""
ACTION = (os.environ.get("ACTION") or "status").strip()
TARGET = (os.environ.get("TARGET") or "").strip()
IDMAP = os.environ.get("RUVDS_SERVER_IDS") or ""
out = Path("out")
out.mkdir(parents=True, exist_ok=True)

if not TOKEN:
    print("STATUS=FAIL missing RUVDS_API_TOKEN")
    print("PHONE_FALLBACK=RuVDS mobile app / console power cycle")
    sys.exit(1)


def req(url: str, method: str = "GET", body: dict | None = None) -> tuple[int, object]:
    data = None
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/json",
    }
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {"error": str(e)}
        except json.JSONDecodeError:
            parsed = {"error": raw[:500]}
        return e.code, parsed


def sanitize_servers(payload: object) -> list[dict]:
    items: object = payload
    if isinstance(payload, dict):
        items = (
            payload.get("items")
            or payload.get("result")
            or payload.get("servers")
            or payload.get("data")
            or []
        )
        if isinstance(items, dict):
            items = items.get("items") or []
    out_list = []
    if not isinstance(items, list):
        return out_list
    for it in items:
        if not isinstance(it, dict):
            continue
        out_list.append(
            {
                "id": it.get("id"),
                "ip": it.get("ip") or it.get("ipv4") or it.get("primaryIp"),
                "running": it.get("running"),
                "state": it.get("state") or it.get("status"),
                "paid": it.get("paid"),
                "paidTill": it.get("paidTill") or it.get("paid_till"),
            }
        )
    return out_list


def resolve_server_id(target: str) -> str:
    if target.isdigit():
        return target
    m = {}
    for part in IDMAP.split(","):
        part = part.strip()
        if "=" in part:
            k, v = part.split("=", 1)
            m[k.strip()] = v.strip()
    return m.get(target, "")


if ACTION == "balance":
    for url in (
        "https://api.ruvds.com/v2/balance",
        "https://ruvds.com/api/v2/balance",
    ):
        code, data = req(url)
        if code == 200:
            # keep only amount/currency-like fields
            safe = {
                k: data.get(k)
                for k in ("amount", "currency", "balance", "value")
                if isinstance(data, dict) and k in data
            } or {"http": code, "keys": list(data)[:12] if isinstance(data, dict) else type(data).__name__}
            (out / "ruvds-balance.json").write_text(
                json.dumps(safe, indent=2) + "\n", encoding="utf-8"
            )
            print(json.dumps(safe, indent=2))
            print("STATUS=OK")
            sys.exit(0)
    print("STATUS=FAIL balance endpoints rejected")
    sys.exit(1)

if ACTION == "status":
    last = None
    for url in (
        "https://api.ruvds.com/v2/servers",
        "https://ruvds.com/api/v2/servers",
    ):
        code, data = req(url)
        last = (code, data)
        if code == 200:
            safe = sanitize_servers(data)
            (out / "ruvds-status.json").write_text(
                json.dumps(safe, indent=2) + "\n", encoding="utf-8"
            )
            print(json.dumps(safe, indent=2))
            print("STATUS=OK")
            sys.exit(0)
    print("STATUS=FAIL status", last[0] if last else "?")
    sys.exit(1)

if ACTION == "reboot":
    sid = resolve_server_id(TARGET)
    if not sid.isdigit():
        print("STATUS=FAIL reboot needs numeric id or RUVDS_SERVER_IDS map ru=ID")
        sys.exit(1)
    ok = False
    for url in (
        f"https://api.ruvds.com/v2/servers/{sid}/command",
        f"https://ruvds.com/api/v2/servers/{sid}/command",
    ):
        code, data = req(url, method="POST", body={"type": "reset"})
        (out / "ruvds-reboot.json").write_text(
            json.dumps({"http": code, "id": sid, "result_keys": list(data)[:20] if isinstance(data, dict) else []}, indent=2)
            + "\n",
            encoding="utf-8",
        )
        if code in (200, 201, 202, 204):
            ok = True
            break
    if not ok:
        # legacy GET with token as sessionToken (some accounts still use this)
        from urllib.parse import urlencode

        q = urlencode({"sessionToken": TOKEN, "id": sid, "type": "reset"})
        code, data = req(f"https://ruvds.com/api/server/command/?{q}")
        (out / "ruvds-reboot.json").write_text(
            json.dumps({"http": code, "id": sid, "legacy": True}, indent=2) + "\n",
            encoding="utf-8",
        )
        ok = code in (200, 201, 202, 204) or (
            isinstance(data, dict) and data.get("errorCode") in (0, "0", None)
        )
    print("reboot_requested id=%s ok=%s" % (sid, ok))
    print("STATUS=OK" if ok else "STATUS=FAIL")
    sys.exit(0 if ok else 1)

print("STATUS=FAIL unknown action", ACTION)
sys.exit(2)
