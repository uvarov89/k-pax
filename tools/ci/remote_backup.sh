#!/usr/bin/env bash
# Create allowlisted backup tarball on panel. Path printed on last line.
set -euo pipefail
stamp=$(date -u +%Y%m%dT%H%MZ)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/db" "$work/cfg"
sudo cp -a /var/lib/k-pax/k-pax.db "$work/db/" 2>/dev/null || true
sudo sqlite3 /var/lib/k-pax/k-pax.db ".backup '$work/db/k-pax.backup.db'" 2>/dev/null || true
for f in \
  /etc/k-pax/config.json \
  /etc/systemd/system/k-pax.service \
  /etc/systemd/system/kpax-front-relay.service \
  /etc/caddy/Caddyfile
do
  if sudo test -f "$f"; then
    sudo cp -a "$f" "$work/cfg/$(basename "$f")"
  fi
done
if [[ -f "$work/cfg/config.json" ]]; then
  python3 - "$work/cfg/config.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
c = json.loads(p.read_text(encoding="utf-8"))
for k in list(c.keys()):
    kl = k.lower()
    if any(x in kl for x in ("key", "pass", "secret", "token", "private")):
        c[k] = "<redacted>"
if isinstance(c.get("ssh_key"), str):
    c["ssh_key"] = "<redacted>"
p.write_text(json.dumps(c, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
fi
out="/tmp/kpax-ci-backup-${stamp}.tar.gz"
tar -C "$work" -czf "$out" .
echo "$out"
