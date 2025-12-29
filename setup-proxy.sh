#!/bin/bash
set -e

echo "=== Installation des dépendances ==="
apt update -y
apt install -y nginx jq curl unzip

echo "=== Création des répertoires ==="
mkdir -p /opt/saxo-proxy
mkdir -p /opt/saxo-proxy/scripts
mkdir -p /opt/saxo-proxy/logs

echo "=== Chargement du fichier .env ==="
if [ ! -f /opt/saxo-proxy/.env ]; then
    echo "ERREUR : Le fichier /opt/saxo-proxy/.env est manquant."
    echo "Copiez env.example vers .env et remplissez vos valeurs Saxo."
    exit 1
fi

source /opt/saxo-proxy/.env

echo "=== Installation du script de refresh token ==="
cat << 'EOF' > /opt/saxo-proxy/scripts/refresh_token.sh
#!/bin/bash
source /opt/saxo-proxy/.env

RESPONSE=$(curl -s -X POST "https://sim.logonvalidation.net/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "refresh_token=$REFRESH_TOKEN" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET")

ACCESS_TOKEN=$(echo $RESPONSE | jq -r '.access_token')

if [ "$ACCESS_TOKEN" != "null" ]; then
  echo $ACCESS_TOKEN > /opt/saxo-proxy/logs/access_token.txt
fi
EOF

chmod +x /opt/saxo-proxy/scripts/refresh_token.sh

echo "=== Installation du cron ==="
cat << 'EOF' > /etc/cron.d/saxo-refresh
*/10 * * * * root /opt/saxo-proxy/scripts/refresh_token.sh >> /opt/saxo-proxy/logs/cron.log 2>&1
EOF

chmod 644 /etc/cron.d/saxo-refresh
systemctl restart cron

echo "=== Configuration NGINX ==="
cat << 'EOF' > /etc/nginx/sites-available/saxo-proxy
server {
    listen 80;
    server_name _;

    location /saxo-proxy/ {
        proxy_pass https://gateway.saxobank.com/sim/openapi/;
        proxy_set_header Authorization "Bearer $(cat /opt/saxo-proxy/logs/access_token.txt)";
        proxy_set_header Host gateway.saxobank.com;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -sf /etc/nginx/sites-available/saxo-proxy /etc/nginx/sites-enabled/saxo-proxy
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl restart nginx

echo "=== Installation terminée ==="
echo "Proxy opérationnel sur : http://<IP_DE_TA_VM>/saxo-proxy/"

