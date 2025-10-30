#!/bin/bash

DOMAIN="qoq.digital"
EMAIL="k3kermanych@gmail.com"

echo "=== Generating initial nginx config (HTTP only) ==="
cat > nginx.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files \$uri \$uri.html \$uri/ =404;
    }
}
EOF

echo "=== Starting nginx with HTTP-only config ==="
docker-compose up -d nginx

echo "=== Waiting for nginx to start ==="
sleep 7

echo "=== Obtaining SSL certificate ==="
docker-compose run --rm certbot certonly --webroot \
    --webroot-path=/var/www/certbot \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    -d $DOMAIN \
    -d www.$DOMAIN

if [ $? -ne 0 ]; then
    echo "Failed to obtain certificate"
    exit 1
fi

echo "=== Generating production nginx config (HTTPS) ==="
cat > nginx.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files \$uri \$uri/ \$uri.html /index.html =404;
    }
}
EOF

echo "=== Reloading nginx with HTTPS config ==="
docker-compose exec nginx nginx -s reload

echo "=== Setting up auto-renewal cron ==="
cat > renew-certs.sh << 'RENEW'
#!/bin/bash
docker-compose run --rm certbot renew
if [ $? -eq 0 ]; then
    docker-compose exec nginx nginx -s reload
fi
RENEW

chmod +x renew-certs.sh

echo "=== Setup complete! ==="
echo "Add this to crontab (crontab -e):"
echo "0 3 * * * cd $(pwd) && ./renew-certs.sh >> /var/log/certbot-renew.log 2>&1"