#!/usr/bin/env bash
# Shared runner for .github/workflows/config-ops.yml
set -euo pipefail
mkdir -p out
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=yes -i "$HOME/.ssh/id_ed25519" -o UserKnownHostsFile="$HOME/.ssh/known_hosts")
SCP=(scp -o BatchMode=yes -o StrictHostKeyChecking=yes -i "$HOME/.ssh/id_ed25519" -o UserKnownHostsFile="$HOME/.ssh/known_hosts")
CI=/usr/local/lib/kpax-ci/kpax-ci

declare -A HOSTS=(
  [panel]="${PANEL}"
  [de]=31.77.116.51
  [fi]=144.31.169.6
  [pl]=2.26.225.213
  [ru]=195.133.45.167
  [ru2]=152.228.112.142
)

case "${KIND}" in
  singbox|caddy|relay-unit|kpax-unit|panel-config|ufw-status|ci-drill|resolved-dropin) ;;
  *) echo "::error::kind not allowlisted: $KIND"; exit 1 ;;
esac

FAIL=0
IFS=',' read -ra items <<< "$TARGETS"
for id in "${items[@]}"; do
  id="$(echo "$id" | xargs)"
  [[ -n "$id" ]] || continue
  host="${HOSTS[$id]:-}"
  [[ -n "$host" ]] || { echo "FAIL unknown target $id" | tee "out/${id}.txt"; FAIL=1; continue; }
  echo "== $id $ACTION $KIND =="

  case "$ACTION" in
    get)
      if ! "${SSH[@]}" "gha@${host}" "sudo $CI config-get $KIND" > "out/${id}-${KIND}.txt" 2>&1; then
        echo "FAIL get $id" | tee -a "out/${id}-${KIND}.txt"
        FAIL=1
      fi
      ;;
    deadman-status)
      if ! "${SSH[@]}" "gha@${host}" "sudo $CI deadman-status" > "out/${id}-deadman.txt" 2>&1; then
        FAIL=1
      fi
      ;;
    deadman-cancel)
      if ! "${SSH[@]}" "gha@${host}" "sudo $CI deadman-cancel" > "out/${id}-deadman-cancel.txt" 2>&1; then
        FAIL=1
      fi
      ;;
    diff|apply)
      # Stage candidate from repo ops/candidates/<kind> (filename mapping)
      case "$KIND" in
        singbox) cand_repo="ops/candidates/singbox.json" ;;
        caddy) cand_repo="ops/candidates/caddy.Caddyfile" ;;
        relay-unit) cand_repo="ops/candidates/kpax-front-relay.service" ;;
        kpax-unit) cand_repo="ops/candidates/k-pax.service" ;;
        panel-config) cand_repo="ops/candidates/panel-config.json" ;;
        ci-drill) cand_repo="ops/candidates/ci-drill.conf" ;;
        *) echo "FAIL no candidate mapping for $KIND"; FAIL=1; continue ;;
      esac
      [[ -f "$cand_repo" ]] || { echo "FAIL missing $cand_repo — commit candidate first"; FAIL=1; continue; }
      # Refuse obvious secrets in candidates for non-panel kinds logged to Actions
      if [[ "$KIND" != "panel-config" ]]; then
        if grep -Eiq 'BEGIN (RSA |OPENSSH |)PRIVATE KEY' "$cand_repo"; then
          echo "FAIL candidate looks secret-bearing"; FAIL=1; continue
        fi
      fi
      "${SSH[@]}" "gha@${host}" 'rm -rf /tmp/kpax-ci-stage && mkdir -m 700 /tmp/kpax-ci-stage'
      "${SCP[@]}" "$cand_repo" "gha@${host}:/tmp/kpax-ci-stage/${KIND}"
      if [[ "$ACTION" == "diff" ]]; then
        if ! "${SSH[@]}" "gha@${host}" "sudo $CI config-diff $KIND" > "out/${id}-diff.txt" 2>&1; then
          FAIL=1
        fi
      else
        args=("$KIND")
        if [[ "${DRY_RUN:-true}" == "true" ]]; then
          args+=(--dry-run)
        fi
        if [[ -n "${DEADMAN:-}" && "${DEADMAN}" != "0" && "${DRY_RUN:-true}" != "true" ]]; then
          args+=(--deadman "$DEADMAN")
        fi
        # shellcheck disable=SC2029
        if ! "${SSH[@]}" "gha@${host}" "sudo $CI config-apply ${args[*]}" > "out/${id}-apply.txt" 2>&1; then
          echo "FAIL apply $id" | tee -a "out/${id}-apply.txt"
          FAIL=1
        fi
      fi
      ;;
    rollback)
      # shellcheck disable=SC2029
      if [[ -n "${BACKUP_NAME:-}" ]]; then
        remote="sudo $CI config-rollback $KIND $BACKUP_NAME"
      else
        remote="sudo $CI config-rollback $KIND"
      fi
      if ! "${SSH[@]}" "gha@${host}" "$remote" > "out/${id}-rollback.txt" 2>&1; then
        FAIL=1
      fi
      ;;
    patch)
      [[ -n "${PATCH_SET:-}" ]] || { echo "FAIL patch_set empty"; FAIL=1; continue; }
      # shellcheck disable=SC2029
      args=("$KIND")
      if [[ "${DRY_RUN:-true}" == "true" ]]; then
        args+=(--dry-run)
      else
        [[ -n "${PATCH_DIGEST:-}" ]] || { echo "FAIL real patch needs patch_digest"; FAIL=1; continue; }
        args+=(--digest "$PATCH_DIGEST")
      fi
      if [[ -n "${DEADMAN:-}" && "${DEADMAN}" != "0" && "${DRY_RUN:-true}" != "true" ]]; then
        args+=(--deadman "$DEADMAN")
      fi
      # Pass patch tokens as separate args (no secrets allowed by allowlist)
      # shellcheck disable=SC2086
      if ! "${SSH[@]}" "gha@${host}" "sudo $CI config-patch ${args[*]} -- ${PATCH_SET}" \
        | tee "out/${id}-patch.txt"; then
        echo "FAIL patch $id" | tee -a "out/${id}-patch.txt"
        FAIL=1
      fi
      ;;
    deadman-drill)
      # Isolated auto-rollback proof on ci-drill only (panel)
      [[ "$KIND" == "ci-drill" ]] || { echo "FAIL deadman-drill only for ci-drill"; FAIL=1; continue; }
      [[ "$id" == "panel" ]] || { echo "skip deadman-drill on $id"; continue; }
      if ! "${SSH[@]}" "gha@${host}" "sudo bash -s" <<'REMOTE' | tee "out/${id}-deadman-drill.txt"
set -euo pipefail
CI=/usr/local/lib/kpax-ci/kpax-ci
mkdir -p /etc/k-pax /tmp/kpax-ci-stage /var/backups/k-pax-ci
# Baseline v1 without deadman
printf '%s\n' 'drill_version=1' 'note=deadman-base' > /tmp/kpax-ci-stage/ci-drill
$CI config-apply ci-drill --deadman 0
grep -q 'drill_version=1' /etc/k-pax/ci-drill.conf
# Mutate to v2 with 1-minute deadman — intentionally do NOT cancel
printf '%s\n' 'drill_version=2' 'note=deadman-temp' > /tmp/kpax-ci-stage/ci-drill
$CI config-apply ci-drill --deadman 1
grep -q 'drill_version=2' /etc/k-pax/ci-drill.conf
echo "armed waiting for deadman fire..."
ok=0
for i in $(seq 1 20); do
  sleep 5
  if grep -q 'drill_version=1' /etc/k-pax/ci-drill.conf 2>/dev/null && ! grep -q 'drill_version=2' /etc/k-pax/ci-drill.conf 2>/dev/null; then
    echo "DEADMAN_FIRE_OK after $((i*5))s"
    cat /etc/k-pax/ci-drill.conf
    ok=1
    break
  fi
  echo "wait $i content=$(tr '\n' ' ' </etc/k-pax/ci-drill.conf 2>/dev/null || true)"
done
$CI deadman-status || true
[[ "$ok" -eq 1 ]] || { echo "STATUS=FAIL deadman did not restore"; exit 1; }
echo "STATUS=OK deadman-drill"
REMOTE
      then
        echo "ok deadman-drill"
      else
        echo "FAIL deadman-drill" | tee -a "out/${id}-deadman-drill.txt"
        FAIL=1
      fi
      ;;
    *) echo "FAIL bad action"; exit 1 ;;
  esac
done

if [[ "${RUN_E2E:-false}" == "true" && "${DRY_RUN:-true}" != "true" && ( "$ACTION" == "apply" || "$ACTION" == "patch" ) && "$FAIL" -eq 0 ]]; then
  echo "== post-apply e2e (egress IP checked inside SoftProbe) =="
  if ! "${SSH[@]}" "gha@${PANEL}" "sudo $CI e2e" | tee out/e2e.txt; then
    echo "FAIL e2e after apply — consider config-rollback / deadman" | tee -a out/e2e.txt
    FAIL=1
  fi
  "${SSH[@]}" "gha@${PANEL}" "sudo $CI logs e2e 80" | tee out/e2e-logs-inline.txt || true
fi

{
  echo "# config-ops summary $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "action=$ACTION kind=$KIND targets=$TARGETS dry=${DRY_RUN:-n/a}"
  grep -E 'STATUS=|FAIL|DIFF_|APPLY_|DRY_RUN|deadman|validation' out/*.txt 2>/dev/null || true
} | tee out/SUMMARY.txt

if [[ "$FAIL" -ne 0 ]]; then
  echo "::error::config-ops reported failures"
  exit 1
fi
# Also fail if any STATUS=FAIL markers
if grep -R "STATUS=FAIL" out/ >/dev/null 2>&1; then
  exit 1
fi
