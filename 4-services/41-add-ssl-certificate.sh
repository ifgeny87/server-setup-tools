#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Сертификат домена запрашивается один раз.
# Конфиг nginx затирается только если файла ещё нет или задан FORCE_NGINX=1.
# Файл с правками вне блока sst не трогается.

checkRoot

loghead "Получение SSL сертификата"

DOMAIN=${DOMAIN:-}
if [ -z "$DOMAIN" ]; then
    if [ -t 0 ]; then
        read -r -p "Введите один домен: " DOMAIN
    fi
fi
if [ -z "$DOMAIN" ] || [[ "$DOMAIN" == */* ]]; then
    logerr "Название домена не может быть пустым"
    exit 1
fi

CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
if [ -f "$CERT" ]; then
    logok "Сертификат уже есть: $DOMAIN"
else
    logr "Проверка получения сертификата для домена: $DOMAIN"
    if ! certbot certonly --dry-run --nginx -d "$DOMAIN"; then
        logerr "Проверка certbot не прошла: $DOMAIN"
        exit 1
    fi
    logr "Получение SSL сертификата для домена: $DOMAIN"
    if ! certbot certonly --nginx -d "$DOMAIN"; then
        logerr "Не удалось получить сертификат: $DOMAIN"
        exit 1
    fi
fi

FILE=/etc/nginx/conf.d/${DOMAIN}.conf
BLOCK_NAME="nginx-${DOMAIN}"
BEGIN="# BEGIN sst ${BLOCK_NAME}"
# Страницы ошибок подключает только 43-nginx-error-pages.sh, не этот шаблон.
BODY=$(cat <<EOF
server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_session_cache         shared:SSL:10m;
    ssl_session_timeout       10m; # default 5m
    ssl_prefer_server_ciphers on;
    ssl_certificate           /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key       /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
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
)

if [ -f "$FILE" ] && [ "${FORCE_NGINX:-}" != "1" ]; then
    current=""
    if grep -Fxq "$BEGIN" "$FILE"; then
        current=$(awk -v b="$BEGIN" -v e="# END sst ${BLOCK_NAME}" '
            $0 == b { grab = 1; next }
            $0 == e { grab = 0; next }
            grab { print }
        ' "$FILE")
    fi
    outside=$(awk -v b="$BEGIN" -v e="# END sst ${BLOCK_NAME}" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip { next }
        { print }
    ' "$FILE")
    outside_compact=$(printf '%s' "$outside" | tr -d '[:space:]')
    if [ "$current" = "$BODY" ] && [ -z "$outside_compact" ]; then
        logok "Конфиг nginx уже совпадает: $FILE"
        exit 0
    fi
    if [ -n "$outside_compact" ]; then
        logwarn "Конфиг $FILE изменён вне блока sst, не трогаю. Для замены: FORCE_NGINX=1"
    else
        logwarn "Конфиг $FILE уже есть и отличается от шаблона, не трогаю. Для замены: FORCE_NGINX=1"
    fi
    exit 0
fi
if [ -f "$FILE" ]; then
    logr "FORCE_NGINX=1, конфиг будет заменён: $FILE"
fi

logr "Создается шаблонный конфиг nginx для нового домена: $DOMAIN"
mkdir -p /etc/nginx/conf.d

BACKUP=""
if [ -f "$FILE" ]; then
    BACKUP=$(mktemp)
    cp "$FILE" "$BACKUP"
fi
{
    printf '%s\n' "$BEGIN"
    printf '%s\n' "$BODY"
    printf '%s\n' "# END sst ${BLOCK_NAME}"
} > "$FILE"
if ! nginx -t; then
    logerr "nginx -t не прошёл, конфиг $FILE не оставлен"
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" "$FILE"
    else
        rm -f "$FILE"
    fi
    rm -f ${BACKUP:+"$BACKUP"}
    exit 1
fi
rm -f ${BACKUP:+"$BACKUP"}
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
