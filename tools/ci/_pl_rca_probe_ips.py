#!/usr/bin/env python3
"""Force SoftProbe to specific front IPs + check if panel PL pbk matches live private."""
from __future__ import annotations

import json
import os
import socket
import subprocess
import tempfile
from pathlib import Path

# load e2e env without printing secrets
env = {}
for line in Path("/etc/k-pax/ci-e2e.env").read_text().splitlines():
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        env[k] = v

uuid = env["E2E_UUID"]
front_pbk = env["E2E_FRONT_PBK"]
front_sid = env["E2E_FRONT_SID"]
front_sni = env["E2E_FRONT_SNI"]
pl_pbk = env["E2E_PL_PBK"]
pl_sid = env["E2E_PL_SID"]
pl_sni = env["E2E_PL_SNI"]
pl_host = env["E2E_PL_HOST"]


def probe(label, server, port, sni, pbk, sid):
    listen = socket.socket()
    listen.bind(("127.0.0.1", 0))
    lport = listen.getsockname()[1]
    listen.close()
    cfg = {
        "log": {"level": "warn"},
        "inbounds": [
            {"type": "mixed", "listen": "127.0.0.1", "listen_port": lport}
        ],
        "outbounds": [
            {
                "type": "vless",
                "tag": "x",
                "server": server,
                "server_port": int(port),
                "uuid": uuid,
                "flow": "xtls-rprx-vision",
                "tls": {
                    "enabled": True,
                    "server_name": sni,
                    "utls": {"enabled": True, "fingerprint": "firefox"},
                    "reality": {
                        "enabled": True,
                        "public_key": pbk,
                        "short_id": sid,
                    },
                },
            }
        ],
    }
    with tempfile.TemporaryDirectory() as td:
        path = Path(td) / "p.json"
        log = Path(td) / "log"
        path.write_text(json.dumps(cfg))
        proc = subprocess.Popen(
            ["sing-box", "run", "-c", str(path)],
            stdout=open(log, "w"),
            stderr=subprocess.STDOUT,
        )
        try:
            import time

            time.sleep(1.2)
            code = subprocess.run(
                [
                    "curl",
                    "-s",
                    "-o",
                    "/dev/null",
                    "-w",
                    "%{http_code}",
                    "-x",
                    "http://127.0.0.1:%s" % lport,
                    "--connect-timeout",
                    "8",
                    "--max-time",
                    "14",
                    "https://www.gstatic.com/generate_204",
                ],
                capture_output=True,
                text=True,
            ).stdout.strip() or "000"
            body = log.read_text(errors="replace")
            reality_fail = "reality verification failed" in body
            print(
                "probe",
                label,
                "HTTP",
                code,
                "reality_fail",
                reality_fail,
            )
        finally:
            proc.kill()
            proc.wait(timeout=5)


print("=== forced-IP SoftProbe ===")
for ip, name in (("195.133.45.167", "ru"), ("152.228.112.142", "ru2")):
    for port, tag in ((2443, "de"), (2444, "fi"), (2445, "pl")):
        probe("%s-%s:%s" % (name, tag, port), ip, port, front_sni, front_pbk, front_sid)

probe("direct-pl", pl_host, 443, pl_sni, pl_pbk, pl_sid)

# Try derive public from private on PL if cryptography/nacl available
print("=== try match panel PL pbk to live private ===")
cfg = json.loads(Path("/etc/k-pax/config.json").read_text())
key = cfg["ssh_key"]
kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"
panel_pl_pbk = pl_pbk
remote = r"""
import json
from pathlib import Path
c=json.loads(Path('/etc/sing-box/config.json').read_text())
sk=None
for i in c.get('inbounds') or []:
    real=((i.get('tls') or {}).get('reality') or {})
    if real.get('private_key') and (i.get('listen_port') or i.get('port'))==443:
        sk=real.get('private_key'); break
print('sk_present', bool(sk))
try:
    from nacl.bindings import crypto_scalarmult_base
    import base64
    # Reality uses X25519; sing-box keys are URL-safe base64 without padding often
    raw=base64.urlsafe_b64decode(sk + '==')
    pub=crypto_scalarmult_base(raw)
    print('derived_pbk', base64.urlsafe_b64encode(pub).decode().rstrip('='))
except Exception as e:
    print('derive_err', type(e).__name__, e)
"""
path = Path("/tmp/_derive_pl.py")
path.write_text(remote)
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
        "root@%s:/tmp/_derive_pl.py" % pl_host,
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
        "root@%s" % pl_host,
        "python3 /tmp/_derive_pl.py",
    ],
    text=True,
    stderr=subprocess.STDOUT,
)
print(out)
if "derived_pbk" in out:
    derived = out.strip().split("derived_pbk", 1)[-1].strip()
    print("panel_matches_derived", derived == panel_pl_pbk)
print("DONE")
