#!/usr/bin/env bash
# Thin wrapper — see config_patch.py
set -euo pipefail
exec python3 "$(dirname "$0")/config_patch.py" "$@"
