#!/usr/bin/env python3
"""Rotate root admin SSH pubkey on panel + enabled nodes.

Run on panel as root:
  python3 rotate_admin_ssh.py /path/to/new.pub [--remove-old SHA256:...]

Never prints private keys. Does not touch /etc/k-pax/id_ed25519 (panel→node key).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def fingerprint(pub_line: str) -> str:
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(pub_line.strip() + "\n")
        path = f.name
    try:
        out = subprocess.check_output(["ssh-keygen", "-lf", path], text=True).strip()
        # "256 SHA256:xxx comment (ED25519)"
        return out.split()[1]
    finally:
        Path(path).unlink(missing_ok=True)


def ensure_key(auth_path: Path, pub: str) -> None:
    auth_path.parent.mkdir(mode=0o700, exist_ok=True)
    existing = auth_path.read_text() if auth_path.exists() else ""
    if pub.strip() not in existing:
        with auth_path.open("a", encoding="utf-8") as f:
            f.write(pub.strip() + "\n")
    auth_path.chmod(0o600)


def remove_fp(auth_path: Path, fp: str) -> int:
    if not auth_path.exists():
        return 0
    kept = []
    removed = 0
    for line in auth_path.read_text().splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            kept.append(line)
            continue
        try:
            if fingerprint(s) == fp:
                removed += 1
                continue
        except Exception:
            kept.append(line)
            continue
        kept.append(line)
    auth_path.write_text("\n".join(kept) + ("\n" if kept else ""), encoding="utf-8")
    auth_path.chmod(0o600)
    return removed


def ssh_root(admin_key: str, kh: str, host: str, script: str) -> str:
    return subprocess.check_output(
        [
            "ssh",
            "-i",
            admin_key,
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=15",
            "-o",
            f"UserKnownHostsFile={kh}",
            f"root@{host}",
            "bash -s",
        ],
        input=script,
        text=True,
        stderr=subprocess.STDOUT,
        timeout=90,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pubkey")
    ap.add_argument("--remove-old", default="", help="SHA256:... fingerprint to remove after install")
    ap.add_argument("--install-only", action="store_true")
    args = ap.parse_args()

    pub = Path(args.pubkey).read_text(encoding="utf-8").strip()
    if not pub.startswith("ssh-") or "PRIVATE" in pub:
        print("need a single OpenSSH public key", file=sys.stderr)
        return 2
    new_fp = fingerprint(pub)
    print("new_fp", new_fp)

    cfg = json.load(open("/etc/k-pax/config.json", encoding="utf-8"))
    admin_key = cfg["ssh_key"]
    kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"

    # panel local
    ensure_key(Path("/root/.ssh/authorized_keys"), pub)
    print("panel: installed", new_fp)

    remote = f"""
set -euo pipefail
mkdir -p /root/.ssh
chmod 700 /root/.ssh
AUTH=/root/.ssh/authorized_keys
touch "$AUTH"
PUB={pub!r}
grep -qxF "$PUB" "$AUTH" 2>/dev/null || echo "$PUB" >> "$AUTH"
chmod 600 "$AUTH"
echo OK $(hostname)
"""
    for n in cfg.get("nodes") or []:
        if n.get("enabled", True) is False:
            print("skip", n.get("id"))
            continue
        host = n["host"]
        print("===", n.get("id"), host)
        try:
            print(ssh_root(admin_key, kh, host, remote).strip())
        except Exception as e:
            print("FAIL", n.get("id"), e)

    if args.remove_old and not args.install_only:
        fp = args.remove_old
        n = remove_fp(Path("/root/.ssh/authorized_keys"), fp)
        print("panel removed", fp, "count", n)
        rem = f"""
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import subprocess, tempfile, os
fp = {fp!r}
auth = Path('/root/.ssh/authorized_keys')
if not auth.exists():
    print('noauth'); raise SystemExit
kept=[]
removed=0
for line in auth.read_text().splitlines():
    s=line.strip()
    if not s or s.startswith('#'):
        kept.append(line); continue
    with tempfile.NamedTemporaryFile('w', delete=False) as f:
        f.write(s+'\\n'); p=f.name
    try:
        out=subprocess.check_output(['ssh-keygen','-lf',p], text=True).split()[1]
    finally:
        os.unlink(p)
    if out == fp:
        removed += 1
        continue
    kept.append(line)
auth.write_text('\\n'.join(kept)+('\\n' if kept else ''))
auth.chmod(0o600)
print('removed', removed)
PY
"""
        for n in cfg.get("nodes") or []:
            if n.get("enabled", True) is False:
                continue
            host = n["host"]
            try:
                print(n.get("id"), ssh_root(admin_key, kh, host, rem).strip())
            except Exception as e:
                print("FAIL remove", n.get("id"), e)

    print("DONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
