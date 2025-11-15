#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/_misc.sh" # load misc

# Скрипт выполняет установку nginx и certbot, подготавливает конфиг для получения SSL сертификатов

checkRoot

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
# Created: $(timestamp)
server {
    listen 80;

    # enable ACME challenge for SSL certs
    #location /.well-known/acme-challenge/ {
    #    root /var/www/acme;
    #}

    # redirect from http to https
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

logr "Регистрация в certbot..."
certbot register -m admin@mail.ru

FILE=/etc/cron.daily/certbot-renew
logr "Добавление расписания для автоматического обновления сертификатов и перезапуска nginx: $FILE"
cat > $FILE <<EOF
#!/bin/bash -e
# Location: $FILE
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
