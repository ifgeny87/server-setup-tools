#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт выполняет установку nginx и certbot, подготавливает конфиг для получения SSL сертификатов.
# default.conf принадлежит скрипту: один блок sst. Совпавший текст nginx не перечитывает.

checkRoot

loghead "Установка и настройка nginx и certbot"

need_install=0
for pkg in nginx certbot python3-certbot-nginx; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        need_install=1
    fi
done
if [ "$need_install" -eq 0 ]; then
    logok "nginx и certbot уже установлены"
else
    logr "Установка nginx и certbot..."
    apt-get install -yy nginx certbot python3-certbot-nginx
fi

logr "Отключение дефолтного конфига: /etc/nginx/sites-enabled/default"
rm -f /etc/nginx/sites-enabled/default

FILE=/etc/nginx/conf.d/default.conf
logr "Проверяем дефолтный конфиг nginx: $FILE"
# Страницы ошибок подключает только 4-services/43-nginx-error-pages.sh.
DESIRED=$(cat <<EOF
# BEGIN sst nginx-default
server {
    listen 80;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;

    ssl_certificate     /etc/nginx/ssl/default-reject.crt;
    ssl_certificate_key /etc/nginx/ssl/default-reject.key;

    return 404;
}
# END sst nginx-default
EOF
)

mkdir -p /etc/nginx/ssl /etc/nginx/conf.d
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

BACKUP=$(mktemp)
had_file=0
if [ -f "$FILE" ]; then
    cp "$FILE" "$BACKUP"
    had_file=1
fi
sst_write_if_changed "$FILE" <<EOF
$DESIRED
EOF
if ! nginx -t; then
    logerr "nginx -t не прошёл: $FILE"
    if [ "$SST_FILE_CHANGED" = 1 ]; then
        if [ "$had_file" -eq 1 ]; then
            cat "$BACKUP" > "$FILE"
        else
            rm -f "$FILE"
        fi
    fi
    rm -f "$BACKUP"
    exit 1
fi
rm -f "$BACKUP"
if [ "$SST_FILE_CHANGED" = 1 ]; then
    if ! nginx -s reload; then
        logerr "Не удалось перечитать nginx"
        exit 1
    fi
else
    logr "Конфиг nginx уже совпадает, reload не нужен"
fi

if certbot show_account >/dev/null 2>&1; then
    logok "Аккаунт certbot уже есть"
else
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
    logr "Регистрация в certbot..."
    if ! certbot register --non-interactive --agree-tos -m "$CERTBOT_EMAIL"; then
        logerr "Не удалось зарегистрировать аккаунт certbot"
        exit 1
    fi
fi

CRON=/etc/cron.daily/certbot-renew
if [ -f "$CRON" ] && grep -qx 'certbot renew' "$CRON" && grep -qx 'nginx -s reload' "$CRON"; then
    logr "Расписание certbot уже есть: $CRON"
else
    logr "Добавление расписания для автоматического обновления сертификатов и перезапуска nginx: $CRON"
    cat > "$CRON" <<EOF
#!/bin/bash -e
# Location: $CRON
certbot renew
nginx -t
nginx -s reload
EOF
    chmod +x "$CRON"
fi

logok "Установка и настройка nginx + certbot завершена
----------------------------------------
Рекомендации:
 - для получения нового сертификата: ./4-services/41-add-ssl-certificate.sh
----------------------------------------
"
