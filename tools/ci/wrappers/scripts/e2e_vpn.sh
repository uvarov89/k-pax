#!/usr/bin/env bash
# End-to-end Reality SoftProbe using /etc/k-pax/ci-e2e.env (operator-maintained).
# Never prints UUID/password. TCP-open alone is NOT treated as success.
set -euo pipefail
ENV_FILE="${KPAX_CI_E2E_ENV:-/etc/k-pax/ci-e2e.env}"
echo "=== e2e-vpn $(hostname) $(date -u +%Y-%m-%dT%H:%MZ) ==="

if [[ ! -f "$ENV_FILE" ]]; then
  echo "E2E_FAIL missing $ENV_FILE (create on panel; never commit secrets)"
  echo "STATUS=FAIL"
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${E2E_UUID:?}"
: "${E2E_PBK:?}"
: "${E2E_SID:?}"

probe_one() {
  local label="$1" server="$2" port="$3" sni="$4" pbk="$5" sid="$6"
  local listen work cfg log code
  work=$(mktemp -d)
  listen=$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()
PY
)
  cfg="$work/p.json"
  log="$work/log"
  python3 - "$cfg" "$server" "$port" "$E2E_UUID" "$sni" "$pbk" "$sid" "$listen" <<'PY'
import json, sys
path, server, port, uuid, sni, pbk, sid, listen = sys.argv[1:9]
probe = {
  "log": {"level": "warn"},
  "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": int(listen)}],
  "outbounds": [{
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
      "reality": {"enabled": True, "public_key": pbk, "short_id": sid},
    },
  }],
}
open(path, "w", encoding="utf-8").write(json.dumps(probe))
PY
  local attempt code=000 ip_sample="" pid
  for attempt in 1 2 3; do
    sing-box run -c "$cfg" >"$log" 2>&1 &
    pid=$!
    sleep 1.4
    code=$(curl -s -o /dev/null -w '%{http_code}' -x "http://127.0.0.1:${listen}" \
      --connect-timeout 8 --max-time 14 https://www.gstatic.com/generate_204 || true)
    code=${code:-000}
    [[ "$code" =~ ^[0-9]+$ ]] || code=000
    ip_sample=$(curl -s -x "http://127.0.0.1:${listen}" --connect-timeout 8 --max-time 14 \
      https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -E '^(ip|loc)=' | tr '\n' ' ' || true)
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    if [[ "$code" == "204" || "$code" == "200" ]]; then
      echo "e2e $label SoftProbe HTTP $code OK ${ip_sample}"
      rm -rf "$work"
      return 0
    fi
    sleep 0.8
  done
  rm -rf "$work"
  echo "E2E_FAIL $label SoftProbe HTTP $code"
  return 1
}

FAIL=0
PL_FAIL=0
# Defaults can be overridden in ci-e2e.env
FRONT_HOST="${E2E_FRONT_HOST:-media.nastolkashop.store}"
FRONT_SNI="${E2E_FRONT_SNI:-media.nastolkashop.store}"
DE_HOST="${E2E_DE_HOST:-31.77.116.51}"
DE_SNI="${E2E_DE_SNI:-files.nastolkashop.store}"
FI_HOST="${E2E_FI_HOST:-144.31.169.6}"
FI_SNI="${E2E_FI_SNI:-static.nastolkashop.store}"
PL_HOST="${E2E_PL_HOST:-2.26.225.213}"
PL_SNI="${E2E_PL_SNI:-pl.k-pax.space}"

probe_one "front-de:${FRONT_HOST}:2443" "$FRONT_HOST" 2443 "$FRONT_SNI" "$E2E_PBK" "$E2E_SID" || FAIL=1
probe_one "front-fi:${FRONT_HOST}:2444" "$FRONT_HOST" 2444 "$FRONT_SNI" "$E2E_PBK" "$E2E_SID" || FAIL=1
# PL is enabled in inventory; SoftProbe must be visible even if path still broken.
if ! probe_one "front-pl:${FRONT_HOST}:2445" "$FRONT_HOST" 2445 "$FRONT_SNI" "$E2E_PBK" "$E2E_SID"; then
  PL_FAIL=1
  echo "PL_PATH=FAIL front SoftProbe (investigate to-pl / PL Reality / DNS pl.k-pax.space)"
fi
# Direct exits (may FAIL from some networks — report, do not hide)
DE_PBK="${E2E_DE_PBK:-$E2E_PBK}"; DE_SID="${E2E_DE_SID:-$E2E_SID}"
FI_PBK="${E2E_FI_PBK:-$E2E_PBK}"; FI_SID="${E2E_FI_SID:-$E2E_SID}"
PL_PBK="${E2E_PL_PBK:-$E2E_PBK}"; PL_SID="${E2E_PL_SID:-$E2E_SID}"
probe_one "direct-de:${DE_HOST}:443" "$DE_HOST" 443 "$DE_SNI" "$DE_PBK" "$DE_SID" || echo "note direct-de SoftProbe soft-fail (path-dependent)"
probe_one "direct-fi:${FI_HOST}:443" "$FI_HOST" 443 "$FI_SNI" "$FI_PBK" "$FI_SID" || echo "note direct-fi SoftProbe soft-fail (path-dependent)"
probe_one "direct-pl:${PL_HOST}:443" "$PL_HOST" 443 "$PL_SNI" "$PL_PBK" "$PL_SID" || echo "note direct-pl SoftProbe soft-fail (path-dependent)"

# Required RF path: front-de + front-fi. PL tracked separately until Reality hop is green.
if [[ "$FAIL" -ne 0 ]]; then
  echo "STATUS=FAIL"
  echo "E2E_FAIL required front SoftProbe failed (de/fi)"
  exit 1
fi
if [[ "$PL_FAIL" -ne 0 ]]; then
  echo "STATUS=OK"
  echo "PL_PATH=FAIL"
  echo "DONE"
  exit 0
fi
echo "STATUS=OK"
echo "PL_PATH=OK"
echo "DONE"
