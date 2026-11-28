#!/usr/bin/env bash
# Sanitized config dump. Usage: kpax-ci config-get <kind>
set -euo pipefail
# shellcheck source=config_paths.sh
source "$(dirname "$0")/config_paths.sh"
kind="${1:?kind}"
config_resolve "$kind" || exit $?
echo "=== config-get kind=$kind host=$(hostname -f 2>/dev/null || hostname) $(date -u +%Y-%m-%dT%H:%MZ) ==="

if [[ "$kind" == "ufw-status" ]]; then
  if command -v ufw >/dev/null 2>&1; then
    ufw status numbered 2>/dev/null | head -80 || true
  elif command -v nft >/dev/null 2>&1; then
    nft list ruleset 2>/dev/null | head -80 || true
  else
    iptables -L -n 2>/dev/null | head -40 || true
  fi
  echo "STATUS=OK"
  exit 0
fi

[[ -n "$CONFIG_PATH" && -f "$CONFIG_PATH" ]] || {
  # ci-drill may not exist yet
  if [[ "$kind" == "ci-drill" ]]; then
    echo "(missing — will be created on first apply)"
    echo "STATUS=OK"
    exit 0
  fi
  echo "STATUS=FAIL missing $CONFIG_PATH"
  exit 1
}

echo "path=$CONFIG_PATH"
echo "service=${CONFIG_SERVICE:-none}"
echo "----- begin sanitized -----"
if [[ "$CONFIG_VALIDATOR" == "json-panel" || "$kind" == "singbox" ]]; then
  python3 - "$CONFIG_PATH" <<'PY' | config_redact_stream
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
raw = p.read_text(encoding="utf-8", errors="replace")
try:
    cfg = json.loads(raw)
except json.JSONDecodeError:
    print(raw)
    raise SystemExit(0)
# Structure summary for sing-box; full redacted JSON for panel
if p.name == "config.json" and "inbounds" in cfg:
    ins = cfg.get("inbounds") or []
    outs = cfg.get("outbounds") or []
    print(json.dumps({
        "log": cfg.get("log"),
        "inbound_count": len(ins),
        "outbound_count": len(outs),
        "inbounds": [
            {
                "type": i.get("type"),
                "tag": i.get("tag"),
                "listen_port": i.get("listen_port") or i.get("port"),
                "users": len(i.get("users") or []),
                "tls_server_name": ((i.get("tls") or {}).get("server_name")),
                "reality": bool(((i.get("tls") or {}).get("reality") or {}).get("enabled")),
            }
            for i in ins
        ],
        "outbounds": [
            {
                "type": o.get("type"),
                "tag": o.get("tag"),
                "server": o.get("server"),
                "server_port": o.get("server_port"),
            }
            for o in outs
            if o.get("type") not in ("direct", "block", "dns")
        ][:40],
    }, indent=2, ensure_ascii=False))
else:
    # panel-config: drop secret-looking keys
    def scrub(o):
        if isinstance(o, dict):
            out = {}
            for k, v in o.items():
                kl = str(k).lower()
                if any(x in kl for x in ("key", "pass", "secret", "token", "private", "pbk", "sid")):
                    out[k] = "<redacted>"
                else:
                    out[k] = scrub(v)
            return out
        if isinstance(o, list):
            return [scrub(x) for x in o]
        return o
    print(json.dumps(scrub(cfg), indent=2, ensure_ascii=False))
PY
else
  config_redact_stream < "$CONFIG_PATH"
fi
echo "----- end sanitized -----"
echo "STATUS=OK"
