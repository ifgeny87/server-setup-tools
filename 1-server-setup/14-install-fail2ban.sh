#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт установки и настройки fail2ban для SSH
# Блокировка IP после 3 неудачных попыток на 7 дней (604800 секунд)
# Порт берётся из SSH_PORT: скрипт 13 уже уводит SSH с 22.

checkRoot
loadEnv

if [ -z "${SSH_PORT:-}" ]; then
    logerr "В .env не задан SSH_PORT"
    exit 1
fi

loghead "Установка и настройка fail2ban"

if dpkg -s fail2ban >/dev/null 2>&1; then
    logok "fail2ban уже установлен"
else
    logr "Установка..."
    apt-get update -y
    apt-get install -y fail2ban
fi

logr "Настройка..."

JAIL_LOCAL="/etc/fail2ban/jail.local"

# Тот же текст при повторе не перезаписывает файл и не рестартует сервис.
sst_write_if_changed "$JAIL_LOCAL" <<EOF
[DEFAULT]
# Лог
loglevel = INFO
logtarget = /var/log/fail2ban.log

# Блокировка на 7 дней (в секундах)
bantime = 604800

# После 3 попыток
maxretry = 3

# Интервал между попытками (в секундах)
findtime = 600

# Ban через iptables
banaction = iptables-multiport

# --- SSH защита ---
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 604800
findtime = 600
EOF

systemctl enable fail2ban
if [ "$SST_FILE_CHANGED" = 1 ] || ! systemctl is-active --quiet fail2ban; then
    logr "Перезапуск fail2ban..."
    if ! systemctl restart fail2ban; then
        logerr "Не удалось перезапустить fail2ban"
        exit 1
    fi
else
    logr "jail.local совпадает, fail2ban уже активен"
fi

sleep 1
if ! systemctl is-active --quiet fail2ban; then
    logerr "fail2ban не активен после перезапуска"
    exit 1
fi
STATUS="активен"

logok "Fail2ban установлен и настроен
----------------------------------------
Защищаемый сервис: SSH
Попыток входа до блокировки: 3
Время блокировки по IP: 7 дней
Статус службы: $STATUS

Рекомендации:
 - проверить состояние: sudo fail2ban-client status sshd
 - просмотр заблокированных IP: sudo fail2ban-client status sshd | grep 'Banned IPs'
 - разблокировать IP: sudo fail2ban-client unban <IP>
----------------------------------------
"
