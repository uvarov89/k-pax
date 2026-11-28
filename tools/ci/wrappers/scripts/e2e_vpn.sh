#!/usr/bin/env bash
# Layered Reality SoftProbe using dedicated /etc/k-pax/ci-e2e.env (CI-E2E account).
# Never prints UUID. Never borrows front Reality keys for exits that lack their own.
# TCP-open alone is NOT success. HTTP success requires egress IP check when expected.
set -euo pipefail

ENV_FILE="${KPAX_CI_E2E_ENV:-/etc/k-pax/ci-e2e.env}"
LOG_DIR="${KPAX_CI_E2E_LOG_DIR:-/var/log/k-pax-ci/e2e}"
mkdir -p "$LOG_DIR"
STAMP=$(date -u +%Y%m%dT%H%MZ)
RUN_LOG="$LOG_DIR/run-${STAMP}.log"
exec > >(tee -a "$RUN_LOG") 2>&1

echo "=== e2e-vpn $(hostname) ${STAMP} ==="
TOOL_FAIL=0
VPN_FAIL=0
declare -A NODE_STATUS=()

mark() {
  local key="$1" st="$2"
  NODE_STATUS["$key"]="$st"
  echo "NODE $key=$st"
}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "TOOL_FAIL missing $ENV_FILE (run kpax-ci ensure-e2e-env on panel)"
  echo "STATUS=FAIL"
  echo "CLASS=TOOL"
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
if [[ -z "${E2E_UUID:-}" ]]; then
  echo "TOOL_FAIL E2E_UUID empty"
  echo "STATUS=FAIL"
  echo "CLASS=TOOL"
  exit 1
fi
if [[ -z "${E2E_FRONT_PBK:-}" || -z "${E2E_FRONT_SID:-}" ]]; then
  echo "TOOL_FAIL front Reality PBK/SID missing in env"
  echo "STATUS=FAIL"
  echo "CLASS=TOOL"
  exit 1
fi

redact() {
  sed -E \
    -e 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/gi' \
    -e 's/"public_key"[[:space:]]*:[[:space:]]*"[^"]+"/"public_key":"<pbk>"/g' \
    -e 's/"short_id"[[:space:]]*:[[:space:]]*"[^"]+"/"short_id":"<sid>"/g' \
    -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g'
}

tcp_check() {
  local host="$1" port="$2"
  timeout 5 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null
}

# SoftProbe: HTTP via mixed inbound. Saves redacted sing-box log on failure.
# Returns 0 only if HTTP 200/204 AND (optional) egress IP matches expect_ip.
probe_http() {
  local label="$1" server="$2" port="$3" sni="$4" pbk="$5" sid="$6" expect_ip="${7:-}"
  local listen work cfg log code ip_got="" pid attempt
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
  "log": {"level": "info", "timestamp": True},
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

  code=000
  for attempt in 1 2 3; do
    sing-box run -c "$cfg" >"$log" 2>&1 &
    pid=$!
    sleep 1.5
    code=$(curl -s -o /dev/null -w '%{http_code}' -x "http://127.0.0.1:${listen}" \
      --connect-timeout 8 --max-time 14 https://www.gstatic.com/generate_204 || true)
    code=${code:-000}
    [[ "$code" =~ ^[0-9]+$ ]] || code=000
    ip_got=$(curl -s -x "http://127.0.0.1:${listen}" --connect-timeout 8 --max-time 14 \
      https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^ip=/{print $2}' || true)
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    if [[ "$code" == "204" || "$code" == "200" ]]; then
      if [[ -n "$expect_ip" && -n "$ip_got" && "$ip_got" != "$expect_ip" ]]; then
        echo "E2E_FAIL $label HTTP $code but egress_ip=$ip_got expect=$expect_ip"
        # continue retries — may be transient
      else
        echo "e2e $label SoftProbe HTTP $code OK egress=${ip_got:-n/a}"
        rm -rf "$work"
        return 0
      fi
    fi
    sleep 0.8
  done

  # Persist redacted failure evidence
  local fail_log="$LOG_DIR/fail-${label//[:\/]/_}-${STAMP}.log"
  {
    echo "# fail $label code=$code egress=${ip_got:-}"
    echo "# curl 000 usually means: dial refused, Reality auth fail, TLS handshake fail, or DNS"
    redact < "$log"
  } > "$fail_log" 2>/dev/null || true
  echo "E2E_FAIL $label SoftProbe HTTP ${code} (detail $fail_log)"
  if [[ "$code" == "000" ]]; then
    echo "HINT HTTP_000: TCP may be open but Reality/TLS/UUID rejected, or sing-box crashed — see fail log"
  fi
  rm -rf "$work"
  return 1
}

run_path() {
  # label host port sni pbk sid expect_ip required(0|1)
  local label="$1" host="$2" port="$3" sni="$4" pbk="$5" sid="$6" expect_ip="$7" required="$8"
  echo "--- path $label ---"
  if [[ -z "$host" || -z "$sni" || -z "$pbk" || -z "$sid" ]]; then
    echo "SKIP $label missing individual Reality params (no key borrowing)"
    mark "$label" "SKIP_NO_KEYS"
    if [[ "$required" == "1" ]]; then
      TOOL_FAIL=1
    fi
    return 0
  fi
  if ! tcp_check "$host" "$port"; then
    echo "E2E_FAIL $label TCP closed ${host}:${port}"
    mark "$label" "FAIL_TCP"
    VPN_FAIL=1
    return 1
  fi
  echo "tcp $label ${host}:${port} open"
  if probe_http "$label" "$host" "$port" "$sni" "$pbk" "$sid" "$expect_ip"; then
    mark "$label" "OK"
    return 0
  fi
  mark "$label" "FAIL_SOFTPROBE"
  VPN_FAIL=1
  return 1
}

FRONT_HOST="${E2E_FRONT_HOST:-}"
FRONT_SNI="${E2E_FRONT_SNI:-}"
FRONT_PBK="${E2E_FRONT_PBK}"
FRONT_SID="${E2E_FRONT_SID}"

# Required RF fronts: DE + FI. PL is required for honest overall status.
run_path "front-de:${FRONT_HOST}:2443" "$FRONT_HOST" 2443 "$FRONT_SNI" "$FRONT_PBK" "$FRONT_SID" "${E2E_EXPECT_DE_IP:-}" 1 || true
run_path "front-fi:${FRONT_HOST}:2444" "$FRONT_HOST" 2444 "$FRONT_SNI" "$FRONT_PBK" "$FRONT_SID" "${E2E_EXPECT_FI_IP:-}" 1 || true
run_path "front-pl:${FRONT_HOST}:2445" "$FRONT_HOST" 2445 "$FRONT_SNI" "$FRONT_PBK" "$FRONT_SID" "${E2E_EXPECT_PL_IP:-}" 1 || true

# Direct exits — individual keys only; skip if absent (do NOT fall back to front PBK/SID)
run_path "direct-de:${E2E_DE_HOST:-}:443" "${E2E_DE_HOST:-}" 443 "${E2E_DE_SNI:-}" "${E2E_DE_PBK:-}" "${E2E_DE_SID:-}" "${E2E_EXPECT_DE_IP:-}" 0 || true
run_path "direct-fi:${E2E_FI_HOST:-}:443" "${E2E_FI_HOST:-}" 443 "${E2E_FI_SNI:-}" "${E2E_FI_PBK:-}" "${E2E_FI_SID:-}" "${E2E_EXPECT_FI_IP:-}" 0 || true
run_path "direct-pl:${E2E_PL_HOST:-}:443" "${E2E_PL_HOST:-}" 443 "${E2E_PL_SNI:-}" "${E2E_PL_PBK:-}" "${E2E_PL_SID:-}" "${E2E_EXPECT_PL_IP:-}" 0 || true

echo "=== node status map ==="
for k in "${!NODE_STATUS[@]}"; do
  echo "  $k -> ${NODE_STATUS[$k]}"
done | sort

# Inline recent fail logs so Actions viewers need no ZIP
echo "=== recent e2e fail logs (redacted, inline) ==="
if [[ -d "$LOG_DIR" ]]; then
  mapfile -t _fails < <(ls -1t "$LOG_DIR"/fail-*.log 2>/dev/null | head -6 || true)
  if ((${#_fails[@]} == 0)); then
    echo "(none)"
  else
    for f in "${_fails[@]}"; do
      echo "--- $(basename "$f") ---"
      redact < "$f" | tail -n 60
    done
  fi
fi

# Honest gates: front-de OR front-fi must OK; front-pl must OK for STATUS=OK
DE_OK=0; FI_OK=0; PL_OK=0
[[ "${NODE_STATUS[front-de:${FRONT_HOST}:2443]:-}" == "OK" ]] && DE_OK=1
[[ "${NODE_STATUS[front-fi:${FRONT_HOST}:2444]:-}" == "OK" ]] && FI_OK=1
[[ "${NODE_STATUS[front-pl:${FRONT_HOST}:2445]:-}" == "OK" ]] && PL_OK=1

if [[ "$TOOL_FAIL" -ne 0 ]]; then
  echo "STATUS=FAIL"
  echo "CLASS=TOOL"
  echo "DONE"
  exit 1
fi
if [[ "$DE_OK" -eq 0 && "$FI_OK" -eq 0 ]]; then
  echo "STATUS=FAIL"
  echo "CLASS=VPN"
  echo "E2E_FAIL required front SoftProbe failed (both de and fi)"
  echo "DONE"
  exit 1
fi
if [[ "$PL_OK" -eq 0 ]]; then
  echo "STATUS=FAIL"
  echo "CLASS=VPN"
  echo "PL_PATH=FAIL"
  echo "E2E_FAIL Poland front SoftProbe failed — does not green overall (PL config unchanged pending RCA)"
  echo "DONE"
  exit 1
fi
echo "STATUS=OK"
echo "CLASS=VPN"
echo "PL_PATH=OK"
echo "DONE"
