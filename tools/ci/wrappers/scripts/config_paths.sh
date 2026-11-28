#!/usr/bin/env bash
# Shared allowlist for kpax-ci config-* commands. Sourced by other scripts.
# kind|abs_path|restart_service|validator
# validator: singbox | caddy | unit | text | json-panel

config_resolve() {
  local kind="${1:-}"
  case "$kind" in
    singbox)
      CONFIG_PATH="/etc/sing-box/config.json"
      CONFIG_SERVICE="sing-box"
      CONFIG_VALIDATOR="singbox"
      CONFIG_DEADMAN_DEFAULT=1
      ;;
    caddy)
      CONFIG_PATH="/etc/caddy/Caddyfile"
      CONFIG_SERVICE="caddy"
      CONFIG_VALIDATOR="caddy"
      CONFIG_DEADMAN_DEFAULT=1
      ;;
    relay-unit)
      CONFIG_PATH="/etc/systemd/system/kpax-front-relay.service"
      CONFIG_SERVICE="kpax-front-relay"
      CONFIG_VALIDATOR="unit"
      CONFIG_DEADMAN_DEFAULT=0
      ;;
    kpax-unit)
      CONFIG_PATH="/etc/systemd/system/k-pax.service"
      CONFIG_SERVICE="k-pax"
      CONFIG_VALIDATOR="unit"
      CONFIG_DEADMAN_DEFAULT=0
      ;;
    panel-config)
      CONFIG_PATH="/etc/k-pax/config.json"
      CONFIG_SERVICE="k-pax"
      CONFIG_VALIDATOR="json-panel"
      CONFIG_DEADMAN_DEFAULT=0
      ;;
    ufw-status)
      # get-only pseudo kind
      CONFIG_PATH=""
      CONFIG_SERVICE=""
      CONFIG_VALIDATOR="ufw-get"
      CONFIG_DEADMAN_DEFAULT=0
      ;;
    ci-drill)
      # Isolated non-VPN file for acceptance drills only
      CONFIG_PATH="/etc/k-pax/ci-drill.conf"
      CONFIG_SERVICE=""
      CONFIG_VALIDATOR="text"
      CONFIG_DEADMAN_DEFAULT=1
      ;;
    resolved-dropin)
      # systemd-resolved drop-in (DNS= / FallbackDNS=). Network-sensitive → deadman default.
      CONFIG_PATH="/etc/systemd/resolved.conf.d/99-kpax-dns.conf"
      CONFIG_SERVICE="systemd-resolved"
      CONFIG_VALIDATOR="resolved-dropin"
      CONFIG_DEADMAN_DEFAULT=1
      ;;
    *)
      echo "STATUS=FAIL unknown kind=$kind (allow: singbox|caddy|relay-unit|kpax-unit|panel-config|ufw-status|ci-drill|resolved-dropin)"
      return 2
      ;;
  esac
  return 0
}

config_redact_stream() {
  # Must read piped stdin — do not use a heredoc (it steals stdin).
  python3 -c 'import re,sys
text=sys.stdin.read()
text=re.sub(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----","<pem-redacted>",text,flags=re.S)
subs=[
 (r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}","<uuid>",re.I),
 (r"\"uuid\"\s*:\s*\"[^\"]+\"","\"uuid\":\"<uuid>\"",0),
 (r"\"password\"\s*:\s*\"[^\"]+\"","\"password\":\"<redacted>\"",0),
 (r"\"private_key\"\s*:\s*\"[^\"]+\"","\"private_key\":\"<redacted>\"",0),
 (r"\"public_key\"\s*:\s*\"[^\"]+\"","\"public_key\":\"<pbk>\"",0),
 (r"\"short_id\"\s*:\s*(\"[^\"]+\"|\[[^\]]+\])","\"short_id\":\"<sid>\"",0),
 (r"\"token\"\s*:\s*\"[^\"]+\"","\"token\":\"<redacted>\"",0),
 (r"\"secret\"\s*:\s*\"[^\"]+\"","\"secret\":\"<redacted>\"",0),
 (r"\"ssh_key\"\s*:\s*\"[^\"]+\"","\"ssh_key\":\"<redacted>\"",0),
]
for pat,repl,flags in subs:
 text=re.sub(pat,repl,text,flags=flags)
sys.stdout.write(text)
'
}

config_validate_file() {
  local validator="$1" path="$2"
  case "$validator" in
    singbox)
      command -v sing-box >/dev/null || { echo "STATUS=FAIL sing-box missing"; return 1; }
      sing-box check -c "$path"
      ;;
    caddy)
      if command -v caddy >/dev/null; then
        caddy validate --config "$path" 2>&1 | tail -20
      else
        echo "note: caddy binary missing — syntax not validated"
      fi
      ;;
    unit)
      systemd-analyze verify "$path" 2>&1 | tail -20 || true
      ;;
    json-panel)
      python3 - "$path" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
cfg = json.loads(p.read_text(encoding="utf-8"))
assert isinstance(cfg, dict), "panel config must be object"
assert "nodes" in cfg, "missing nodes"
print("json-panel ok keys", len(cfg))
PY
      ;;
    text)
      test -s "$path"
      ;;
    resolved-dropin)
      python3 - "$path" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
assert "[Resolve]" in text, "missing [Resolve]"
# Only allow known keys
allowed = {"DNS", "FallbackDNS", "Domains", "DNSStubListener", "DNSOverTLS"}
for line in text.splitlines():
    s = line.strip()
    if not s or s.startswith("#") or s.startswith("["):
        continue
    if "=" not in s:
        raise SystemExit("bad line: " + s)
    k = s.split("=", 1)[0].strip()
    assert k in allowed, "refused key " + k
print("resolved-dropin ok")
PY
      ;;
    ufw-get)
      true
      ;;
    *)
      echo "STATUS=FAIL bad validator"; return 2
      ;;
  esac
}
