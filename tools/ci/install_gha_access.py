#!/usr/bin/env python3
"""Install limited `gha` CI user + deploy pubkey + fixed kpax-ci wrappers.

Run on the panel host as root (from a checkout that includes tools/ci/wrappers):
  python3 tools/ci/install_gha_access.py /path/to/gha.pub
Or pipe the pubkey:
  cat gha.pub | python3 tools/ci/install_gha_access.py

Sudoers allow ONLY /usr/local/lib/kpax-ci/kpax-ci — no arbitrary python/shell.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
WRAP_SRC = HERE / "wrappers"
DEST = Path("/usr/local/lib/kpax-ci")

if len(sys.argv) > 1:
    PUBKEY = Path(sys.argv[1]).read_text(encoding="utf-8").strip()
else:
    PUBKEY = sys.stdin.read().strip()
if not PUBKEY.startswith("ssh-") or "PRIVATE" in PUBKEY:
    raise SystemExit("need a single OpenSSH public key")

cfg = json.load(open("/etc/k-pax/config.json", encoding="utf-8"))
admin_key = cfg["ssh_key"]
kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"

# ONLY the fixed entrypoint — never /usr/bin/python3 or generic cp/rm.
SUDOERS = """# K-Pax GitHub Actions — fixed wrappers only (do not widen)
gha ALL=(root) NOPASSWD: /usr/local/lib/kpax-ci/kpax-ci
"""

Path("/tmp/gha.pub").write_text(PUBKEY + "\n", encoding="utf-8")
Path("/tmp/gha.sudoers").write_text(SUDOERS, encoding="utf-8")


def install_wrappers_local() -> None:
    if not (WRAP_SRC / "kpax-ci").is_file():
        raise SystemExit(f"missing wrappers at {WRAP_SRC}")
    DEST.mkdir(parents=True, exist_ok=True)
    # Clear old scripts then copy tree
    for child in DEST.iterdir():
        if child.name == "kpax-ci" or child.name == "scripts":
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()
    shutil.copy2(WRAP_SRC / "kpax-ci", DEST / "kpax-ci")
    (DEST / "kpax-ci").chmod(0o755)
    scripts_dest = DEST / "scripts"
    scripts_dest.mkdir(parents=True, exist_ok=True)
    for src in (WRAP_SRC / "scripts").iterdir():
        if src.is_file():
            shutil.copy2(src, scripts_dest / src.name)
            if src.suffix in (".sh", "") or src.name == "kpax-ci":
                (scripts_dest / src.name).chmod(0o755)
            else:
                (scripts_dest / src.name).chmod(0o644)
    # Ensure shell scripts executable
    for sh in scripts_dest.glob("*.sh"):
        sh.chmod(0o755)
    (DEST / "kpax-ci").chmod(0o755)
    print("wrappers installed", DEST)


BOOTSTRAP = r"""
set -euo pipefail
id gha >/dev/null 2>&1 || useradd --create-home --shell /bin/bash gha
install -d -m 700 -o gha -g gha /home/gha/.ssh
AUTH=/home/gha/.ssh/authorized_keys
touch "$AUTH"
PUB=$(cat /tmp/gha.pub | head -1)
grep -qxF "$PUB" "$AUTH" 2>/dev/null || echo "$PUB" >> "$AUTH"
grep -v PRIVATE "$AUTH" > "$AUTH.tmp" && mv "$AUTH.tmp" "$AUTH"
chown gha:gha "$AUTH"
chmod 600 "$AUTH"
install -m 440 /tmp/gha.sudoers /etc/sudoers.d/kpax-gha
visudo -cf /etc/sudoers.d/kpax-gha
# Wrappers are rsynced separately for remote nodes
echo OK $(hostname) $(id -u gha)
"""


def run_local() -> None:
    install_wrappers_local()
    print(subprocess.check_output(["bash", "-lc", BOOTSTRAP], text=True))


def ssh(host: str, script: str) -> str:
    return subprocess.check_output(
        [
            "ssh",
            "-i",
            admin_key,
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=12",
            "-o",
            f"UserKnownHostsFile={kh}",
            f"root@{host}",
            "bash -s",
        ],
        input=script,
        text=True,
        stderr=subprocess.STDOUT,
        timeout=120,
    )


print("=== panel ===")
run_local()

for n in cfg.get("nodes") or []:
    nid = n.get("id")
    if n.get("enabled", True) is False:
        print("skip", nid)
        continue
    host = n["host"]
    print("===", nid, host)
    try:
        subprocess.check_call(
            [
                "scp",
                "-i",
                admin_key,
                "-o",
                "BatchMode=yes",
                "-o",
                f"UserKnownHostsFile={kh}",
                "/tmp/gha.pub",
                "/tmp/gha.sudoers",
                f"root@{host}:/tmp/",
            ]
        )
        # Sync wrappers
        subprocess.check_call(
            [
                "rsync",
                "-az",
                "-e",
                f"ssh -i {admin_key} -o BatchMode=yes -o UserKnownHostsFile={kh}",
                str(DEST) + "/",
                f"root@{host}:{DEST}/",
            ]
        )
        print(ssh(host, BOOTSTRAP))
        ssh(
            host,
            f"chmod 755 {DEST}/kpax-ci; chmod 755 {DEST}/scripts/*.sh 2>/dev/null || true; "
            f"chown -R root:root {DEST}",
        )
    except Exception as e:
        print("FAIL", nid, e)

print("DONE")
