#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Настройка iptables-файервола с учётом Docker и автозапуском через systemd.
# Повтор собирает тот же filter и подменяет таблицу целиком, без второго -A.
# INPUT получает политику DROP. Чужие цепочки filter, кроме правил этого скрипта, сохраняются.

checkRoot
loadEnv

if [ -z "$SSH_PORT" ] ; then
    logerr "Не задана переменная окружения: SSH_PORT"
    exit 1
fi

loghead "Настройка Firewall"

if dpkg -s iptables-persistent >/dev/null 2>&1; then
    logok "iptables-persistent уже установлен"
else
    logr "Установка iptables-persistent"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -yy iptables-persistent
fi

if ! command -v iptables >/dev/null 2>&1 || ! command -v iptables-save >/dev/null 2>&1; then
    logerr "iptables не установлен"
    exit 1
fi

if ip link show docker0 >/dev/null 2>&1; then
    docker_flag=yes
    logr "Интерфейс docker0 есть, правила Docker войдут в набор"
else
    docker_flag=no
    logwarn "Интерфейс docker0 не найден, правила Docker пропущены"
fi

CURRENT=$(mktemp)
BUILT=$(mktemp)
RAW=$(mktemp)
if ! iptables-save -t filter > "$RAW"; then
    logerr "iptables-save не прочитал таблицу filter"
    rm -f "$CURRENT" "$BUILT" "$RAW"
    exit 1
fi
sed -E 's/\[[0-9]+:[0-9]+\]/[0:0]/' "$RAW" | grep -vE '^#' > "$CURRENT" || true
rm -f "$RAW"
awk -v ssh="$SSH_PORT" -v docker="$docker_flag" '
    BEGIN { nc = 0; nr = 0; nf = 0; seen_du = 0; seen_input = 0 }
    /^#/ || /^COMMIT$/ || /^\*/ { next }
    /^:/ {
        name = $1
        if (name == ":INPUT") {
            chain[++nc] = ":INPUT DROP [0:0]"
            seen_input = 1
        } else {
            if (name == ":DOCKER-USER") seen_du = 1
            chain[++nc] = $0
        }
        next
    }
    /^-A INPUT / && $0 ~ /-j f2b-/ { f2b[++nf] = $0; next }
    /^-A INPUT / { next }
    /^-A OUTPUT / && $0 ~ /--dport 53 / && $0 ~ /-j ACCEPT$/ { next }
    docker == "yes" && /^-A FORWARD / && $0 ~ /docker0/ && $0 ~ /-j ACCEPT$/ { next }
    /^-A DOCKER-USER / && $0 ~ /--ctstate RELATED,ESTABLISHED/ && $0 ~ /-j ACCEPT$/ { next }
    { rule[++nr] = $0; next }
    END {
        if (!seen_input) chain[++nc] = ":INPUT DROP [0:0]"
        print "*filter"
        for (i = 1; i <= nc; i++) print chain[i]
        if (docker == "yes" && !seen_du) print ":DOCKER-USER - [0:0]"
        for (i = 1; i <= nr; i++) print rule[i]
        for (i = 1; i <= nf; i++) print f2b[i]
        print "-A INPUT -i lo -j ACCEPT"
        print "-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
        print "-A INPUT -p tcp -m tcp --dport " ssh " -j ACCEPT"
        print "-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT"
        print "-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT"
        print "-A INPUT -p udp -m udp --sport 53 -j ACCEPT"
        print "-A INPUT -p tcp -m tcp --sport 53 -j ACCEPT"
        print "-A INPUT -m limit --limit 5/min --limit-burst 5 -j LOG --log-prefix \"FIREWALL DROP: \" --log-level 4"
        print "-A INPUT -j DROP"
        print "-A OUTPUT -p udp -m udp --dport 53 -j ACCEPT"
        print "-A OUTPUT -p tcp -m tcp --dport 53 -j ACCEPT"
        if (docker == "yes") {
            print "-A FORWARD -i docker0 -j ACCEPT"
            print "-A FORWARD -o docker0 -j ACCEPT"
            print "-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
        }
        print "COMMIT"
    }
' "$CURRENT" > "$BUILT"

if cmp -s "$CURRENT" "$BUILT"; then
    logr "Правила filter уже совпадают"
else
    logr "Применяем правила iptables"
    if ! iptables-restore < "$BUILT"; then
        logerr "iptables-restore не применил правила"
        rm -f "$CURRENT" "$BUILT"
        exit 1
    fi
fi
rm -f "$CURRENT" "$BUILT"

if dpkg -s fail2ban >/dev/null 2>&1; then
    if ! iptables -S INPUT | grep -q -- '-j f2b-'; then
        logr "Перезапускаем fail2ban, чтобы вернуть его цепочки в INPUT"
        if ! systemctl restart fail2ban; then
            logerr "Не удалось перезапустить fail2ban после правил iptables"
            exit 1
        fi
    else
        logr "Цепочки fail2ban в INPUT уже есть"
    fi
fi

mkdir -p /etc/iptables/
LIVE=$(mktemp)
iptables-save | sed -E 's/\[[0-9]+:[0-9]+\]/[0:0]/' | grep -vE '^#' > "$LIVE"
SAVED=/etc/iptables/rules.v4
if [ -f "$SAVED" ] && sed -E 's/\[[0-9]+:[0-9]+\]/[0:0]/' "$SAVED" | grep -vE '^#' | cmp -s - "$LIVE"; then
    logr "Файл правил уже совпадает: $SAVED"
else
    logr "Сохраняем правила"
    if command -v netfilter-persistent >/dev/null 2>&1; then
        if ! netfilter-persistent save; then
            iptables-save > "$SAVED"
        fi
    else
        iptables-save > "$SAVED"
    fi
fi
rm -f "$LIVE"

SERVICE_FILE=/etc/systemd/system/secure-firewall.service
sst_write_if_changed "$SERVICE_FILE" <<EOF
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

if [ "$SST_FILE_CHANGED" = 1 ]; then
    logr "Обновляем автозапуск"
    systemctl daemon-reload
fi
if ! systemctl is-enabled --quiet secure-firewall.service; then
    systemctl enable secure-firewall.service
fi
if ! systemctl is-active --quiet secure-firewall.service; then
    systemctl start secure-firewall.service
fi

logok "Файервол настроен, автозапуск активен"
