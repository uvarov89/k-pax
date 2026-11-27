#!/bin/bash
# /usr/local/sbin/x-plm-backup on the X-Plm server: encrypted daily archive of configs and mailboxes.
set -euo pipefail
OUT=/var/backups/x-plm
PASS=/etc/x-plm/backup.pass
KEEP=7
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
umask 077
mkdir -p "$OUT"
TMP=$(mktemp -d /var/backups/x-plm-tmp.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
PATHS=(
  /etc/caddy /var/www/x-plm
  /etc/postfix /etc/dovecot /etc/opendkim /etc/opendkim.conf /etc/x-plm
  /etc/postsrsd.conf /etc/postsrsd.secret /etc/default/postsrsd
  /etc/ssh/sshd_config.d /etc/fail2ban/jail.d /etc/ufw /etc/apt/apt.conf.d/20auto-upgrades
  /etc/systemd/system/x-plm-certsync.service /etc/systemd/system/x-plm-certsync.timer
  /etc/systemd/system/x-plm-backup.service /etc/systemd/system/x-plm-backup.timer
  /usr/local/bin/x-plm-certsync /usr/local/sbin/x-plm-backup
  /var/mail/vhosts
)
EXISTING=()
for p in "${PATHS[@]}"; do [ -e "$p" ] && EXISTING+=("$p"); done
tar -C / -czf "$TMP/x-plm.tar.gz" "${EXISTING[@]/#\//}"
openssl enc -e -aes-256-cbc -pbkdf2 -iter 200000 -salt -in "$TMP/x-plm.tar.gz" -out "$TMP/x-plm.enc" -pass "file:$PASS"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$TMP/x-plm.enc" -pass "file:$PASS" | tar -tzf - >/dev/null
NAME="x-plm-$STAMP.tar.gz.enc"
mv "$TMP/x-plm.enc" "$OUT/$NAME"
ln -sfn "$OUT/$NAME" "$OUT/latest.tar.gz.enc"
ls -1t "$OUT"/x-plm-*.tar.gz.enc | tail -n +$((KEEP + 1)) | xargs -r rm -f
echo "backup $NAME $(stat -c %s "$OUT/$NAME") bytes, files=$(tar -tzf "$TMP/x-plm.tar.gz" | wc -l)"
