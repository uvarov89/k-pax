#!/usr/bin/env python3
import json
import socket

cfg = json.load(open("/etc/k-pax/config.json"))
keys = [k for k in cfg if "front" in k.lower() or k in ("exits", "exit_nodes", "nodes")]
print("keys", keys)
fronts = cfg.get("front_nodes") or cfg.get("fronts") or []
if not fronts and isinstance(cfg.get("nodes"), list):
    fronts = [
        n
        for n in cfg["nodes"]
        if n.get("front_ports") or str(n.get("role", "")).startswith("front")
    ]
print("front_count", len(fronts))
for f in fronts:
    host = str(f.get("self_domain") or f.get("host") or "?")
    ports = f.get("front_ports") or {}
    print("FRONT_HOST", host)
    print("FRONT_PORTS", {str(k): int(v) for k, v in ports.items()} if isinstance(ports, dict) else ports)
    if not isinstance(ports, dict):
        continue
    for label, p in ports.items():
        s = socket.socket()
        s.settimeout(3)
        try:
            code = s.connect_ex((host, int(p)))
            print("TCP", host, label, p, "OK" if code == 0 else code)
        except Exception as e:
            print("TCP", host, label, p, type(e).__name__)
        finally:
            s.close()
