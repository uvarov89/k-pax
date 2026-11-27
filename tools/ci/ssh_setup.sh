#!/usr/bin/env bash
# Prepare ~/.ssh for GHA from secrets. Never echo private key.
set -euo pipefail
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
printf '%s\n' "$KPAX_DEPLOY_SSH_KEY" > "$HOME/.ssh/id_ed25519"
chmod 600 "$HOME/.ssh/id_ed25519"
printf '%s\n' "$KPAX_DEPLOY_SSH_KNOWN_HOSTS" > "$HOME/.ssh/known_hosts"
chmod 644 "$HOME/.ssh/known_hosts"
# normalize Windows-ish newlines if pasted
sed -i 's/\r$//' "$HOME/.ssh/id_ed25519" "$HOME/.ssh/known_hosts" || true
ssh-keygen -y -f "$HOME/.ssh/id_ed25519" >/dev/null
echo "SSH key material loaded (fingerprint only):"
ssh-keygen -lf "$HOME/.ssh/id_ed25519"
