#!/usr/bin/env python3
"""Dump non-secret sing-box shapes + key fingerprints from fleet."""
from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

cfg = json.loads(Path("/etc/k-pax/config.json").read_text())
key = cfg["ssh_key"]
kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"
by = {n["id"]: n for n in (cfg.get("nodes") or [])}

remote_py = """
import json, hashlib
from pathlib import Path
c=json.loads(Path('/etc/sing-box/config.json').read_text())
print('inbounds')
for i in c.get('inbounds') or []:
    tls=i.get('tls') or {}
    real=tls.get('reality') or {}
    sk=str(real.get('private_key') or '')
    print('inbound', i.get('type'), i.get('listen_port') or i.get('port'),
          'users', len(i.get('users') or []),
          'sni', tls.get('server_name'),
          'sid', real.get('short_id'),
          'sk_sha12', hashlib.sha256(sk.encode()).hexdigest()[:12] if sk else 'none')
print('outbounds')
for o in c.get('outbounds') or []:
    tag=str(o.get('tag') or '')
    if o.get('type')!='vless' and not tag.startswith('to-'):
        continue
    tls=o.get('tls') or {}
    real=tls.get('reality') or {}
    pbk=str(real.get('public_key') or '')
    print('outbound', tag, o.get('server'), o.get('server_port'),
          'sni', tls.get('server_name'),
          'sid', real.get('short_id'),
          'pbk_sha12', hashlib.sha256(pbk.encode()).hexdigest()[:12] if pbk else 'none')
"""

path = Path("/tmp/_shape_remote.py")
path.write_text(remote_py, encoding="utf-8")

for nid in ("de", "fi", "pl", "ru", "ru2"):
    n = by.get(nid) or {}
    host = n.get("host")
    if not host:
        continue
    print("##", nid, host)
    try:
        subprocess.check_call(
            [
                "scp",
                "-i",
                key,
                "-o",
                "BatchMode=yes",
                "-o",
                "UserKnownHostsFile=%s" % kh,
                str(path),
                "root@%s:/tmp/_shape_remote.py" % host,
            ]
        )
        out = subprocess.check_output(
            [
                "ssh",
                "-i",
                key,
                "-o",
                "BatchMode=yes",
                "-o",
                "UserKnownHostsFile=%s" % kh,
                "root@%s" % host,
                "python3 /tmp/_shape_remote.py",
            ],
            text=True,
            stderr=subprocess.STDOUT,
            timeout=45,
        )
        print(out)
    except subprocess.CalledProcessError as e:
        print("ERR", (e.output or str(e))[-400:])

print("panel_pbk_sha12")
for nid in ("de", "fi", "pl", "ru"):
    pbk = (by.get(nid) or {}).get("pbk") or ""
    print(
        nid,
        hashlib.sha256(pbk.encode()).hexdigest()[:12] if pbk else "missing",
        "sid",
        (by.get(nid) or {}).get("sid"),
    )

# DNS dual-A note
import socket

print("media_A", socket.getaddrinfo("media.nastolkashop.store", 443, type=socket.SOCK_STREAM))
print("DONE")
