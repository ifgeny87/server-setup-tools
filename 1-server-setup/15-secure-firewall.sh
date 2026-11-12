#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Настройка iptables-файервола с учётом Docker и автозапуском через systemd
# Работает на Ubuntu (20.04+, 22.04+)

checkRoot
loadEnv

# Проверка обязательных переменных
if [ -z "$SSH_PORT" ] ; then
    logerr "Не задана переменная окружения: SSH_PORT"
    exit 1
fi

loghead "Настройка Firewall"

# --- Основные правила ---
logr "Применяем правила iptables"
iptables -F INPUT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "FIREWALL DROP: " --log-level 4
iptables -A INPUT -j DROP

if ip link show docker0 >/dev/null 2>&1; then
    logr "Интерфейс docker0 есть, добавляем правила Docker"
    iptables -N DOCKER-USER 2>/dev/null || true
    iptables -F DOCKER-USER
    iptables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -I FORWARD -o docker0 -j ACCEPT
    iptables -I FORWARD -i docker0 -j ACCEPT
else
    logwarn "Интерфейс docker0 не найден, правила Docker пропущены"
fi

if dpkg -s fail2ban >/dev/null 2>&1; then
    logr "Перезапускаем fail2ban, чтобы вернуть его цепочки в INPUT"
    if ! systemctl restart fail2ban; then
        logerr "Не удалось перезапустить fail2ban после правил iptables"
        exit 1
    fi
fi

# Сохраняем правила
logr "Сохраняем правила"
apt-get update -y
apt-get install -yy iptables-persistent
mkdir -p /etc/iptables/
netfilter-persistent save || iptables-save > /etc/iptables/rules.v4

# Создаём systemd unit
logr "Настраиваем автозапуск"

SERVICE_FILE=/etc/systemd/system/secure-firewall.service

cat > $SERVICE_FILE <<EOF
[Unit]
Description=Secure Firewall Rules with Docker support
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables-restore /etc/iptables/rules.v4
ExecReload=/usr/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable secure-firewall.service
systemctl start secure-firewall.service

logok "Файервол настроен, автозапуск активен"
