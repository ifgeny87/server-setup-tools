#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт установки и настройки fail2ban для SSH
# Блокировка IP после 3 неудачных попыток на 7 дней (604800 секунд)

loghead "Установка и настройка fail2ban"

logr "Установка..."
apt-get update -y
apt-get install -y fail2ban

logr "Настройка..."

# Основная директория
JAIL_LOCAL="/etc/fail2ban/jail.local"

# Резервная копия, если файл уже есть
if [ -f "$JAIL_LOCAL" ]; then
  cp "$JAIL_LOCAL" "$JAIL_LOCAL.bak.$(date +%F_%H-%M-%S)"
  logok "Резервная копия jail.local создана"
fi

# Настраиваем fail2ban для SSH
cat > "$JAIL_LOCAL" <<EOF
[DEFAULT]
# Отправка писем (можно отключить)
destemail = root@localhost
sender = fail2ban@localhost
mta = sendmail

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
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 604800
findtime = 600
EOF

logr "Активация автозапуска и перезапуск fail2ban..."
systemctl enable fail2ban
systemctl restart fail2ban

# Проверка статуса
sleep 1
systemctl is-active --quiet fail2ban && STATUS="активен" || STATUS="не запущен"

logok "Fail2ban установлен и настроен.
  - Защищаемый сервис: SSH
  - Попыток входа до блокировки: 3
  - Время блокировки: 7 дней
  - Статус службы: $STATUS

Проверить состояние:
  sudo fail2ban-client status sshd

Просмотр заблокированных IP:
  sudo fail2ban-client status sshd | grep 'Banned IPs'

Разблокировать IP:
  sudo fail2ban-client unban <IP>"
