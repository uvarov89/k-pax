#!/usr/bin/env python3
"""In-place allowlisted config patches on the VPS (no full config to GitHub).

Usage:
  config_patch.py <kind> [--dry-run] [--deadman N] [--digest HEX] set:field=value ...

Real (non-dry) applies require --digest matching sha256 of sorted 'field=value' lines.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent


def run_bash_resolve(kind: str) -> dict:
    # Source config_paths via bash printenv-style
    script = f"""
source "{SCRIPTS}/config_paths.sh"
config_resolve "{kind}" || exit $?
printf 'PATH=%s\\n' "$CONFIG_PATH"
printf 'SERVICE=%s\\n' "$CONFIG_SERVICE"
printf 'VALIDATOR=%s\\n' "$CONFIG_VALIDATOR"
printf 'DEADMAN_DEFAULT=%s\\n' "$CONFIG_DEADMAN_DEFAULT"
"""
    out = subprocess.check_output(["bash", "-c", script], text=True)
    meta = {}
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    return meta


def digest_of(patches: list[tuple[str, str]]) -> str:
    lines = sorted(f"{k}={v}" for k, v in patches)
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()


def scrub(s: str) -> str:
    s = re.sub(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        "<uuid>",
        s,
        flags=re.I,
    )
    for pat, repl in [
        (r'"private_key"\s*:\s*"[^"]+"', '"private_key":"<sk>"'),
        (r'"public_key"\s*:\s*"[^"]+"', '"public_key":"<pbk>"'),
        (r'"password"\s*:\s*"[^"]+"', '"password":"<redacted>"'),
        (r'"ssh_key"\s*:\s*"[^"]+"', '"ssh_key":"<redacted>"'),
        (r'"token"\s*:\s*"[^"]+"', '"token":"<redacted>"'),
    ]:
        s = re.sub(pat, repl, s)
    return s


SINGBOX_OK = re.compile(
    r"^(log\.level|inbound\.[A-Za-z0-9_.-]+\.(sni|listen_port|server_name)|"
    r"outbound\.[A-Za-z0-9_.-]+\.(server|server_port|sni|server_name))$"
)
PANEL_OK = re.compile(r"^nodes\.[A-Za-z0-9_-]+\.(reality_sni|self_domain|enabled|host)$")
DRILL_OK = re.compile(r"^[A-Za-z0-9_.-]+$")


def refuse(msg: str) -> None:
    print("STATUS=FAIL", msg)
    raise SystemExit(2)


def apply_singbox(cfg: dict, key: str, val: str) -> None:
    if key == "log.level":
        cfg.setdefault("log", {})["level"] = val
        return
    m = re.match(r"inbound\.([^.]+)\.(sni|listen_port|server_name)$", key)
    if m:
        tag, field = m.group(1), m.group(2)
        for i in cfg.get("inbounds") or []:
            if i.get("tag") == tag:
                if field in ("sni", "server_name"):
                    i.setdefault("tls", {})["server_name"] = val
                else:
                    i["listen_port"] = int(val)
                return
        refuse(f"inbound tag not found: {tag}")
    m = re.match(r"outbound\.([^.]+)\.(server|server_port|sni|server_name)$", key)
    if m:
        tag, field = m.group(1), m.group(2)
        for o in cfg.get("outbounds") or []:
            if o.get("tag") == tag:
                if field == "server":
                    o["server"] = val
                elif field == "server_port":
                    o["server_port"] = int(val)
                else:
                    o.setdefault("tls", {})["server_name"] = val
                return
        refuse(f"outbound tag not found: {tag}")
    refuse(f"unhandled {key}")


def apply_panel(cfg: dict, key: str, val: str) -> None:
    m = re.match(r"nodes\.([^.]+)\.(reality_sni|self_domain|enabled|host)$", key)
    if not m:
        refuse(key)
    nid, field = m.group(1), m.group(2)
    for n in cfg.get("nodes") or []:
        if n.get("id") == nid:
            if field == "enabled":
                n["enabled"] = val.lower() in ("1", "true", "yes")
            else:
                n[field] = val
            return
    refuse(f"node id not found: {nid}")


def apply_drill(text: str, key: str, val: str) -> str:
    lines = text.splitlines()
    out, found = [], False
    for ln in lines:
        if ln.startswith("#") or "=" not in ln:
            out.append(ln)
            continue
        k0 = ln.split("=", 1)[0].strip()
        if k0 == key:
            out.append(f"{key}={val}")
            found = True
        else:
            out.append(ln)
    if not found:
        out.append(f"{key}={val}")
    return "\n".join(out) + "\n"


def validate(validator: str, path: Path) -> None:
    if validator == "singbox":
        if subprocess.call(["sing-box", "check", "-c", str(path)]) != 0:
            refuse("sing-box check failed")
    elif validator == "json-panel":
        json.loads(path.read_text(encoding="utf-8"))
    elif validator == "text":
        if path.stat().st_size <= 0:
            refuse("empty file")
    elif validator == "caddy":
        if shutil.which("caddy"):
            subprocess.call(["caddy", "validate", "--config", str(path)])
    elif validator == "unit":
        subprocess.call(["systemd-analyze", "verify", str(path)])


def main() -> int:
    args = sys.argv[1:]
    if not args:
        refuse("usage: config_patch.py <kind> [--dry-run] [--deadman N] [--digest HEX] set:k=v ...")
    kind = args.pop(0)
    dry = False
    deadman = 0
    expect = ""
    patches: list[tuple[str, str]] = []
    while args:
        a = args.pop(0)
        if a == "--dry-run":
            dry = True
        elif a == "--deadman":
            deadman = int(args.pop(0))
        elif a == "--digest":
            expect = args.pop(0)
        elif a == "--":
            continue
        elif a.startswith("set:") or "=" in a:
            s = a[4:] if a.startswith("set:") else a
            if "=" not in s:
                refuse(f"bad patch {a}")
            k, v = s.split("=", 1)
            patches.append((k.strip(), v.strip()))
        else:
            refuse(f"unknown arg {a}")
    if not patches:
        refuse("need set:field=value")

    meta = run_bash_resolve(kind)
    path = Path(meta.get("PATH") or "")
    if not path.as_posix():
        refuse("kind not patchable")
    validator = meta.get("VALIDATOR") or "text"
    service = meta.get("SERVICE") or ""
    dm_default = int(meta.get("DEADMAN_DEFAULT") or "0")

    dig = digest_of(patches)
    print(f"PATCH_DIGEST={dig}")
    print("patches", " ".join(f"{k}={v}" for k, v in patches))
    if expect and expect != dig:
        print(f"STATUS=FAIL digest mismatch expect={expect} got={dig}")
        return 1
    if not dry and not expect:
        print("STATUS=FAIL real patch requires --digest matching PATCH_DIGEST")
        return 1

    for k, v in patches:
        if kind == "singbox":
            if not SINGBOX_OK.match(k):
                refuse(f"field not allowlisted for singbox: {k}")
        elif kind == "panel-config":
            if not PANEL_OK.match(k):
                refuse(f"field not allowlisted for panel-config: {k}")
        elif kind == "ci-drill":
            if not DRILL_OK.match(k):
                refuse(f"bad drill key {k}")
        else:
            refuse(f"kind {kind} does not support in-place patch")

    print(f"=== config-patch kind={kind} dry={int(dry)} path={path} ===")
    before = path.read_text(encoding="utf-8") if path.exists() else ""
    if kind in ("singbox", "panel-config"):
        cfg = json.loads(before) if before else {}
        for k, v in patches:
            if kind == "singbox":
                apply_singbox(cfg, k, v)
            else:
                apply_panel(cfg, k, v)
        after = json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"
    else:
        after = before
        for k, v in patches:
            after = apply_drill(after, k, v)

    import difflib

    diff = "".join(
        difflib.unified_diff(
            scrub(before).splitlines(True),
            scrub(after).splitlines(True),
            fromfile="live",
            tofile="patched",
            n=2,
        )
    )
    print("----- sanitized diff -----")
    print(diff[:8000] if diff else "(empty)")
    print("DIFF_EMPTY=" + ("1" if not diff.strip() else "0"))

    stage = Path("/tmp/kpax-ci-stage")
    stage.mkdir(mode=0o700, exist_ok=True)
    cpath = stage / kind
    cpath.write_text(after, encoding="utf-8")
    validate(validator, cpath)
    print("validation=OK")

    if dry:
        print("DRY_RUN=1")
        print("STATUS=OK")
        return 0

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%MZ")
    bak_dir = Path("/var/backups/k-pax-ci")
    bak_dir.mkdir(parents=True, exist_ok=True)
    bak = bak_dir / f"config-{kind}-pre-{stamp}"
    if path.exists():
        shutil.copy2(path, bak)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        bak.write_text("# kpax-ci-absent\n", encoding="utf-8")
    print(f"backup={bak}")

    tmp = Path(str(path) + ".kpax-new")
    tmp.write_text(after, encoding="utf-8")
    os.replace(tmp, path)
    print(f"installed {path}")

    if service:
        if validator == "unit":
            subprocess.call(["systemctl", "daemon-reload"])
        subprocess.check_call(["systemctl", "restart", service])
        subprocess.check_call(["systemctl", "is-active", service])
        print(f"restarted={service}")

    # Only auto-arm when --deadman omitted (caller passes 0 explicitly to skip)
    deadman_explicit = any(a == "--deadman" for a in sys.argv[1:])
    if not deadman_explicit and deadman == 0 and dm_default:
        deadman = 5
    if deadman > 0:
        subprocess.check_call(
            [
                "bash",
                str(SCRIPTS / "deadman.sh"),
                "arm",
                stamp,
                str(deadman),
                kind,
            ]
        )
    print(f"APPLY_STAMP={stamp}")
    print("STATUS=OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
