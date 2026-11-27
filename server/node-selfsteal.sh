#!/bin/bash
# Run on a node: Reality that looks like the node's own website (self-steal), next to the existing Reality on 443.
#   bash node-selfsteal.sh <node-id> [port] [domain]
# A local nginx serves a small site with a Let's Encrypt certificate for <domain> on 127.0.0.1:8446;
# probes that connect without the Reality key get that site, so SNI, DNS, certificate and IP all agree.
# Without <domain> the node's own <node-id>.k-pax.space is used.
set -e
NODE="$1"; PORT="${2:-2053}"; DOMAIN="${3:-$NODE.k-pax.space}"
LIVE="/etc/letsencrypt/live/$DOMAIN"
export DEBIAN_FRONTEND=noninteractive
command -v nginx >/dev/null || { apt-get update -qq >/dev/null; apt-get install -y -qq nginx >/dev/null; }
if [ ! -f "$LIVE/fullchain.pem" ]; then
  # Standalone challenge on port 80; nginx never listens there.
  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --quiet
fi
[ -f "$LIVE/fullchain.pem" ] || { echo "no certificate for $DOMAIN"; exit 1; }
cat > /etc/letsencrypt/renewal-hooks/deploy/k-pax-nginx <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/k-pax-nginx

rm -f /etc/nginx/sites-enabled/default
mkdir -p /var/www/k-pax-self
case "$DOMAIN" in
  *.k-pax.space)
    TITLE="$DOMAIN"
    BODY='<p>Сервер раздачи статических файлов. Публичных страниц здесь нет.</p><p><a href="https://k-pax.space/">k-pax.space</a></p>' ;;
  *)
    TITLE="Настолка — магазин настольных игр"
    BODY='<p>Мы готовим каталог настольных игр для компании и всей семьи: стратегии, кооперативы, игры для вечеринок.</p><p>Открытие магазина — скоро. Следите за новостями.</p>' ;;
esac
cat > /var/www/k-pax-self/index.html <<EOF
<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$TITLE</title>
<style>body{font-family:system-ui,sans-serif;max-width:640px;margin:12vh auto;padding:0 24px;color:#1e293b}a{color:#0f766e}</style>
</head><body>
<h1>$TITLE</h1>
$BODY
</body></html>
EOF
cat > /etc/nginx/sites-available/k-pax-self <<EOF
server {
    listen 127.0.0.1:8446 ssl http2;
    server_name $DOMAIN;
    ssl_certificate $LIVE/fullchain.pem;
    ssl_certificate_key $LIVE/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/k-pax-self;
    index index.html;
    access_log off;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
ln -sf /etc/nginx/sites-available/k-pax-self /etc/nginx/sites-enabled/k-pax-self
nginx -t -q
systemctl enable --now nginx >/dev/null 2>&1
systemctl reload nginx

C=/etc/sing-box/config.json
cp -a $C $C.bak-selfsteal
python3 - "$DOMAIN" "$PORT" <<'PY'
import json, sys, copy
domain, port = sys.argv[1], int(sys.argv[2])
path = "/etc/sing-box/config.json"
cfg = json.load(open(path))
base = next(i for i in cfg["inbounds"] if i.get("tag") == "vless-reality")
cfg["inbounds"] = [i for i in cfg["inbounds"] if i.get("tag") != "vless-reality-self"]
self_in = copy.deepcopy(base)
self_in["tag"] = "vless-reality-self"
self_in["listen_port"] = port
self_in["tls"]["server_name"] = domain
self_in["tls"]["reality"]["handshake"] = {"server": "127.0.0.1", "server_port": 8446}
at = cfg["inbounds"].index(base) + 1
cfg["inbounds"].insert(at, self_in)
json.dump(cfg, open(path + ".new", "w"), indent=2)
print("self-steal inbound: port", port, "sni", domain, "users", len(self_in.get("users", [])))
PY
sing-box check -c $C.new || { rm -f $C.new; exit 1; }
chown --reference=$C $C.new; chmod --reference=$C $C.new
mv $C.new $C
ufw allow $PORT/tcp >/dev/null
systemctl restart sing-box
sleep 2
echo "sing-box $(systemctl is-active sing-box) | nginx $(systemctl is-active nginx) | listening $PORT: $(ss -tln | grep -c ":$PORT ")"
# certbot renews in standalone mode on port 80; nginx must not hold it.
if ss -tln | grep -qE ':80 '; then echo "WARNING: port 80 is busy: $(ss -tlnp | grep -E ':80 ' | head -1)"; else echo "port 80 free for certbot"; fi
