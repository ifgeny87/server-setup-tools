#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# Настройка iptables и ip6tables с учётом Docker и автозапуском через systemd.
# Повтор собирает тот же filter и подменяет таблицу целиком, без второго -A.
# INPUT и FORWARD получают политику DROP. Чужие цепочки filter, кроме правил этого скрипта, сохраняются.
# Ответы DNS проходят как established. Отдельный вход с source-port 53 не открывается.
# IPv6 закрывается тем же входом, если ядро его не выключило. Форвард скрипта 42 включается только после DROP на FORWARD.
# Ответ проброса после снятия DNAT/SNAT идёт на порт клиента, поэтому в FORWARD нужно RELATED,ESTABLISHED.
# Правило в DOCKER-USER этого не заменяет: переход туда добавляет Docker, а этот скрипт часто выполняется раньше.

# Собирает таблицу filter IPv4. На stdin — нормализованный iptables-save -t filter.
# Правила печатаются по цепочкам, как iptables-save, чтобы повтор не вызывал restore.
# limit-burst 5 и log-level 4 не пишем: это значения по умолчанию, save их опускает.
build_v4_filter() {
    local ssh=$1 docker=$2
    awk -v ssh="$ssh" -v docker="$docker" '
        BEGIN { nc = 0; nr = 0; nf = 0; seen_du = 0; seen_input = 0; seen_forward = 0 }
        /^#/ || /^COMMIT$/ || /^\*/ { next }
        /^:/ {
            name = $1
            if (name == ":INPUT") {
                chain[++nc] = ":INPUT DROP [0:0]"
                seen_input = 1
            } else if (name == ":FORWARD") {
                chain[++nc] = ":FORWARD DROP [0:0]"
                seen_forward = 1
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
        /^-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT$/ { next }
        /^-A DOCKER-USER / && $0 ~ /--ctstate RELATED,ESTABLISHED/ && $0 ~ /-j ACCEPT$/ { next }
        { rule[++nr] = $0; next }
        END {
            if (!seen_input) chain[++nc] = ":INPUT DROP [0:0]"
            if (!seen_forward) chain[++nc] = ":FORWARD DROP [0:0]"
            if (docker == "yes" && !seen_du) chain[++nc] = ":DOCKER-USER - [0:0]"
            add[++na] = "-A INPUT -i lo -j ACCEPT"
            add[++na] = "-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
            add[++na] = "-A INPUT -p tcp -m tcp --dport " ssh " -j ACCEPT"
            add[++na] = "-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT"
            add[++na] = "-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT"
            add[++na] = "-A INPUT -m limit --limit 5/min -j LOG --log-prefix \"FIREWALL DROP: \""
            add[++na] = "-A INPUT -j DROP"
            add[++na] = "-A OUTPUT -p udp -m udp --dport 53 -j ACCEPT"
            add[++na] = "-A OUTPUT -p tcp -m tcp --dport 53 -j ACCEPT"
            if (docker == "yes") {
                add[++na] = "-A FORWARD -i docker0 -j ACCEPT"
                add[++na] = "-A FORWARD -o docker0 -j ACCEPT"
                add[++na] = "-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
            }
            print "*filter"
            for (i = 1; i <= nc; i++) print chain[i]
            for (i = 1; i <= nc; i++) {
                cname = chain[i]
                sub(/^:/, "", cname)
                sub(/ .*/, "", cname)
                if (cname == "FORWARD") print "-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
                for (j = 1; j <= nf; j++) {
                    split(f2b[j], parts, " ")
                    if (parts[2] == cname) print f2b[j]
                }
                for (j = 1; j <= nr; j++) {
                    split(rule[j], parts, " ")
                    if (parts[2] == cname) print rule[j]
                }
                for (j = 1; j <= na; j++) {
                    split(add[j], parts, " ")
                    if (parts[2] == cname) print add[j]
                }
            }
            print "COMMIT"
        }
    '
}

# Собирает таблицу filter IPv6. Типы 1–4 — ошибки доставки, 133–136 — neighbor discovery.
# Echo request не принимается. Source-port 53 не добавляется.
# Порядок цепочек совпадает с ip6tables-save. Лимит лога — как у IPv4.
build_v6_filter() {
    local ssh=$1
    awk -v ssh="$ssh" '
        BEGIN { nc = 0; nr = 0; nf = 0; seen_input = 0 }
        /^#/ || /^COMMIT$/ || /^\*/ { next }
        /^:/ {
            name = $1
            if (name == ":INPUT") {
                chain[++nc] = ":INPUT DROP [0:0]"
                seen_input = 1
            } else {
                chain[++nc] = $0
            }
            next
        }
        /^-A INPUT / && $0 ~ /-j f2b-/ { f2b[++nf] = $0; next }
        /^-A INPUT / { next }
        { rule[++nr] = $0; next }
        END {
            if (!seen_input) chain[++nc] = ":INPUT DROP [0:0]"
            add[++na] = "-A INPUT -i lo -j ACCEPT"
            add[++na] = "-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
            add[++na] = "-A INPUT -p tcp -m tcp --dport " ssh " -j ACCEPT"
            add[++na] = "-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT"
            add[++na] = "-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT"
            add[++na] = "-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 1 -j ACCEPT"
            add[++na] = "-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 2 -j ACCEPT"
            add[++na] = "-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 3 -j ACCEPT"
            add[++na] = "-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 4 -j ACCEPT"
            add[++na] = "-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 133 -j ACCEPT"
            add[++na] = "-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 134 -j ACCEPT"
            add[++na] = "-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 135 -j ACCEPT"
            add[++na] = "-A INPUT -p ipv6-icmp -m icmp6 --icmpv6-type 136 -j ACCEPT"
            add[++na] = "-A INPUT -m limit --limit 5/min -j LOG --log-prefix \"FIREWALL DROP: \""
            add[++na] = "-A INPUT -j DROP"
            print "*filter"
            for (i = 1; i <= nc; i++) print chain[i]
            for (i = 1; i <= nc; i++) {
                cname = chain[i]
                sub(/^:/, "", cname)
                sub(/ .*/, "", cname)
                for (j = 1; j <= nf; j++) {
                    split(f2b[j], parts, " ")
                    if (parts[2] == cname) print f2b[j]
                }
                for (j = 1; j <= nr; j++) {
                    split(rule[j], parts, " ")
                    if (parts[2] == cname) print rule[j]
                }
                for (j = 1; j <= na; j++) {
                    split(add[j], parts, " ")
                    if (parts[2] == cname) print add[j]
                }
            }
            print "COMMIT"
        }
    '
}

# 0 — ядро отдаёт IPv6. 1 — каталога нет или disable_ipv6 включён.
ipv6_kernel_on() {
    local flag
    [ -d /proc/sys/net/ipv6 ] || return 1
    if [ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        flag=$(tr -d '[:space:]' < /proc/sys/net/ipv6/conf/all/disable_ipv6)
        [ "$flag" = 0 ] || return 1
    fi
    return 0
}

main() {
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

    ipv6_on=no
    if ipv6_kernel_on; then
        if ! command -v ip6tables >/dev/null 2>&1 || ! command -v ip6tables-save >/dev/null 2>&1 || ! command -v ip6tables-restore >/dev/null 2>&1; then
            logerr "IPv6 включён, а ip6tables не установлен"
            exit 1
        fi
        ipv6_on=yes
    else
        logr "IPv6 в ядре выключен, правила ip6tables пропущены"
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
    build_v4_filter "$SSH_PORT" "$docker_flag" < "$CURRENT" > "$BUILT"

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

    if [ "$ipv6_on" = yes ]; then
        CURRENT6=$(mktemp)
        BUILT6=$(mktemp)
        RAW6=$(mktemp)
        if ! ip6tables-save -t filter > "$RAW6"; then
            logerr "ip6tables-save не прочитал таблицу filter"
            rm -f "$CURRENT6" "$BUILT6" "$RAW6"
            exit 1
        fi
        sed -E 's/\[[0-9]+:[0-9]+\]/[0:0]/' "$RAW6" | grep -vE '^#' > "$CURRENT6" || true
        rm -f "$RAW6"
        build_v6_filter "$SSH_PORT" < "$CURRENT6" > "$BUILT6"
        if cmp -s "$CURRENT6" "$BUILT6"; then
            logr "Правила filter IPv6 уже совпадают"
        else
            logr "Применяем правила ip6tables"
            if ! ip6tables-restore < "$BUILT6"; then
                logerr "ip6tables-restore не применил правила"
                rm -f "$CURRENT6" "$BUILT6"
                exit 1
            fi
        fi
        rm -f "$CURRENT6" "$BUILT6"
    fi

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

    if [ "$ipv6_on" = yes ]; then
        LIVE6=$(mktemp)
        ip6tables-save | sed -E 's/\[[0-9]+:[0-9]+\]/[0:0]/' | grep -vE '^#' > "$LIVE6"
        SAVED6=/etc/iptables/rules.v6
        if [ -f "$SAVED6" ] && sed -E 's/\[[0-9]+:[0-9]+\]/[0:0]/' "$SAVED6" | grep -vE '^#' | cmp -s - "$LIVE6"; then
            logr "Файл правил уже совпадает: $SAVED6"
        else
            logr "Сохраняем правила IPv6"
            ip6tables-save > "$SAVED6"
        fi
        rm -f "$LIVE6"
        if [ -x /usr/sbin/ip6tables-restore ]; then
            V6_RESTORE=/usr/sbin/ip6tables-restore
        else
            V6_RESTORE=$(command -v ip6tables-restore)
        fi
    fi

    SERVICE_FILE=/etc/systemd/system/secure-firewall.service
    if [ "$ipv6_on" = yes ]; then
        sst_write_if_changed "$SERVICE_FILE" <<EOF
[Unit]
Description=Secure Firewall Rules with Docker support
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables-restore /etc/iptables/rules.v4
ExecStart=${V6_RESTORE} /etc/iptables/rules.v6
ExecReload=/usr/sbin/iptables-restore /etc/iptables/rules.v4
ExecReload=${V6_RESTORE} /etc/iptables/rules.v6
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    else
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
    fi

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
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
