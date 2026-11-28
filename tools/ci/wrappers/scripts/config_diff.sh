#!/usr/bin/env bash
# Diff staged candidate vs live. Usage: kpax-ci config-diff <kind>
# Candidate: /tmp/kpax-ci-stage/<kind>
set -euo pipefail
source "$(dirname "$0")/config_paths.sh"
kind="${1:?kind}"
config_resolve "$kind" || exit $?
cand="/tmp/kpax-ci-stage/$kind"
[[ -f "$cand" ]] || { echo "STATUS=FAIL missing candidate $cand"; exit 1; }
[[ -n "$CONFIG_PATH" ]] || { echo "STATUS=FAIL kind has no file path"; exit 1; }

echo "=== config-diff kind=$kind ==="
echo "live=$CONFIG_PATH"
echo "candidate=$cand"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "live: (missing)"
  echo "----- candidate (sanitized) -----"
  config_redact_stream < "$cand" | head -200
  echo "STATUS=OK diff=new-file"
  exit 0
fi

# Validate candidate before showing diff as "applyable"
if ! config_validate_file "$CONFIG_VALIDATOR" "$cand"; then
  echo "STATUS=FAIL candidate validation failed"
  exit 1
fi

tmpd=$(mktemp -d)
trap 'rm -rf "$tmpd"' EXIT
config_redact_stream < "$CONFIG_PATH" >"$tmpd/live"
config_redact_stream < "$cand" >"$tmpd/cand"
if diff -u "$tmpd/live" "$tmpd/cand" | tee "$tmpd/diff" | head -400; then
  echo "DIFF_EMPTY=1"
else
  echo "DIFF_EMPTY=0"
fi
echo "STATUS=OK"
