#!/usr/bin/env bash
# Run ON panel as root after scp of tools/ci/wrappers.
set -euo pipefail
SRC="${1:-/tmp/kpax-ci-wrappers}"
DEST=/usr/local/lib/kpax-ci
mkdir -p "$DEST/scripts"
install -m 755 "$SRC/kpax-ci" "$DEST/kpax-ci"
cp -a "$SRC/scripts/." "$DEST/scripts/"
chmod 755 "$DEST/kpax-ci" "$DEST/scripts/"*.sh || true
chmod 644 "$DEST/scripts/"*.py || true
chown -R root:root "$DEST"
cat >/etc/sudoers.d/kpax-gha <<'EOF'
# K-Pax GitHub Actions — fixed wrappers only (do not widen)
gha ALL=(root) NOPASSWD: /usr/local/lib/kpax-ci/kpax-ci
EOF
chmod 440 /etc/sudoers.d/kpax-gha
visudo -cf /etc/sudoers.d/kpax-gha
echo "wrappers OK on $(hostname)"
sudo -u gha sudo /usr/local/lib/kpax-ci/kpax-ci diag | tail -5
