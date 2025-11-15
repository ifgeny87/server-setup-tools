#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Настройка iptables-файервола с учётом Docker и автозапуском через systemd
# Работает на Ubuntu (20.04+, 22.04+)

loadEnv

# Проверка обязательных переменных
if [ -z "$SSH_PORT" ] ; then
    logerr "Не задана переменная окружения: SSH_PORT"
    exit 1
fi

loghead "Настройка Firewall"

# Создаём цепочку DOCKER-USER, если не существует
iptables -N DOCKER-USER || true
iptables -F DOCKER-USER

# --- Основные правила ---
logr "Применяем правила iptables"
# Разрешаем уже установленные соединения
iptables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Разрешаем порты: SSH, HTTP, HTTPS
iptables -F INPUT
# Разрешаем loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
# (чтобы можно было обращаться к внешним DNS-серверам)
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Логирование попыток на другие порты (в syslog)
iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "FIREWALL DROP: " --log-level 4

# Всё остальное дропаем
iptables -A INPUT -j DROP

# Разрешаем форвардинг Docker контейнеров
iptables -I FORWARD -o docker0 -j ACCEPT
iptables -I FORWARD -i docker0 -j ACCEPT

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
