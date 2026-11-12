#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт выполняет установку nginx и certbot, подготавливает конфиг для получения SSL сертификатов

checkRoot

CERTBOT_EMAIL=${CERTBOT_EMAIL:-}
if [ -z "$CERTBOT_EMAIL" ]; then
    if [ -t 0 ]; then
        read -r -p "Email для регистрации certbot: " CERTBOT_EMAIL
    fi
fi
if [ -z "$CERTBOT_EMAIL" ]; then
    logerr "Нужен CERTBOT_EMAIL до регистрации в certbot"
    exit 1
fi

loghead "Установка и настройка nginx и certbot"

logr "Установка nginx и certbot..."
apt-get install -yy nginx certbot python3-certbot-nginx

#logr "Создание папки для прохождения ACME квеста..."
#mkdir -p /var/www/acme
#chown -R www-data:www-data /var/www

logr "Отключение дефолтного конфига: /etc/nginx/sites-enabled/default"
rm /etc/nginx/sites-enabled/default

FILE=/etc/nginx/conf.d/default.conf
logr "Создание дефолтного конфига nginx: $FILE"
cat > $FILE <<EOF
# Location: $FILE
# Author: $(whoami)
# Created: $(timestamp)

#
# Redirect all requests from http to https
#
server {
    listen 80;
    include /etc/nginx/snippets/sst-errors.conf;

    location / {
        return 301 https://$host$request_uri;
    }
}

#
# Locking requests to unknown domains
#
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;

    include /etc/nginx/snippets/sst-errors.conf;

    ssl_certificate     /etc/nginx/ssl/default-reject.crt;
    ssl_certificate_key /etc/nginx/ssl/default-reject.key;

    return 404;
}
EOF

mkdir -p /etc/nginx/ssl /etc/nginx/snippets
if [ ! -f /etc/nginx/ssl/default-reject.crt ]; then
    logr "Создаём сертификат-заглушку для чужих доменов"
    if ! openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout /etc/nginx/ssl/default-reject.key \
        -out /etc/nginx/ssl/default-reject.crt \
        -subj "/CN=invalid" >/dev/null 2>&1; then
        logerr "Не удалось создать сертификат-заглушку"
        exit 1
    fi
fi
if [ ! -e /etc/nginx/snippets/sst-errors.conf ]; then
    : > /etc/nginx/snippets/sst-errors.conf
fi

logr "Проверяем конфиг nginx..."
if ! nginx -t; then
    logerr "nginx -t не прошёл: $FILE"
    exit 1
fi
if ! nginx -s reload; then
    logerr "Не удалось перечитать nginx"
    exit 1
fi

logr "Регистрация в certbot..."
if ! certbot register --non-interactive --agree-tos -m "$CERTBOT_EMAIL"; then
    logerr "Не удалось зарегистрировать аккаунт certbot"
    exit 1
fi

FILE=/etc/cron.daily/certbot-renew
logr "Добавление расписания для автоматического обновления сертификатов и перезапуска nginx: $FILE"
cat > $FILE <<EOF
#!/bin/bash -e
# Location: $FILE
# Author: $(whoami)
# Created: $(timestamp)
certbot renew
nginx -t
nginx -s reload
EOF
chmod +x $FILE

logok "Установка и настройка nginx + certbot завершена
----------------------------------------
Рекомендации:
 - для получения нового сертификата: ./4-services/41-add-ssl-certificate.sh
----------------------------------------
"
