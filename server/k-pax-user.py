#!/usr/bin/env python3
"""Add or remove K-Pax users in the local sing-box and Xray configs.

Every restart drops all connections on the node, so services restart only
when their config really changed, and `batch` applies many changes at once.
Idempotent add/remove: re-sending an existing user is a no-op (no restart).
"""

import base64
import fcntl
import json
import os
import shutil
import subprocess
import sys
import tempfile

CONFIG = "/etc/sing-box/config.json"
XRAY = "/usr/local/etc/xray/config.json"
LOCK = "/var/lock/k-pax-singbox.lock"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def user_name(uuid: str) -> str:
    return "kp-" + uuid.replace("-", "")[:8]


def check_credentials(uuid: str, password: str) -> None:
    if len(uuid) < 32 or len(password) < 16:
        fail("bad credentials")


def _vless_entry(inbound: dict, name: str, uuid: str) -> dict:
    entry = {"name": name, "uuid": uuid}
    transport = (inbound.get("transport") or {}).get("type")
    if transport not in ("grpc", "ws", "http", "httpupgrade"):
        entry["flow"] = "xtls-rprx-vision"
    return entry


def _same_vless(user: dict, entry: dict) -> bool:
    if user.get("uuid") != entry.get("uuid"):
        return False
    if user.get("name") != entry.get("name"):
        return False
    want_flow = entry.get("flow")
    have_flow = user.get("flow")
    if want_flow:
        return have_flow == want_flow
    return not have_flow


def apply_singbox(cfg: dict, action: str, uuid: str, password: str) -> bool:
    name = user_name(uuid)
    changed = False
    saw_vless = False
    for inbound in cfg.get("inbounds", []):
        users = inbound.setdefault("users", [])
        kind = inbound.get("type")
        if kind == "vless":
            saw_vless = True
            entry = _vless_entry(inbound, name, uuid)
            if action == "add":
                existing = next(
                    (
                        user
                        for user in users
                        if user.get("uuid") == uuid or user.get("name") == name
                    ),
                    None,
                )
                if existing is not None and _same_vless(existing, entry):
                    continue
                kept = [
                    user
                    for user in users
                    if user.get("uuid") != uuid and user.get("name") != name
                ]
                kept.append(entry)
            else:
                kept = [
                    user
                    for user in users
                    if user.get("uuid") != uuid and user.get("name") != name
                ]
                if len(kept) == len(users):
                    continue
        elif kind == "hysteria2":
            if action == "add":
                existing = next((user for user in users if user.get("name") == name), None)
                if existing is not None and existing.get("password") == password:
                    continue
                kept = [user for user in users if user.get("name") != name]
                kept.append({"name": name, "password": password})
            else:
                kept = [user for user in users if user.get("name") != name]
                if len(kept) == len(users):
                    continue
        elif kind == "tuic":
            if action == "add":
                existing = next(
                    (
                        user
                        for user in users
                        if user.get("uuid") == uuid or user.get("name") == name
                    ),
                    None,
                )
                if (
                    existing is not None
                    and existing.get("uuid") == uuid
                    and existing.get("password") == password
                ):
                    continue
                kept = [
                    user
                    for user in users
                    if user.get("uuid") != uuid and user.get("name") != name
                ]
                kept.append({"name": name, "uuid": uuid, "password": password})
            else:
                kept = [
                    user
                    for user in users
                    if user.get("uuid") != uuid and user.get("name") != name
                ]
                if len(kept) == len(users):
                    continue
        else:
            continue
        inbound["users"] = kept
        changed = True
    if action == "add" and not saw_vless:
        fail("no vless/hysteria2 inbound")
    if action == "add" and not any(
        user.get("uuid") == uuid
        for inbound in cfg.get("inbounds", [])
        if inbound.get("type") == "vless"
        for user in inbound.get("users", [])
    ):
        fail("no vless/hysteria2 inbound")
    return changed


def apply_xray(cfg: dict, action: str, uuid: str) -> bool:
    name = user_name(uuid)
    changed = False
    for inbound in cfg.get("inbounds", []):
        if inbound.get("protocol") != "vless":
            continue
        stream = inbound.get("streamSettings") or {}
        if stream.get("network") not in ("ws", "xhttp"):
            continue
        settings = inbound.setdefault("settings", {})
        before = settings.get("clients") or []
        if action == "add":
            if any(client.get("id") == uuid for client in before):
                clients = before
            else:
                clients = [
                    client
                    for client in before
                    if client.get("email") != name and client.get("id") != uuid
                ]
                clients.append({"id": uuid, "email": name})
        else:
            clients = [
                client
                for client in before
                if client.get("email") != name and client.get("id") != uuid
            ]
        before_keys = sorted((c.get("id") or "", c.get("email") or "") for c in before)
        after_keys = sorted((c.get("id") or "", c.get("email") or "") for c in clients)
        if before_keys != after_keys:
            settings["clients"] = clients
            changed = True
        if settings.get("decryption") != "none":
            settings["decryption"] = "none"
            changed = True
    return changed


def write_json(path, cfg, mode=None):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".kpax.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(cfg, handle, indent=2)
            handle.write("\n")
        st = os.stat(path)
        os.chown(tmp, st.st_uid, st.st_gid)
        os.chmod(tmp, mode if mode is not None else st.st_mode & 0o777)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def restart(service: str, path: str, backup: str) -> None:
    result = subprocess.run(["systemctl", "restart", service], capture_output=True, text=True)
    active = subprocess.run(["systemctl", "is-active", service], capture_output=True, text=True)
    if result.returncode != 0 or active.stdout.strip() != "active":
        shutil.copy2(backup, path)
        subprocess.run(["systemctl", "restart", service], capture_output=True)
        raise RuntimeError(result.stderr.strip()[-200:] or service + " did not stay active")


def apply(changes):
    with open(CONFIG, encoding="utf-8") as handle:
        cfg = json.load(handle)
    changed = False
    for action, uuid, password in changes:
        changed = apply_singbox(cfg, action, uuid, password) or changed
    if changed:
        backup = CONFIG + ".kpax-bak"
        shutil.copy2(CONFIG, backup)
        write_json(CONFIG, cfg)
        check = subprocess.run(["sing-box", "check", "-c", CONFIG], capture_output=True, text=True)
        if check.returncode != 0:
            shutil.copy2(backup, CONFIG)
            fail(check.stderr.strip() or "sing-box check failed")
        try:
            restart("sing-box", CONFIG, backup)
        except RuntimeError as exc:
            fail(str(exc))
    xchanged = False
    if os.path.isfile(XRAY):
        with open(XRAY, encoding="utf-8") as handle:
            xcfg = json.load(handle)
        for action, uuid, _password in changes:
            xchanged = apply_xray(xcfg, action, uuid) or xchanged
        if xchanged:
            backup = XRAY + ".kpax-bak"
            shutil.copy2(XRAY, backup)
            write_json(XRAY, xcfg, 0o600)
            check = subprocess.run(
                ["xray", "run", "-test", "-config", XRAY], capture_output=True, text=True
            )
            if check.returncode != 0:
                shutil.copy2(backup, XRAY)
                fail("message sync failed: " + (check.stderr.strip()[-200:] or "xray check failed"))
            try:
                restart("xray", XRAY, backup)
            except RuntimeError as exc:
                fail("message sync failed: " + str(exc)[:200])
    return changed or xchanged


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "batch":
        try:
            items = json.loads(base64.b64decode(sys.argv[2]).decode())
        except ValueError:
            fail("bad batch")
        changes = []
        for item in items:
            action = str(item.get("action") or "")
            if action not in ("add", "remove"):
                fail("bad batch action")
            uuid, password = str(item.get("uuid") or "").strip(), str(item.get("password") or "").strip()
            check_credentials(uuid, password)
            changes.append((action, uuid, password))
    elif len(sys.argv) == 4 and sys.argv[1] in ("add", "remove"):
        uuid, password = sys.argv[2].strip(), sys.argv[3].strip()
        check_credentials(uuid, password)
        changes = [(sys.argv[1], uuid, password)]
    else:
        fail("usage: k-pax-user.py add|remove UUID HY2_PASSWORD | batch BASE64_JSON")
    os.makedirs("/var/lock", exist_ok=True)
    with open(LOCK, "a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        changed = apply(changes)
    print("ok changed" if changed else "ok")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 — report to the panel over SSH
        fail(str(exc))
