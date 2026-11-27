#!/bin/bash
# /opt/k-pax/x-plm-pull.sh on the K-Pax server: fetch the latest encrypted X-Plm backup.
# The key on the X-Plm side is restricted to `cat /var/backups/x-plm/latest.tar.gz.enc`.
set -euo pipefail
OUT=/var/backups/x-plm
KEY=$(python3 -c 'import json; print(json.load(open("/etc/k-pax/config.json"))["ssh_key"])')
KEEP=14
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
umask 077
mkdir -p "$OUT"
FILE="$OUT/x-plm-$STAMP.tar.gz.enc"
ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/etc/k-pax/xplm_known_hosts -o ConnectTimeout=20 \
  root@45.133.209.80 backup < /dev/null > "$FILE.part"
if [ "$(head -c 8 "$FILE.part")" != "Salted__" ]; then
  rm -f "$FILE.part"
  echo "x-plm pull failed: not an encrypted archive" >&2
  exit 1
fi
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$FILE.part" -pass file:/etc/k-pax/xplm-backup.pass | tar -tzf - >/dev/null
mv "$FILE.part" "$FILE"
ls -1t "$OUT"/x-plm-*.tar.gz.enc | tail -n +$((KEEP + 1)) | xargs -r rm -f
echo "pulled $(basename "$FILE") $(stat -c %s "$FILE") bytes"
