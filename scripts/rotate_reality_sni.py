#!/usr/bin/env python3
"""Rotate primary Reality SNI/dest on a sing-box node. Self-steal inbound is left alone."""
from __future__ import annotations

import json
import sys
from pathlib import Path

CONFIG = Path("/etc/sing-box/config.json")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: rotate_reality_sni.py <hostname>", file=sys.stderr)
        return 2
    host = sys.argv[1].strip().lower()
    if not host or "." not in host:
        print("bad hostname", file=sys.stderr)
        return 2
    raw = CONFIG.read_text(encoding="utf-8")
    cfg = json.loads(raw)
    changed = 0
    for inbound in cfg.get("inbounds") or []:
        if inbound.get("tag") != "vless-reality":
            continue
        tls = inbound.setdefault("tls", {})
        reality = tls.setdefault("reality", {})
        tls["server_name"] = host
        reality["handshake"] = {"server": host, "server_port": 443}
        changed += 1
    if not changed:
        print("no vless-reality inbound", file=sys.stderr)
        return 1
    backup = CONFIG.with_suffix(CONFIG.suffix + ".bak-sni")
    backup.write_text(raw, encoding="utf-8")
    CONFIG.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("updated", changed, "inbound(s) ->", host)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
