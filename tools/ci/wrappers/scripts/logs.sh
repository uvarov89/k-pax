#!/usr/bin/env bash
# Dump redacted journals / e2e fail logs to stdout (Actions-visible, no ZIP required).
# Usage: kpax-ci logs [sing-box|e2e|all|relay|caddy|k-pax] [lines]
set -euo pipefail
KIND="${1:-all}"
LINES="${2:-80}"
[[ "$LINES" =~ ^[0-9]+$ ]] || LINES=80
(( LINES >= 20 && LINES <= 400 )) || LINES=80

redact() {
  sed -E \
    -e 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/gi' \
    -e 's/"public_key"[[:space:]]*:[[:space:]]*"[^"]+"/"public_key":"<pbk>"/g' \
    -e 's/"private_key"[[:space:]]*:[[:space:]]*"[^"]+"/"private_key":"<sk>"/g' \
    -e 's/"short_id"[[:space:]]*:[[:space:]]*("[^"]+"|\[[^]]+\])/"short_id":"<sid>"/g' \
    -e 's/"password"[[:space:]]*:[[:space:]]*"[^"]+"/"password":"<redacted>"/g'
}

dump_unit() {
  local u="$1"
  echo "=== journal $u last ${LINES} (redacted) host=$(hostname) ==="
  journalctl -u "$u" -n "$LINES" --no-pager 2>/dev/null | redact || echo "(no journal)"
}

dump_e2e() {
  local dir=/var/log/k-pax-ci/e2e
  echo "=== e2e logs dir=$dir ==="
  if [[ ! -d "$dir" ]]; then
    echo "(missing — run e2e on panel first)"
    return 0
  fi
  ls -lt "$dir" 2>/dev/null | head -20 || true
  # Latest run + recent fails
  local latest
  latest=$(ls -1t "$dir"/run-*.log 2>/dev/null | head -1 || true)
  if [[ -n "$latest" ]]; then
    echo "--- $(basename "$latest") ---"
    redact < "$latest" | tail -n "$LINES"
  fi
  local f
  for f in $(ls -1t "$dir"/fail-*.log 2>/dev/null | head -6); do
    echo "--- $(basename "$f") ---"
    redact < "$f" | tail -n "$LINES"
  done
}

echo "=== kpax-ci logs kind=$KIND lines=$LINES $(date -u +%Y-%m-%dT%H:%MZ) ==="
case "$KIND" in
  sing-box|singbox) dump_unit sing-box ;;
  relay) dump_unit kpax-front-relay ;;
  caddy) dump_unit caddy ;;
  k-pax|panel) dump_unit k-pax ;;
  e2e) dump_e2e ;;
  all)
    dump_unit sing-box
    dump_unit kpax-front-relay
    dump_e2e
    ;;
  *)
    echo "STATUS=FAIL unknown logs kind=$KIND"
    exit 2
    ;;
esac
echo "STATUS=OK"
