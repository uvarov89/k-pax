#!/usr/bin/env bash
# Deadman / emergency local rollback timer.
# Usage:
#   kpax-ci deadman-arm <stamp> <minutes> <kind...>
#   kpax-ci deadman-cancel [stamp]
#   kpax-ci deadman-status
set -euo pipefail
DM_DIR="/var/backups/k-pax-ci/deadman"
mkdir -p "$DM_DIR"
CMD="${1:-status}"
shift || true

case "$CMD" in
  arm)
    stamp="${1:?stamp}"
    minutes="${2:?minutes}"
    shift 2
    [[ "$minutes" =~ ^[0-9]+$ ]] || { echo "STATUS=FAIL bad minutes"; exit 2; }
    (( minutes >= 1 && minutes <= 30 )) || { echo "STATUS=FAIL minutes must be 1..30"; exit 2; }
    kinds=("$@")
    (( ${#kinds[@]} >= 1 )) || { echo "STATUS=FAIL need kinds"; exit 2; }
    state="$DM_DIR/$stamp"
    mkdir -p "$state"
    printf '%s\n' "${kinds[@]}" >"$state/kinds.txt"
    echo "$minutes" >"$state/minutes.txt"
    date -u +%Y-%m-%dT%H:%MZ >"$state/armed_at.txt"
    # Cancel previous timer unit if any
    for u in $(systemctl list-units --all 'kpax-ci-deadman*' --no-legend 2>/dev/null | awk '{print $1}'); do
      systemctl stop "$u" 2>/dev/null || true
      systemctl reset-failed "$u" 2>/dev/null || true
    done
    ln -sfn "$state" "$DM_DIR/latest"
    # One-shot restore after N minutes unless cancelled (SSH-loss safety net)
    systemd-run --unit=kpax-ci-deadman --on-active="${minutes}min" --timer-property=AccuracySec=1s \
      /usr/local/lib/kpax-ci/kpax-ci deadman-fire "$stamp"
    echo "deadman armed stamp=$stamp minutes=$minutes kinds=${kinds[*]}"
    echo "STATUS=OK"
    ;;
  fire)
    stamp="${1:?stamp}"
    state="$DM_DIR/$stamp"
    [[ -d "$state" ]] || { echo "STATUS=FAIL no deadman state $stamp"; exit 1; }
    if [[ -f "$state/cancelled" ]]; then
      echo "deadman already cancelled — no restore"
      echo "STATUS=OK"
      exit 0
    fi
    echo "=== DEADMAN FIRE stamp=$stamp $(date -u +%Y-%m-%dT%H:%MZ) ==="
    while read -r kind; do
      [[ -n "$kind" ]] || continue
      bak=$(ls -1dt /var/backups/k-pax-ci/config-${kind}-pre-* 2>/dev/null | head -1 || true)
      if [[ -z "$bak" || ! -f "$bak" ]]; then
        echo "FAIL no backup for kind=$kind"
        continue
      fi
      /usr/local/lib/kpax-ci/kpax-ci config-rollback "$kind" "$(basename "$bak")" || true
    done <"$state/kinds.txt"
    echo "fired" >"$state/fired"
    echo "STATUS=OK deadman-fired"
    ;;
  cancel)
    stamp="${1:-}"
    if [[ -z "$stamp" ]]; then
      if [[ -L "$DM_DIR/latest" || -d "$DM_DIR/latest" ]]; then
        stamp=$(basename "$(readlink -f "$DM_DIR/latest" 2>/dev/null || readlink "$DM_DIR/latest" 2>/dev/null || echo "")")
      fi
      if [[ -z "$stamp" ]]; then
        stamp=$(ls -1dt "$DM_DIR"/*/armed_at.txt 2>/dev/null | head -1 | xargs -r dirname | xargs -r basename || true)
      fi
    fi
    [[ -n "$stamp" && "$stamp" != "latest" ]] || { echo "STATUS=FAIL no deadman to cancel"; exit 1; }
    state="$DM_DIR/$stamp"
    mkdir -p "$state"
    date -u +%Y-%m-%dT%H:%MZ >"$state/cancelled"
    for u in $(systemctl list-units --all 'kpax-ci-deadman*' --no-legend 2>/dev/null | awk '{print $1}'); do
      systemctl stop "$u" 2>/dev/null || true
      systemctl reset-failed "$u" 2>/dev/null || true
    done
    echo "deadman cancelled stamp=$stamp"
    echo "STATUS=OK"
    ;;
  status|*)
    echo "=== deadman-status ==="
    ls -la "$DM_DIR" 2>/dev/null | head -30 || true
    for d in "$DM_DIR"/*; do
      [[ -d "$d" ]] || continue
      echo "-- $(basename "$d") --"
      cat "$d/armed_at.txt" 2>/dev/null || true
      cat "$d/kinds.txt" 2>/dev/null || true
      [[ -f "$d/cancelled" ]] && echo "cancelled=$(cat "$d/cancelled")"
      [[ -f "$d/fired" ]] && echo "fired=yes"
    done
    systemctl list-timers --all 2>/dev/null | grep -i kpax-ci-deadman || echo "no deadman timer"
    echo "STATUS=OK"
    ;;
esac
