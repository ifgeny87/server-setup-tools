#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт выполняет получение нового сертификата в два этапа:
# - dry-run проверка получения сертификата
# - получение сертификата
# После получения сертификата будет создан шаблонный nginx конфиг для этого сертификата

checkRoot

loghead "Получение SSL сертификата"

DOMAIN=${DOMAIN:-}
if [ -z "$DOMAIN" ]; then
    read -p "Введите один домен: " DOMAIN
fi
if [ -z "$DOMAIN" ]; then
    logerr "Название домена не может быть пустым"
    exit 1
fi

logr "Проверка получения сертификата для домена: $DOMAIN"
certbot certonly --dry-run --nginx -d "$DOMAIN"

logr "Получение SSL сертификата для домена: $DOMAIN"
certbot certonly --nginx -d "$DOMAIN"

logr "Создается шаблонный конфиг nginx для нового домена: $DOMAIN"
FILE=/etc/nginx/conf.d/${DOMAIN}.conf
mkdir -p /etc/nginx/snippets
if [ ! -e /etc/nginx/snippets/sst-errors.conf ]; then
    : > /etc/nginx/snippets/sst-errors.conf
fi
TMP=$(mktemp)
cat > "$TMP" <<EOF
# Location: $FILE
# Author: $(whoami)
# Created: $(timestamp)
server {
    listen 443 ssl;
    server_name $DOMAIN;

    include /etc/nginx/snippets/sst-errors.conf;

    ssl_session_cache         shared:SSL:10m;
    ssl_session_timeout       10m; # default 5m
    ssl_prefer_server_ciphers on;
    ssl_certificate           /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key       /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols             TLSv1.2 TLSv1.3;
    ssl_ciphers               RC4:HIGH:!aNULL:!MD5:!kEDH;

    fastcgi_read_timeout  30;
    proxy_connect_timeout 30;
    proxy_send_timeout    30;
    proxy_read_timeout    30;
    send_timeout          30;

    client_max_body_size 10m;

    access_log on;
    error_log on;

    location ~ \/\.(ht|sv|git) {
        deny all;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Request \$uri;
        proxy_set_header X-Result-All \$uri\$is_args\$args;
        proxy_pass       http://127.0.0.1:8080;
    }
}
EOF
BACKUP=""
if [ -f "$FILE" ]; then
    BACKUP=$(mktemp)
    cp "$FILE" "$BACKUP"
fi
cp "$TMP" "$FILE"
if ! nginx -t; then
    logerr "nginx -t не прошёл, конфиг $FILE не оставлен"
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" "$FILE"
    else
        rm -f "$FILE"
    fi
    rm -f "$TMP" ${BACKUP:+"$BACKUP"}
    exit 1
fi
rm -f "$TMP" ${BACKUP:+"$BACKUP"}
if ! nginx -s reload; then
    logerr "Не удалось перечитать nginx"
    exit 1
fi

logok "Получение SSL сертификата завершено
----------------------------------------
Создан файл конфигурации nginx: $FILE
Рекомендации:
 - рекомендуется проверить конфигурацю nginx вручную: $FILE
 - тест конфигурации: nginx -t
 - применение новой конфигурации: nginx -s reload
----------------------------------------
"
