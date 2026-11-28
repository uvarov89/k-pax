#!/usr/bin/env bash
# Create DR backup tarball on panel (full secrets — encrypt only after SCP in Actions).
# Includes DB, panel config, units, Caddyfile, panel *.py, and node sing-box configs.
set -euo pipefail
stamp=$(date -u +%Y%m%dT%H%MZ)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/db" "$work/cfg" "$work/code" "$work/nodes" "$work/meta"

if [[ -f /var/lib/k-pax/k-pax.db ]]; then
  cp -a /var/lib/k-pax/k-pax.db "$work/db/k-pax.db"
  sqlite3 /var/lib/k-pax/k-pax.db ".backup '$work/db/k-pax.backup.db'" 2>/dev/null || true
  sqlite3 "$work/db/k-pax.backup.db" "PRAGMA integrity_check;" >"$work/meta/db_integrity.txt" 2>&1 || true
fi

for f in \
  /etc/k-pax/config.json \
  /etc/systemd/system/k-pax.service \
  /etc/systemd/system/kpax-front-relay.service \
  /etc/caddy/Caddyfile \
  /etc/k-pax/ci-e2e.env
do
  if [[ -f "$f" ]]; then
    cp -a "$f" "$work/cfg/$(basename "$f")"
  fi
done

panel=""
for p in /opt/k-pax/panel.py /usr/local/lib/k-pax/panel.py; do
  [[ -f "$p" ]] && panel="$p" && break
done
if [[ -n "$panel" ]]; then
  dir=$(dirname "$panel")
  for f in "$dir"/*.py; do
    [[ -f "$f" ]] || continue
    cp -a "$f" "$work/code/$(basename "$f")"
  done
fi

export KPAX_BACKUP_NODES="$work/nodes"
python3 - <<'PY' || true
import json, os, subprocess
from pathlib import Path
cfg = json.loads(Path("/etc/k-pax/config.json").read_text(encoding="utf-8"))
key = cfg.get("ssh_key") or ""
kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"
nodes_dir = Path(os.environ["KPAX_BACKUP_NODES"])
nodes_dir.mkdir(parents=True, exist_ok=True)
for n in cfg.get("nodes") or []:
    if n.get("enabled", True) is False:
        continue
    host, nid = n.get("host"), n.get("id")
    if not host or not nid or not key:
        continue
    dest = nodes_dir / f"{nid}.sing-box.json"
    try:
        subprocess.check_call(
            [
                "scp", "-i", key, "-o", "BatchMode=yes", "-o", "ConnectTimeout=12",
                "-o", f"UserKnownHostsFile={kh}",
                f"root@{host}:/etc/sing-box/config.json", str(dest),
            ],
            timeout=60,
        )
        print("node_cfg", nid, "ok")
    except Exception as e:
        print("node_cfg", nid, "FAIL", type(e).__name__)
PY

{
  echo "stamp=$stamp"
  echo "hostname=$(hostname -f 2>/dev/null || hostname)"
  echo "created=$(date -u +%Y-%m-%dT%H:%MZ)"
  echo "files:"
  find "$work" -type f | sed "s|$work/||" | sort
} >"$work/meta/MANIFEST.txt"

out="/tmp/kpax-ci-backup-${stamp}.tar.gz"
tar -C "$work" -czf "$out" .
sha256sum "$out" | tee "/tmp/kpax-ci-backup-${stamp}.sha256"
echo "$out"
echo "STATUS=OK"
