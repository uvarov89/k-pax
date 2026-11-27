#!/usr/bin/env python3
"""Run on the control server: install k-pax-watch on every exit node from /etc/k-pax/config.json."""

from __future__ import annotations

import json
import subprocess
import sys

CONFIG_PATH = "/etc/k-pax/config.json"
FILES = {
    "/usr/local/bin/k-pax-watch.py": "/opt/k-pax/k-pax-watch.py",
    "/etc/systemd/system/k-pax-watch.service": "/opt/k-pax/k-pax-watch.service",
    "/etc/systemd/system/k-pax-watch.timer": "/opt/k-pax/k-pax-watch.timer",
}
TITLES = {"de": "Германия", "fi": "Финляндия", "bg": "Болгария"}


def ssh(cfg: dict, host: str, command: str, stdin: bytes | None = None) -> str:
    result = subprocess.run(
        [
            "ssh",
            "-i",
            cfg["ssh_key"],
            "-o",
            "BatchMode=yes",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            "UserKnownHostsFile=" + cfg["known_hosts"],
            "-o",
            "ConnectTimeout=15",
            "root@" + host,
            command,
        ],
        input=stdin if stdin is not None else b"",
        capture_output=True,
        timeout=90,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or b"failed").decode("utf-8", "replace").strip().splitlines()
        raise RuntimeError(detail[-1][:200] if detail else "failed")
    return result.stdout.decode("utf-8", "replace").strip()


def main() -> None:
    cfg = json.load(open(CONFIG_PATH, encoding="utf-8"))
    send_test = "--test" in sys.argv
    for node in cfg["nodes"]:
        node_id = str(node.get("id") or "")
        name = TITLES.get(node_id, str(node.get("name") or node_id))
        host = node["host"]
        try:
            print(node_id, "python", ssh(cfg, host, "python3 -c 'import sys; print(sys.version.split()[0])'"))
            for remote, local in FILES.items():
                data = open(local, "rb").read().replace(b"\r\n", b"\n")
                ssh(cfg, host, "cat > %s && chmod 644 %s" % (remote, remote), data)
            smtp_out = ssh(
                cfg,
                host,
                "timeout 8 bash -c '</dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null && echo yes || echo no",
            )
            watch_cfg = json.dumps(
                {
                    "token": cfg["telegram_bot_token"],
                    "chat": str(cfg["telegram_chat_id"]),
                    "name": name,
                    "smtp": smtp_out.strip() == "yes",
                },
                ensure_ascii=False,
            ).encode("utf-8")
            print(node_id, "smtp check", "on" if smtp_out.strip() == "yes" else "off (outbound mail ports closed on this node)")
            ssh(cfg, host, "umask 077 && cat > /etc/k-pax-watch.json && chmod 600 /etc/k-pax-watch.json", watch_cfg)
            ssh(
                cfg,
                host,
                "chmod 755 /usr/local/bin/k-pax-watch.py && systemctl daemon-reload "
                "&& systemctl enable --now k-pax-watch.timer >/dev/null 2>&1 && systemctl start k-pax-watch.service",
            )
            state = ssh(cfg, host, "cat /var/lib/k-pax-watch/state.json; echo; systemctl is-active k-pax-watch.timer")
            print(node_id, "state", state.replace("\n", " "))
            if send_test:
                print(node_id, ssh(cfg, host, "python3 /usr/local/bin/k-pax-watch.py test"))
        except Exception as exc:  # noqa: BLE001
            print(node_id, "FAILED", exc)


if __name__ == "__main__":
    main()
