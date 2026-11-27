#!/usr/bin/env bash
# Fail the GitHub Actions job when collected outputs contain FAIL markers.
set -euo pipefail
root="${1:-out}"
if [[ ! -d "$root" ]]; then
  echo "::error::missing output dir $root"
  exit 1
fi
# PL_PATH=FAIL is an explicit non-blocking advisory for the new PL exit.
if grep -R -E --line-regexp 'HEALTH_FAIL|STATUS=FAIL' "$root" >/dev/null 2>&1 \
  || grep -R -E '^E2E_FAIL |^FAIL | FAIL$|: FAIL|tcp .* FAIL|http .* FAIL|E2E_FAIL required' "$root" >/dev/null 2>&1; then
  echo "::error::One or more checks reported FAIL — see artifact SUMMARY / per-host logs"
  grep -R -n -E 'FAIL|STATUS=FAIL|HEALTH_FAIL|E2E_FAIL' "$root" | head -80 || true
  exit 1
fi
if grep -R -E '^PL_PATH=FAIL' "$root" >/dev/null 2>&1; then
  echo "::warning::PL SoftProbe path is FAIL (DE/FI fronts OK). See docs/OPS-PROVIDER-APIS.md / HANDOFF."
fi
echo "fail_if_marked: clean"
