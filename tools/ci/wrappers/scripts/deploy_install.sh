#!/usr/bin/env bash
# Install allowlisted staged files from /tmp/kpax-ci-stage into panel dir.
# Usage: kpax-ci deploy-install <stamp> <basename.py> [more.py...]
set -euo pipefail
stamp="${1:?stamp}"
shift
panel=$(bash "$(dirname "$0")/panel_locate.sh" | head -1)
dir=$(dirname "$panel")
mkdir -p /var/backups/k-pax-ci
cp -a "$dir" "/var/backups/k-pax-ci/pre-deploy-${stamp}"
for base in "$@"; do
  case "$base" in
    *.py) ;;
    *) echo "STATUS=FAIL refuse non-py $base"; exit 2 ;;
  esac
  [[ "$base" == */* || "$base" == .* ]] && { echo "STATUS=FAIL bad name"; exit 2; }
  src="/tmp/kpax-ci-stage/$base"
  [[ -f "$src" ]] || { echo "STATUS=FAIL missing $src"; exit 1; }
  install -m 644 "$src" "$dir/$base"
  rm -f "$src"
  echo "installed $base -> $dir/$base"
done
echo "STATUS=OK deploy-install stamp=$stamp dir=$dir"
