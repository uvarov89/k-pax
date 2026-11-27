#!/usr/bin/env bash
# Fail the GitHub Actions job when collected outputs contain FAIL markers.
set -euo pipefail
root="${1:-out}"
if [[ ! -d "$root" ]]; then
  echo "::error::missing output dir $root"
  exit 1
fi
# Build a filtered view: PL SoftProbe advisories must not fail the job while
# DE/FI fronts are OK (STATUS=OK + PL_PATH=FAIL is intentional).
tmp=$(mktemp)
# shellcheck disable=SC2064
trap 'rm -f "$tmp"' EXIT
grep -R -n -E 'FAIL|STATUS=|HEALTH_FAIL|E2E_FAIL|PL_PATH=' "$root" 2>/dev/null \
  | grep -Ev 'PL_PATH=FAIL|front-pl:|PL SoftProbe|PL_SOFTPROBE|relay-pl .* WARN' \
  >"$tmp" || true

if grep -E 'HEALTH_FAIL|STATUS=FAIL|^[^:]+:[0-9]+:E2E_FAIL required|^[^:]+:[0-9]+:FAIL |tcp .* FAIL|http .* FAIL|FAIL public|FAIL e2e|FAIL validate' "$tmp" >/dev/null 2>&1; then
  echo "::error::One or more checks reported FAIL — see artifact SUMMARY / per-host logs"
  head -80 "$tmp" || true
  exit 1
fi
if grep -R -E 'PL_PATH=FAIL|front-pl:' "$root" >/dev/null 2>&1; then
  echo "::warning::PL SoftProbe path is FAIL (DE/FI fronts OK). See docs/OPS-PROVIDER-APIS.md / HANDOFF."
fi
echo "fail_if_marked: clean"
