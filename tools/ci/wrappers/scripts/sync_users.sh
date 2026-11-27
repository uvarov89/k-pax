#!/usr/bin/env bash
# Sync CI-E2E (and optionally active users) onto exits/fronts. Panel host only.
# Never prints UUID/password.
set -euo pipefail
if [[ ! -f /etc/k-pax/config.json ]]; then
  echo "STATUS=FAIL not panel host"
  exit 1
fi

python3 - <<'PY'
import json, secrets, sqlite3, subprocess
from pathlib import Path

cfg = json.loads(Path("/etc/k-pax/config.json").read_text())
conn = sqlite3.connect("/var/lib/k-pax/k-pax.db")
conn.row_factory = sqlite3.Row
cols = {r[1] for r in conn.execute("PRAGMA table_info(users)")}
row = conn.execute("SELECT * FROM users WHERE public_id='CI-E2E'").fetchone()
if row is None:
    print("STATUS=FAIL missing CI-E2E — run ensure-e2e-env first")
    raise SystemExit(1)
uid = row["uuid"]
hy2 = (row["hy2_password"] or "").strip() if "hy2_password" in cols else ""
if len(hy2) < 16:
    hy2 = secrets.token_hex(16)
    if "hy2_password" in cols:
        conn.execute("UPDATE users SET hy2_password=? WHERE public_id='CI-E2E'", (hy2,))
        conn.commit()
key = cfg["ssh_key"]
kh = cfg.get("known_hosts") or "/etc/k-pax/known_hosts"
ok = 0
fail = 0
for n in cfg.get("nodes") or []:
    if n.get("enabled", True) is False:
        print("skip", n.get("id"))
        continue
    host = n["host"]
    nid = n.get("id")
    cmd = "python3 /usr/local/sbin/k-pax-user.py add %s %s" % (uid, hy2)
    try:
        out = subprocess.check_output(
            ["ssh", "-i", key, "-o", "BatchMode=yes", "-o", "UserKnownHostsFile=%s" % kh, "root@%s" % host, cmd],
            text=True,
            stderr=subprocess.STDOUT,
            timeout=90,
        )
        print("sync", nid, out.strip().replace(uid, "<uuid>"))
        ok += 1
    except Exception as e:
        print("sync", nid, "FAIL", type(e).__name__)
        fail += 1
print("sync_summary ok=%s fail=%s" % (ok, fail))
if fail and not ok:
    raise SystemExit(1)
PY

echo "STATUS=OK"
