#!/usr/bin/env python3
"""Deep read-only node diagnose for ChatGPT phone ops.

Usage (via kpax-ci): diagnose [node_id[,node_id...]]

Prints fingerprints only (sha12 of keys), hop TCP results, CI-E2E presence,
and SoftProbe path status when ci-e2e.env is available. Never prints UUID/keys.
Exit 1 if any hard check fails for a required path (e.g. pl SoftProbe).
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path


def shutil_rmtree(path: Path) -> None:
    try:
        shutil.rmtree(path, ignore_errors=True)
    except Exception:
        pass

UUID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I
)


def sha12(s: str) -> str:
    if not s:
        return "missing"
    return hashlib.sha256(s.encode()).hexdigest()[:12]


def redact(s: str) -> str:
    s = UUID_RE.sub("<uuid>", s)
    s = re.sub(r'"public_key"\s*:\s*"[^"]+"', '"public_key":"<pbk>"', s)
    s = re.sub(r'"short_id"\s*:\s*("[^"]+"|\[[^\]]+\])', '"short_id":"<sid>"', s)
    s = re.sub(r'"private_key"\s*:\s*"[^"]+"', '"private_key":"<sk>"', s)
    s = re.sub(r'"password"\s*:\s*"[^"]+"', '"password":"<redacted>"', s)
    return s


def tcp(host: str, port: int, timeout: float = 4.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def ssh(key: str, kh: str, host: str, remote: str, timeout: int = 60) -> str:
    return subprocess.check_output(
        [
            "ssh",
            "-i",
            key,
            "-o",
            "BatchMode=yes",
            "-o",
            f"UserKnownHostsFile={kh}",
            "-o",
            "ConnectTimeout=12",
            f"root@{host}",
            remote,
        ],
        text=True,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


def ssh_py(key: str, kh: str, host: str, code: str, timeout: int = 60) -> str:
    """Run Python on remote via stdin (avoids shell-quoting breakage)."""
    return subprocess.check_output(
        [
            "ssh",
            "-i",
            key,
            "-o",
            "BatchMode=yes",
            "-o",
            f"UserKnownHostsFile={kh}",
            "-o",
            "ConnectTimeout=12",
            f"root@{host}",
            "python3",
            "-",
        ],
        input=code,
        text=True,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


REMOTE_SHAPE = r"""
import json, hashlib
from pathlib import Path
c=json.loads(Path('/etc/sing-box/config.json').read_text())
print('INBOUND_BEGIN')
for i in c.get('inbounds') or []:
    tls=i.get('tls') or {}
    real=tls.get('reality') or {}
    sk=str(real.get('private_key') or '')
    sid=real.get('short_id')
    if isinstance(sid, list):
        sid=','.join(str(x) for x in sid)
    print(i.get('tag') or i.get('type'), i.get('type'),
          i.get('listen_port') or i.get('port'),
          tls.get('server_name') or '',
          sid or '',
          hashlib.sha256(sk.encode()).hexdigest()[:12] if sk else 'none',
          len(i.get('users') or []),
          'reality' if (real.get('enabled')) else 'noreality')
print('INBOUND_END')
print('OUTBOUND_BEGIN')
for o in c.get('outbounds') or []:
    if o.get('type') not in ('vless','trojan','hysteria2') and not str(o.get('tag','')).startswith('to-'):
        continue
    tls=o.get('tls') or {}
    real=tls.get('reality') or {}
    pbk=str(real.get('public_key') or '')
    sid=real.get('short_id')
    if isinstance(sid, list):
        sid=','.join(str(x) for x in sid)
    print(o.get('tag'), o.get('type'), o.get('server'), o.get('server_port'),
          tls.get('server_name') or '', sid or '',
          hashlib.sha256(pbk.encode()).hexdigest()[:12] if pbk else 'none')
print('OUTBOUND_END')
"""


def remote_cie2e_present(key: str, kh: str, host: str, uuid_hash: str) -> str:
    code = (
        "import json,hashlib\n"
        "from pathlib import Path\n"
        f"h={uuid_hash!r}\n"
        "c=json.loads(Path('/etc/sing-box/config.json').read_text())\n"
        "found=False\n"
        "for i in c.get('inbounds') or []:\n"
        "  for u in i.get('users') or []:\n"
        "    uid=str(u.get('uuid') or u.get('name') or '')\n"
        "    if uid and hashlib.sha256(uid.encode()).hexdigest()==h:\n"
        "      found=True\n"
        "print('ci_e2e_present', 'yes' if found else 'no')\n"
    )
    try:
        out = ssh_py(key, kh, host, code)
        return "yes" if "ci_e2e_present yes" in out else "no"
    except Exception as e:
        return f"error:{type(e).__name__}"


def parse_shape(text: str) -> dict:
    ins, outs = [], []
    mode = None
    for line in text.splitlines():
        if line.strip() == "INBOUND_BEGIN":
            mode = "in"
            continue
        if line.strip() == "INBOUND_END":
            mode = None
            continue
        if line.strip() == "OUTBOUND_BEGIN":
            mode = "out"
            continue
        if line.strip() == "OUTBOUND_END":
            mode = None
            continue
        parts = line.split()
        if mode == "in" and len(parts) >= 8:
            ins.append(
                {
                    "tag": parts[0],
                    "type": parts[1],
                    "port": parts[2],
                    "sni": parts[3],
                    "sid": parts[4],
                    "sk_sha12": parts[5],
                    "users": parts[6],
                    "reality": parts[7],
                }
            )
        elif mode == "out" and len(parts) >= 7:
            outs.append(
                {
                    "tag": parts[0],
                    "type": parts[1],
                    "server": parts[2],
                    "port": parts[3],
                    "sni": parts[4],
                    "sid": parts[5],
                    "pbk_sha12": parts[6],
                }
            )
    return {"inbounds": ins, "outbounds": outs}


def softprobe_one(
    label: str,
    server: str,
    port: int,
    sni: str,
    pbk: str,
    sid: str,
    uuid: str,
    expect_ip: str = "",
) -> tuple[str, str]:
    """Returns (status, detail). status in OK|FAIL_TCP|FAIL_SOFTPROBE|SKIP."""
    if not all([server, sni, pbk, sid, uuid]):
        return "SKIP", "missing params"
    if not tcp(server, port):
        return "FAIL_TCP", f"{server}:{port}"
    work = Path(f"/tmp/kpax-diag-{os.getpid()}-{label.replace(':','_')}")
    work.mkdir(parents=True, exist_ok=True)
    listen_sock = socket.socket()
    listen_sock.bind(("127.0.0.1", 0))
    listen = listen_sock.getsockname()[1]
    listen_sock.close()
    cfg = {
        "log": {"level": "info", "timestamp": True},
        "inbounds": [
            {"type": "mixed", "listen": "127.0.0.1", "listen_port": listen}
        ],
        "outbounds": [
            {
                "type": "vless",
                "tag": "x",
                "server": server,
                "server_port": port,
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
    cfg_path = work / "p.json"
    cfg_path.write_text(json.dumps(cfg), encoding="utf-8")
    log_path = work / "log"
    code, ip_got = "000", ""
    try:
        for _ in range(2):
            proc = subprocess.Popen(
                ["sing-box", "run", "-c", str(cfg_path)],
                stdout=log_path.open("w"),
                stderr=subprocess.STDOUT,
            )
            time.sleep(1.4)
            try:
                code = subprocess.check_output(
                    [
                        "curl",
                        "-s",
                        "-o",
                        "/dev/null",
                        "-w",
                        "%{http_code}",
                        "-x",
                        f"http://127.0.0.1:{listen}",
                        "--connect-timeout",
                        "8",
                        "--max-time",
                        "14",
                        "https://www.gstatic.com/generate_204",
                    ],
                    text=True,
                ).strip()
            except Exception:
                code = "000"
            try:
                trace = subprocess.check_output(
                    [
                        "curl",
                        "-s",
                        "-x",
                        f"http://127.0.0.1:{listen}",
                        "--connect-timeout",
                        "8",
                        "--max-time",
                        "14",
                        "https://www.cloudflare.com/cdn-cgi/trace",
                    ],
                    text=True,
                )
                for line in trace.splitlines():
                    if line.startswith("ip="):
                        ip_got = line.split("=", 1)[1]
            except Exception:
                pass
            proc.kill()
            try:
                proc.wait(timeout=3)
            except Exception:
                pass
            if code in ("200", "204"):
                if expect_ip and ip_got and ip_got != expect_ip:
                    detail = f"HTTP {code} egress={ip_got} expect={expect_ip}"
                    # retry
                    continue
                # dump nothing sensitive
                shutil_rmtree(work)
                return "OK", f"HTTP {code} egress={ip_got or 'n/a'}"
        # failure: print redacted sing-box log inline
        log_txt = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
        print(f"--- softprobe fail log {label} ---")
        print(redact(log_txt[-2500:]))
        shutil_rmtree(work)
        return "FAIL_SOFTPROBE", f"HTTP {code} egress={ip_got or 'n/a'}"
    except Exception as e:
        return "FAIL_SOFTPROBE", type(e).__name__


def local_node_diag() -> int:
    print(f"=== local diagnose host={socket.gethostname()} ===")
    fail = 0
    if Path("/etc/sing-box/config.json").exists():
        shape = parse_shape(
            subprocess.check_output(
                ["python3", "-c", REMOTE_SHAPE], text=True, stderr=subprocess.STDOUT
            )
        )
        for i in shape["inbounds"]:
            print(
                "inbound",
                i["tag"],
                "port",
                i["port"],
                "sni",
                i["sni"],
                "sid",
                i["sid"],
                "sk_sha12",
                i["sk_sha12"],
                "users",
                i["users"],
                i["reality"],
            )
        for o in shape["outbounds"]:
            print(
                "outbound",
                o["tag"],
                o["server"],
                o["port"],
                "sni",
                o["sni"],
                "sid",
                o["sid"],
                "pbk_sha12",
                o["pbk_sha12"],
            )
        rc = subprocess.call(
            ["sing-box", "check", "-c", "/etc/sing-box/config.json"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        print("sing-box_check", "OK" if rc == 0 else "FAIL")
        if rc != 0:
            fail = 1
    else:
        print("sing-box config missing")
    # journals
    for unit in ("sing-box", "kpax-front-relay", "caddy", "k-pax"):
        try:
            out = subprocess.check_output(
                ["journalctl", "-u", unit, "-n", "40", "--no-pager"],
                text=True,
                stderr=subprocess.DEVNULL,
            )
            print(f"--- journal {unit} (redacted) ---")
            print(redact(out)[-3000:])
        except Exception:
            pass
    print("STATUS=" + ("FAIL" if fail else "OK"))
    return fail


def panel_diagnose(targets: list[str]) -> int:
    cfg = json.loads(Path("/etc/k-pax/config.json").read_text(encoding="utf-8"))
    key = cfg["ssh_key"]
    kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"
    by = {n["id"]: n for n in (cfg.get("nodes") or [])}
    fail = 0

    # CI-E2E
    import sqlite3

    conn = sqlite3.connect("/var/lib/k-pax/k-pax.db")
    row = conn.execute(
        "SELECT uuid FROM users WHERE public_id='CI-E2E'"
    ).fetchone()
    if not row:
        print("CI_E2E=missing STATUS=FAIL")
        print("STATUS=FAIL")
        return 1
    uuid = row[0]
    uuid_hash = hashlib.sha256(uuid.encode()).hexdigest()
    print("CI_E2E=present uuid_sha12=" + sha12(uuid))

    env_path = Path("/etc/k-pax/ci-e2e.env")
    env: dict[str, str] = {}
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"')
        print("ci_e2e_env=present")
    else:
        print("ci_e2e_env=missing")

    front = by.get("ru") or by.get("ru2") or {}
    front_host = env.get("E2E_FRONT_HOST") or front.get("host") or ""
    front_sni = env.get("E2E_FRONT_SNI") or front.get("reality_sni") or front.get("self_domain") or ""
    front_pbk = env.get("E2E_FRONT_PBK") or front.get("pbk") or ""
    front_sid = env.get("E2E_FRONT_SID") or front.get("sid") or ""

    port_map = {"de": 2443, "fi": 2444, "pl": 2445}

    for nid in targets:
        print(f"\n======== diagnose node={nid} ========")
        n = by.get(nid)
        if not n:
            print("STATUS=FAIL unknown node", nid)
            fail = 1
            continue
        host = n.get("host") or ""
        panel_pbk = n.get("pbk") or ""
        panel_sid = str(n.get("sid") or "")
        panel_sni = n.get("reality_sni") or n.get("self_domain") or ""
        print(
            "panel_meta",
            "host",
            host,
            "sni",
            panel_sni,
            "sid",
            panel_sid,
            "pbk_sha12",
            sha12(panel_pbk),
            "enabled",
            n.get("enabled", True),
        )

        # Live shape on exit
        try:
            shape_txt = ssh_py(key, kh, host, REMOTE_SHAPE)
            shape = parse_shape(shape_txt)
            print("live_exit_shape_ok")
            for i in shape["inbounds"]:
                print(
                    "  in",
                    i["tag"],
                    "port",
                    i["port"],
                    "sni",
                    i["sni"],
                    "sid",
                    i["sid"],
                    "sk_sha12",
                    i["sk_sha12"],
                    "users",
                    i["users"],
                )
                if i.get("reality") == "reality" and panel_sni and i["sni"] and i["sni"] != panel_sni:
                    # self-domain inbound may differ; flag primary 443 vision
                    if str(i["port"]) == "443" and "reality" in i["tag"]:
                        print("  WARN sni_mismatch panel=%s live=%s" % (panel_sni, i["sni"]))
                if panel_sid and i["sid"] and panel_sid not in i["sid"]:
                    if str(i["port"]) == "443" and i.get("reality") == "reality":
                        print("  WARN sid_mismatch panel=%s live=%s" % (panel_sid, i["sid"]))
                        fail = 1
        except Exception as e:
            print("live_exit_shape FAIL", type(e).__name__)
            fail = 1
            shape = {"inbounds": [], "outbounds": []}

        present = remote_cie2e_present(key, kh, host, uuid_hash)
        print("ci_e2e_on_node", present)
        if present != "yes":
            print("WARN CI-E2E UUID not on node — sync-users needed")
            fail = 1

        # DNS on exit (PL SoftProbe HTTP_000: sing-box dns-local → 127.0.0.1:53 refused)
        try:
            dns_remote = r"""
import json, subprocess, re
from pathlib import Path
c=json.loads(Path('/etc/sing-box/config.json').read_text())
dns=c.get('dns') or {}
servers=[]
for s in dns.get('servers') or []:
    if isinstance(s,str): servers.append(('?', s))
    elif isinstance(s,dict): servers.append((s.get('tag') or '?', s.get('address') or s.get('server') or '?'))
print('singbox_dns_servers', ', '.join('%s=%s'%x for x in servers) or '(none)')
print('singbox_dns_final', dns.get('final'))
ss=subprocess.check_output(['ss','-ulnp'], text=True, stderr=subprocess.DEVNULL)
listen_local = any(('127.0.0.1' in ln and ':53' in ln) for ln in ss.splitlines())
listen_stub = any(('127.0.0.53' in ln and ':53' in ln) for ln in ss.splitlines())
print('listen_127_0_0_1_53', 'yes' if listen_local else 'no')
print('listen_127_0_0_53_53', 'yes' if listen_stub else 'no')
for ln in ss.splitlines():
    if ':53' in ln: print('LISTEN53', ln[:160])
# resolve probes
def dig(server):
    try:
        out=subprocess.check_output(['dig','+time=2','+tries=1','+short','@'+server,'www.gstatic.com','A'], text=True, stderr=subprocess.STDOUT, timeout=5)
        ok=bool(re.search(r'\d+\.\d+\.\d+\.\d+', out or ''))
        print('RESOLVE', server, 'OK' if ok else 'FAIL', (out or '').strip().splitlines()[:2])
        return ok
    except Exception as e:
        print('RESOLVE', server, 'FAIL', type(e).__name__); return False
r1=dig('127.0.0.1'); r53=dig('127.0.0.53'); rpub=dig('1.1.1.1')
points_local = any(a=='127.0.0.1' or str(a).startswith('127.0.0.1:') for _,a in servers)
if points_local and not listen_local:
    print('FAIL root_cause=singbox_dns-local_to_127.0.0.1_but_no_listener (DE/FI have unbound; PL only systemd-resolved stub)')
    print('HINT patch set:dns.server.dns-local.address=1.1.1.1  OR  address=127.0.0.53')
if not rpub:
    print('FAIL public_dns_1.1.1.1_unreachable_from_exit')
"""
            dns_out = ssh_py(key, kh, host, dns_remote)
            print("--- exit DNS ---")
            print(redact(dns_out)[:3500])
            if "FAIL root_cause=" in dns_out or "FAIL public_dns" in dns_out:
                fail = 1
            if "RESOLVE 127.0.0.1 FAIL" in dns_out and "singbox_dns_servers" in dns_out and "127.0.0.1" in dns_out:
                fail = 1
        except Exception as e:
            print("exit_dns_check FAIL", type(e).__name__)
            fail = 1

        # Front outbound toward this exit (ru)
        for fid in ("ru", "ru2"):
            fn = by.get(fid)
            if not fn or not fn.get("host"):
                continue
            try:
                fshape = parse_shape(ssh_py(key, kh, fn["host"], REMOTE_SHAPE))
                tag = f"to-{nid}"
                matches = [o for o in fshape["outbounds"] if o["tag"] == tag or o["tag"].endswith(nid)]
                print(f"front_{fid}_outbounds_for_{nid}", len(matches))
                for o in matches:
                    print(
                        " ",
                        o["tag"],
                        "server",
                        o["server"],
                        o["port"],
                        "sni",
                        o["sni"],
                        "sid",
                        o["sid"],
                        "pbk_sha12",
                        o["pbk_sha12"],
                    )
                    if panel_pbk and o["pbk_sha12"] != sha12(panel_pbk):
                        print("  FAIL pbk_mismatch front_outbound vs panel meta")
                        fail = 1
                    else:
                        print("  pbk_match_panel OK")
                    if panel_sid and o["sid"] and panel_sid not in o["sid"]:
                        print("  FAIL sid_mismatch front_outbound vs panel")
                        fail = 1
                    if host and o["server"] and o["server"] != host:
                        print("  WARN server_ip", o["server"], "vs panel_host", host)
            except Exception as e:
                print(f"front_{fid}_shape FAIL", type(e).__name__)

        # Network hops
        fport = port_map.get(nid)
        print("--- hops ---")
        if front_host and fport:
            hop1 = tcp(front_host, fport)
            print(f"hop panel->front:{fport}", "OPEN" if hop1 else "CLOSED", front_host)
            if not hop1:
                fail = 1
        if host:
            hop2 = tcp(host, 443)
            print("hop panel->exit:443", "OPEN" if hop2 else "CLOSED", host)
            if not hop2:
                fail = 1
        # panel relay ports
        for rp in (28443, 28444, 28445):
            print(f"hop panel_local_relay:{rp}", "OPEN" if tcp("127.0.0.1", rp) else "CLOSED_or_remote")

        # SoftProbe paths
        print("--- softprobe ---")
        if env.get("E2E_UUID") or uuid:
            u = env.get("E2E_UUID") or uuid
            expect = env.get(f"E2E_EXPECT_{nid.upper()}_IP", "")
            if front_host and fport and front_pbk and front_sid:
                st, detail = softprobe_one(
                    f"front-{nid}",
                    front_host,
                    fport,
                    front_sni,
                    front_pbk,
                    front_sid,
                    u,
                    expect,
                )
                print(f"softprobe front-{nid}:{fport}", st, detail)
                if st not in ("OK", "SKIP") and nid == "pl":
                    fail = 1
            # direct
            pbk = env.get(f"E2E_{nid.upper()}_PBK") or panel_pbk
            sid = env.get(f"E2E_{nid.upper()}_SID") or panel_sid
            sni = env.get(f"E2E_{nid.upper()}_SNI") or panel_sni
            st, detail = softprobe_one(
                f"direct-{nid}", host, 443, sni, pbk, sid, u, expect
            )
            print(f"softprobe direct-{nid}:443", st, detail)
            if st not in ("OK", "SKIP") and nid == "pl":
                fail = 1
        else:
            print("softprobe SKIP no uuid")

        # Journals from exit + recent e2e fail logs on panel
        try:
            j = ssh(
                key,
                kh,
                host,
                "journalctl -u sing-box -n 50 --no-pager 2>/dev/null || true",
            )
            print("--- exit sing-box journal (redacted) ---")
            print(redact(j)[-3500:])
        except Exception as e:
            print("journal FAIL", type(e).__name__)

        log_dir = Path("/var/log/k-pax-ci/e2e")
        if log_dir.is_dir():
            fails = sorted(log_dir.glob(f"fail-*{nid}*"), key=lambda p: p.stat().st_mtime)
            fails += sorted(log_dir.glob("fail-front-pl*"), key=lambda p: p.stat().st_mtime)
            fails += sorted(log_dir.glob("fail-direct-pl*"), key=lambda p: p.stat().st_mtime)
            seen = set()
            for p in fails[-4:]:
                if p in seen:
                    continue
                seen.add(p)
                print(f"--- e2e fail log {p.name} ---")
                print(redact(p.read_text(encoding="utf-8", errors="replace")[-3000:]))

    print("\nSTATUS=" + ("FAIL" if fail else "OK"))
    return fail


def main() -> int:
    args = [a for a in sys.argv[1:] if a]
    is_panel = Path("/etc/k-pax/config.json").exists() and Path(
        "/var/lib/k-pax/k-pax.db"
    ).exists()
    if not args:
        if is_panel:
            args = ["pl"]
        else:
            return local_node_diag()
    targets = []
    for a in args:
        targets.extend([x.strip() for x in a.split(",") if x.strip()])
    if is_panel:
        return panel_diagnose(targets)
    # On a node: local only (ignore foreign ids)
    return local_node_diag()


if __name__ == "__main__":
    raise SystemExit(main())
