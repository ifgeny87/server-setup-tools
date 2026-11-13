#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# Отчёт о безопасности сервера. Без --fix только читает систему.
# --fix CODE меняет её лишь у кодов, которым это разрешено тикетом SRV-035.
# В пресеты батча скрипт не входит.

REPO=$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
AUDIT_ENV=${AUDIT_ENV:-/root/.env}
AUDIT_SYSCTL=${AUDIT_SYSCTL:-/etc/sysctl.d/99-sst-audit.conf}
AUDIT_RULES=${AUDIT_RULES:-/etc/iptables/rules.v4}
SSH_PORT=""
SS_OUT=""
SS_STATE=missing
AUDIT_TMP=""

# code|fix|текст для справки. fix=yes — --fix может изменить систему.
catalog() {
    cat <<'EOF'
AUD-I-OS|no|ОС, ядро и uptime
AUD-I-DISK|no|df по место и inode, без tmpfs и devtmpfs
AUD-I-MOUNT|no|точки монтирования
AUD-I-PKG|no|установленные пакеты и версии
AUD-I-PROC|no|запущенные сервисы или процессы
AUD-I-PORT|no|слушающие сокеты
AUD-I-RES|no|нагрузка, память и swap
AUD-I-DOCKER|no|контейнеры и образы, если docker есть
AUD-I-LOG|no|размеры /var/log и journal
AUD-I-SUDO|no|учётки в группе sudo
AUD-PKG-GHOST|no|пакет установлен, а файлов нет
AUD-PKG-ALIEN|no|порт слушает бинарь вне пакетов
AUD-BIN-PATH|no|sshd, sudo или iptables не из /usr/bin и /usr/sbin
AUD-P-22|yes|tcp 22 снаружи; фикс только если это sshd и SSH_PORT не 22
AUD-P-23|no|tcp 23 telnet снаружи
AUD-P-21|no|tcp 21 FTP снаружи
AUD-P-69|no|udp 69 TFTP снаружи
AUD-P-25|no|tcp 25 SMTP снаружи
AUD-P-110|no|tcp 110 POP3 снаружи
AUD-P-143|no|tcp 143 IMAP снаружи
AUD-P-139|no|tcp 139 NetBIOS снаружи
AUD-P-445|no|tcp 445 SMB снаружи
AUD-P-111|no|tcp или udp 111 RPC снаружи
AUD-P-161|no|udp 161 SNMP снаружи
AUD-P-389|no|tcp 389 LDAP снаружи
AUD-P-1433|no|tcp 1433 снаружи
AUD-P-3306|no|tcp 3306 MySQL снаружи
AUD-P-5432|no|tcp 5432 Postgres снаружи
AUD-P-6379|no|tcp 6379 Redis снаружи
AUD-P-27017|no|tcp 27017 Mongo снаружи
AUD-P-11211|no|tcp 11211 Memcached снаружи
AUD-P-9200|no|tcp 9200 Elasticsearch снаружи
AUD-P-2375|no|tcp 2375 Docker без TLS снаружи
AUD-P-3389|no|tcp 3389 RDP снаружи
AUD-P-5900|no|tcp 5900 VNC снаружи
AUD-P-6443|no|tcp 6443 API Kubernetes снаружи
AUD-P-10250|no|tcp 10250 kubelet снаружи
AUD-P-10000|no|tcp 10000 Webmin снаружи
AUD-P-3128|no|tcp 3128 прокси снаружи
AUD-P-1883|no|tcp 1883 MQTT снаружи
AUD-P-5601|no|tcp 5601 Kibana снаружи
AUD-P-465|no|tcp 465 приём почты снаружи
AUD-P-587|no|tcp 587 приём почты снаружи
AUD-P-2376|no|tcp 2376 Docker с TLS снаружи
AUD-P-8080|no|tcp 8080 снаружи
AUD-P-9090|no|tcp 9090 снаружи
AUD-MAIL|yes|почтовые пакеты; фикс — скрипт 11
AUD-SSH-PASS|yes|пароль без ключа; фикс — скрипт 13
AUD-SSH-ROOT|yes|вход root по SSH; фикс — скрипт 13
AUD-SSH-PORT|yes|Port не совпадает с SSH_PORT; фикс — скрипт 13, если SSH_PORT задан
AUD-SSH-EMPTY|no|пустой пароль у учётки с оболочкой входа
AUD-SSH-UID0|no|больше одной учётки с uid 0
AUD-F2B|yes|jail sshd не активен; фикс — скрипт 14
AUD-FW-INPUT|yes|политика INPUT не DROP; фикс — скрипт 15
AUD-FW-SSH|yes|нет ACCEPT на SSH_PORT; фикс — скрипт 15
AUD-FW-LOG|yes|нет лога FIREWALL DROP; фикс — скрипт 15
AUD-FW-V6|yes|IPv6 открыт; фикс — скрипт 15
AUD-FW-SPORT53|yes|во входе есть source-port 53; фикс — скрипт 15
AUD-FW-FWD|yes|ip_forward включён при FORWARD ACCEPT; фикс — скрипт 15
AUD-FW-SAVE|no|rules.v4 нет или он расходится с живым filter
AUD-DISK-USE|no|место на диске: предупреждение от 80%, критично от 90%
AUD-DISK-INODE|no|inode: те же пороги
AUD-MNT-STICKY|yes|у /tmp нет sticky; фикс — chmod +t /tmp
AUD-LOG-BIG|no|файл в /var/log больше 500 МБ, файл не удаляется
AUD-JRN-BIG|yes|journal больше 1 ГБ; фикс — vacuum до 200 МБ
AUD-RES-LOAD|no|load за минуту больше двух чисел ядер
AUD-RES-MEM|no|доступной памяти меньше 10%
AUD-RES-SWAP|no|swap занят больше чем наполовину при нехватке памяти
AUD-RES-ZOMBIE|no|есть процессы-зомби
AUD-SYS-FAILED|no|юниты в состоянии failed
AUD-SYS-REBOOT|no|система просит перезагрузку
AUD-SYS-TIME|yes|время не синхронизировано; фикс включает NTP
AUD-SYS-ASLR|yes|randomize_va_space не 2
AUD-SYS-REDIR|yes|accept_redirects не 0
AUD-SYS-RP|yes|rp_filter не 1
AUD-SYS-SYN|yes|tcp_syncookies не 1
AUD-SYS-SRC|yes|accept_source_route не 0
AUD-UPD|no|обновления из кармана security, пакеты не ставятся
AUD-ENV-MODE|yes|режим /root/.env шире 600; фикс — chmod 600
AUD-AUTH-KEY|yes|authorized_keys доступен не только владельцу
AUD-ETC-WW|no|файл в /etc доступен на запись остальным
AUD-CRON-WW|yes|cron доступен на запись группе или остальным
AUD-HOME-WW|yes|домашний каталог доступен на запись остальным
AUD-SUDO-NOPASS|no|в sudoers есть NOPASSWD
AUD-DK-PRIV|no|контейнер Privileged, скрипт его не останавливает
AUD-DK-SOCK|no|в контейнер смонтирован docker.sock
AUD-DK-LATEST|no|образ с тегом latest
AUD-DK-DANGLE|yes|висячие образы; фикс — docker image prune -f
AUD-DK-PRUNE|yes|нет cron очистки образов; фикс — скрипт 23
AUD-NGX-TOK|no|у nginx нет server_tokens off, файл не переписывается
AUD-NGX-OLD|no|в конфиге nginx старый TLS или RC4, файл не переписывается
EOF
}

is_root() {
    [ "$(id -u)" -eq 0 ]
}

code_known() {
    catalog | awk -F'|' -v c="$1" '$1 == c { found = 1 } END { exit !found }'
}

code_fixable() {
    catalog | awk -F'|' -v c="$1" '$1 == c && $2 == "yes" { found = 1 } END { exit !found }'
}

code_hint() {
    catalog | awk -F'|' -v c="$1" '$1 == c { print $3; exit }'
}

rank_of() {
    case "$1" in
        crit) printf '3' ;;
        warn) printf '2' ;;
        ok) printf '1' ;;
        *) printf '0' ;;
    esac
}

# Цвет кода в отчёте. В файл и при NO_COLOR переменные цвета пустые.
audit_color() {
    case "$1" in
        crit) printf '%s' "$COL_RED" ;;
        warn) printf '%s' "$COL_FG_YELLOW" ;;
        ok) printf '%s' "$COL_LIME" ;;
        info) printf '%s' "$COL_FG_BLUE" ;;
        *) printf '%s' "$COL_FG_GRAY" ;;
    esac
}

prepare_tmp() {
    if [ -z "$AUDIT_TMP" ]; then
        AUDIT_TMP=$(mktemp -d)
        trap 'rm -rf "$AUDIT_TMP"' EXIT
    fi
    rm -rf "$AUDIT_TMP/r"
    mkdir -p "$AUDIT_TMP/r"
}

# Оставляет худший уровень по коду: crit выше warn, warn выше ok.
set_result() {
    local level=$1 code=$2 fact=$3 action=${4:-}
    local path="$AUDIT_TMP/r/$code" old
    if [ -f "$path" ]; then
        old=$(awk 'NR == 1 { print; exit }' "$path")
        [ "$(rank_of "$level")" -gt "$(rank_of "$old")" ] || return 0
    fi
    printf '%s\n%s\n%s\n' "$level" "$fact" "$action" > "$path"
}

result_level() {
    local path="$AUDIT_TMP/r/$1"
    if [ ! -f "$path" ]; then
        printf 'none'
        return 0
    fi
    awk 'NR == 1 { print; exit }' "$path"
}

file_mode() {
    local m
    if m=$(stat -c '%a' "$1" 2>/dev/null); then
        printf '%s' "$m"
        return 0
    fi
    stat -f '%OLp' "$1"
}

# Лишние биты сверх 600: группа, остальные или исполнение у владельца.
mode_too_wide() {
    local m=$((8#$1))
    [ $((m & ~0600)) -ne 0 ]
}

mode_world_or_group_write() {
    local m=$((8#$1))
    [ $((m & 022)) -ne 0 ]
}

read_ssh_port() {
    local env="$REPO/.env" line
    SSH_PORT=""
    [ -f "$env" ] || return 0
    line=$(awk -F= '/^[[:space:]]*SSH_PORT=/ { print substr($0, index($0, "=") + 1); exit }' "$env")
    line=${line//$'\r'/}
    line=${line#\"}
    line=${line%\"}
    line=${line#\'}
    line=${line%\'}
    SSH_PORT=$line
}

capture_ss() {
    SS_OUT=""
    SS_STATE=missing
    if ! command -v ss >/dev/null 2>&1; then
        return 1
    fi
    if SS_OUT=$(ss -H -lntup 2>/dev/null || ss -H -lntu 2>/dev/null); then
        SS_STATE=ok
        return 0
    fi
    SS_OUT=""
    SS_STATE=fail
    return 1
}

# Печатает: протокол порт loop|public процесс
listeners() {
    [ -n "$SS_OUT" ] || return 0
    printf '%s\n' "$SS_OUT" | awk '
        $1 != "tcp" && $1 != "udp" { next }
        {
            loc = $5
            n = split(loc, a, ":")
            port = a[n]
            addr = a[1]
            for (i = 2; i < n; i++) addr = addr ":" a[i]
            scope = "public"
            if (addr ~ /^127\./ || addr == "::1" || addr == "[::1]") scope = "loop"
            proc = ""
            if (match($0, /users:\(\("[^"]+/)) {
                proc = substr($0, RSTART, RLENGTH)
                sub(/.*\(\("/, "", proc)
            }
            print $1, port, scope, proc
        }
    '
}

port_scope() {
    local proto=$1 port=$2 scope line p pr po sc
    scope=none
    while read -r pr po sc _; do
        [ "$po" = "$port" ] || continue
        case ",$proto," in
            *,"$pr",*) ;;
            *) continue ;;
        esac
        if [ "$sc" = public ]; then
            printf 'public'
            return 0
        fi
        scope=loop
    done <<EOF
$(listeners)
EOF
    printf '%s' "$scope"
}

port_proc() {
    local proto=$1 port=$2 pr po sc proc
    while read -r pr po sc proc; do
        [ "$po" = "$port" ] || continue
        [ "$sc" = public ] || continue
        case ",$proto," in
            *,"$pr",*) ;;
            *) continue ;;
        esac
        [ -n "$proc" ] || continue
        printf '%s' "$proc"
        return 0
    done <<EOF
$(listeners)
EOF
}

ipv6_kernel_on() {
    [ -d /proc/sys/net/ipv6 ] || return 1
    if [ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        [ "$(tr -d '[:space:]' < /proc/sys/net/ipv6/conf/all/disable_ipv6)" = 0 ] || return 1
    fi
    return 0
}

run_project_script() {
    bash "$REPO/$1"
}

warn_ssh_drop() {
    logwarn "Сейчас может смениться порт SSH. Текущая сессия оборвётся. Пароль пользователя уже должен быть задан."
}

warn_fw_drop() {
    logwarn "Сессия оборвётся, если её порт не входит в новые правила файрвола."
}

collect_info() {
    local os kern up disks mounts pkgs procs ports res docker logs sudos
    if [ -r /etc/os-release ]; then
        os=$(awk -F= '/^PRETTY_NAME=/ { gsub(/"/, "", $2); print $2; exit }' /etc/os-release)
    else
        os="os-release нет"
    fi
    kern=$(uname -sr 2>/dev/null || echo "ядро не прочитано")
    up=$(uptime 2>/dev/null || echo "uptime нет")
    set_result info AUD-I-OS "$os; $kern; $up"

    if disks=$(df -hP 2>/dev/null); then
        disks=$(printf '%s\n' "$disks" | awk 'NR == 1 || ($1 != "tmpfs" && $1 != "devtmpfs")')
    else
        disks="df нет"
    fi
    if mounts=$(df -iP 2>/dev/null); then
        mounts=$(printf '%s\n' "$mounts" | awk 'NR == 1 || ($1 != "tmpfs" && $1 != "devtmpfs")')
        disks="$disks | inode: $(printf '%s' "$mounts" | tr '\n' '; ')"
    fi
    set_result info AUD-I-DISK "$disks"

    if command -v findmnt >/dev/null 2>&1; then
        mounts=$(findmnt -rno TARGET,FSTYPE,OPTIONS 2>/dev/null | tr '\n' '; ')
    else
        mounts="findmnt нет"
    fi
    set_result info AUD-I-MOUNT "$mounts"

    if command -v dpkg-query >/dev/null 2>&1; then
        pkgs=$(dpkg-query -W -f '${Package} ${Version}\n' 2>/dev/null || true)
        [ -n "$pkgs" ] || pkgs="список пакетов пуст"
    else
        pkgs="dpkg нет"
    fi
    set_result info AUD-I-PKG "$pkgs"

    if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --state=running --no-legend >/dev/null 2>&1; then
        procs=$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | awk '{ print $1 }' | tr '\n' ' ')
    elif command -v ps >/dev/null 2>&1; then
        procs=$(ps -axo comm= 2>/dev/null | sort -u | tr '\n' ' ' || true)
        [ -n "$procs" ] || procs="список процессов не прочитан"
    else
        procs="список процессов не прочитан"
    fi
    set_result info AUD-I-PROC "$procs"

    if [ -n "$SS_OUT" ]; then
        ports=$(printf '%s' "$SS_OUT" | tr '\n' '; ')
    else
        ports="ss нет"
    fi
    set_result info AUD-I-PORT "$ports"

    res="load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo нет)"
    res="$res nproc=$(nproc 2>/dev/null || echo нет)"
    if [ -r /proc/meminfo ]; then
        res="$res $(awk '/^MemTotal:|^MemAvailable:|^SwapTotal:|^SwapFree:/ { printf "%s=%s%s ", $1, $2, $3 }' /proc/meminfo)"
    else
        res="$res meminfo нет"
    fi
    set_result info AUD-I-RES "$res"

    if ! command -v docker >/dev/null 2>&1; then
        docker="docker не установлен"
    elif docker=$(docker ps --format '{{.ID}} {{.Image}} {{.Status}}' 2>/dev/null); then
        docker="ps: ${docker:-пусто}; images: $(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | tr '\n' ' ')"
    else
        docker="docker не ответил"
    fi
    set_result info AUD-I-DOCKER "$docker"

    if [ -d /var/log ]; then
        logs=$(find /var/log -xdev -type f -exec du -k {} + 2>/dev/null | sort -n | tail -n 5 | tr '\n' '; ')
        [ -n "$logs" ] || logs="файлов нет"
    else
        logs="/var/log нет"
    fi
    if command -v journalctl >/dev/null 2>&1; then
        logs="$logs journal: $(journalctl --disk-usage 2>/dev/null || echo не прочитан)"
    fi
    set_result info AUD-I-LOG "$logs"

    if [ -r /etc/group ]; then
        sudos=$(awk -F: '$1 == "sudo" || $1 == "wheel" { print $4 }' /etc/group | tr '\n' ' ')
        [ -n "$sudos" ] || sudos="группа пуста"
    else
        sudos="группа sudo не прочитана"
    fi
    set_result info AUD-I-SUDO "$sudos"
}

check_ports() {
    local code proto port level title scope proc action
    if [ "$SS_STATE" = missing ]; then
        set_result warn AUD-P-22 "не проверено" "нет ss"
        return 0
    fi
    if [ "$SS_STATE" != ok ]; then
        set_result warn AUD-P-22 "нет прав" "запустите скрипт от root"
        return 0
    fi
    while read -r code proto port level title; do
        [ -n "$code" ] || continue
        scope=$(port_scope "$proto" "$port")
        if [ "$scope" = public ]; then
            proc=$(port_proc "$proto" "$port")
            action="закройте службу $title"
            if [ "$code" = AUD-P-22 ]; then
                action="1-server-setup/13-ssh-restrict.sh"
                [ -n "$proc" ] && action="$action (процесс $proc)"
            fi
            if [ "$level" = crit ]; then
                set_result crit "$code" "$title слушает снаружи, порт $port${proc:+, процесс $proc}" "$action"
            else
                set_result warn "$code" "$title слушает снаружи, порт $port${proc:+, процесс $proc}" "$action"
            fi
        elif [ "$scope" = loop ] && [ "$code" != AUD-P-22 ]; then
            set_result ok "$code" "слушает только петлю, порт $port"
        fi
    done <<'EOF'
AUD-P-22 tcp 22 crit SSH
AUD-P-23 tcp 23 crit telnet
AUD-P-21 tcp 21 crit FTP
AUD-P-69 udp 69 crit TFTP
AUD-P-25 tcp 25 crit SMTP
AUD-P-110 tcp 110 crit POP3
AUD-P-143 tcp 143 crit IMAP
AUD-P-139 tcp 139 crit NetBIOS
AUD-P-445 tcp 445 crit SMB
AUD-P-111 tcp,udp 111 crit RPC
AUD-P-161 udp 161 crit SNMP
AUD-P-389 tcp 389 crit LDAP
AUD-P-1433 tcp 1433 crit MSSQL
AUD-P-3306 tcp 3306 crit MySQL
AUD-P-5432 tcp 5432 crit Postgres
AUD-P-6379 tcp 6379 crit Redis
AUD-P-27017 tcp 27017 crit Mongo
AUD-P-11211 tcp 11211 crit Memcached
AUD-P-9200 tcp 9200 crit Elasticsearch
AUD-P-2375 tcp 2375 crit Docker
AUD-P-3389 tcp 3389 crit RDP
AUD-P-5900 tcp 5900 crit VNC
AUD-P-6443 tcp 6443 crit Kubernetes
AUD-P-10250 tcp 10250 crit kubelet
AUD-P-10000 tcp 10000 crit Webmin
AUD-P-3128 tcp 3128 crit proxy
AUD-P-1883 tcp 1883 crit MQTT
AUD-P-5601 tcp 5601 crit Kibana
AUD-P-465 tcp 465 warn submission
AUD-P-587 tcp 587 warn submission
AUD-P-2376 tcp 2376 warn Docker-TLS
AUD-P-8080 tcp 8080 warn HTTP-alt
AUD-P-9090 tcp 9090 warn 9090
EOF
    if [ "$(result_level AUD-P-22)" = none ]; then
        if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != 22 ] && [ "$(port_scope tcp "$SSH_PORT")" != none ]; then
            set_result ok AUD-P-22 "порт 22 закрыт снаружи, слушается SSH_PORT $SSH_PORT"
        fi
    fi
}

check_packages() {
    local pkg bad alien line pr po sc proc exe
    if ! command -v dpkg-query >/dev/null 2>&1; then
        set_result warn AUD-PKG-GHOST "не проверено" "нет dpkg"
        set_result warn AUD-PKG-ALIEN "не проверено" "нет dpkg"
        return 0
    fi
    bad=""
    for pkg in openssh-server sudo iptables nginx fail2ban docker-ce; do
        dpkg-query -W -f '${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' || continue
        line=$(dpkg -V "$pkg" 2>/dev/null | awk '/missing/ { print }' || true)
        [ -n "$line" ] && bad="$bad $pkg"
    done
    if [ -n "$bad" ]; then
        set_result crit AUD-PKG-GHOST "нет файлов у пакетов:$bad" "переустановите пакет"
    else
        set_result ok AUD-PKG-GHOST "у проверяемых пакетов нет пропавших файлов"
    fi
    if [ -z "$SS_OUT" ] || ! printf '%s\n' "$SS_OUT" | grep -q 'users:'; then
        set_result warn AUD-PKG-ALIEN "не проверено" "ss не показал процессы"
        return 0
    fi
    if [ ! -d /proc ]; then
        set_result warn AUD-PKG-ALIEN "не проверено" "нет /proc"
        return 0
    fi
    alien=$(printf '%s\n' "$SS_OUT" | awk '
        /users:\(\("/ {
            line = $0
            if (match(line, /pid=[0-9]+/)) {
                pid = substr(line, RSTART + 4, RLENGTH - 4)
                cmd = "readlink /proc/" pid "/exe 2>/dev/null"
                cmd | getline exe
                close(cmd)
                if (exe != "") print exe
            }
        }
    ' || true)
    bad=""
    if [ -z "$alien" ]; then
        set_result warn AUD-PKG-ALIEN "не проверено" "исполняемый файл процесса не прочитан"
        return 0
    fi
    while read -r exe; do
        [ -n "$exe" ] || continue
        if ! dpkg -S "$exe" >/dev/null 2>&1; then
            bad="$bad $exe"
        fi
    done <<EOF
$alien
EOF
    if [ -n "$bad" ]; then
        set_result warn AUD-PKG-ALIEN "бинарь не из пакета:$bad"
    else
        set_result ok AUD-PKG-ALIEN "слушающие бинари принадлежат пакетам"
    fi
}

check_bin_path() {
    local cmd path bad="" seen=0
    for cmd in sshd sudo iptables; do
        path=$(command -v "$cmd" 2>/dev/null || true)
        [ -n "$path" ] || continue
        seen=1
        case "$path" in
            /usr/bin/*|/usr/sbin/*) ;;
            *) bad="$bad $cmd=$path" ;;
        esac
    done
    if [ "$seen" -eq 0 ]; then
        set_result warn AUD-BIN-PATH "не проверено" "команды не найдены"
    elif [ -n "$bad" ]; then
        set_result crit AUD-BIN-PATH "путь вне /usr/bin и /usr/sbin:$bad"
    else
        set_result ok AUD-BIN-PATH "sshd, sudo и iptables в системных каталогах"
    fi
}

check_mail() {
    local pkg installed="" listen=0 name
    if ! command -v dpkg-query >/dev/null 2>&1; then
        set_result warn AUD-MAIL "не проверено" "нет dpkg"
        return 0
    fi
    for pkg in postfix exim4 sendmail mailutils cyrus-imap dovecot; do
        if dpkg-query -W -f '${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
            installed="$installed $pkg"
        fi
    done
    if [ -z "$installed" ]; then
        set_result ok AUD-MAIL "почтовые пакеты не установлены"
        return 0
    fi
    for name in 25 110 143 465 587; do
        [ "$(port_scope tcp "$name")" = public ] && listen=1
    done
    if printf '%s\n' "$SS_OUT" | grep -Eq 'postfix|exim|sendmail|dovecot|master'; then
        listen=1
    fi
    if [ "$listen" -eq 1 ]; then
        set_result crit AUD-MAIL "почтовый пакет слушает порт:$installed" "1-server-setup/11-remove-mail-server.sh"
    else
        set_result warn AUD-MAIL "почтовый пакет установлен:$installed" "1-server-setup/11-remove-mail-server.sh"
    fi
}

sshd_value() {
    local key=$1 dump=$2
    awk -v k="$key" 'BEGIN { key = tolower(k) } tolower($1) == key { val = $2; for (i = 3; i <= NF; i++) val = val " " $i } END { print val }' "$dump"
}

check_ssh() {
    local dump port permit pass methods
    dump=$(mktemp)
    if sshd -T > "$dump" 2>/dev/null; then
        :
    elif [ -r /etc/ssh/sshd_config ]; then
        awk '
            /^[[:space:]]*($|#)/ { next }
            { key = tolower($1); val = $2; for (i = 3; i <= NF; i++) val = val " " $i; v[key] = val }
            END {
                if (!("port" in v)) v["port"] = "22"
                print "port", v["port"]
                print "permitrootlogin", v["permitrootlogin"]
                print "passwordauthentication", v["passwordauthentication"]
                print "authenticationmethods", v["authenticationmethods"]
            }
        ' /etc/ssh/sshd_config > "$dump"
    else
        rm -f "$dump"
        set_result warn AUD-SSH-PASS "нет прав" "запустите скрипт от root"
        set_result warn AUD-SSH-ROOT "нет прав" "запустите скрипт от root"
        set_result warn AUD-SSH-PORT "нет прав" "запустите скрипт от root"
        check_accounts
        return 0
    fi
    port=$(sshd_value port "$dump")
    permit=$(sshd_value permitrootlogin "$dump")
    pass=$(sshd_value passwordauthentication "$dump")
    methods=$(sshd_value authenticationmethods "$dump")
    rm -f "$dump"
    [ -n "$port" ] || port=22
    [ -n "$pass" ] || pass=yes
    if [ "$pass" = yes ] && ! printf '%s' "$methods" | grep -q 'publickey,password'; then
        set_result crit AUD-SSH-PASS "вход по паролю возможен без ключа" "1-server-setup/13-ssh-restrict.sh"
    else
        set_result ok AUD-SSH-PASS "вход только по ключу или ключ вместе с паролем"
    fi
    if [ "$permit" = no ]; then
        set_result ok AUD-SSH-ROOT "PermitRootLogin no"
    else
        set_result crit AUD-SSH-ROOT "PermitRootLogin ${permit:-не no}" "1-server-setup/13-ssh-restrict.sh"
    fi
    if [ -z "$SSH_PORT" ]; then
        set_result warn AUD-SSH-PORT "SSH_PORT не задан, сравнить нельзя" "задайте SSH_PORT в .env"
    elif [ "$port" = "$SSH_PORT" ]; then
        set_result ok AUD-SSH-PORT "Port совпадает с SSH_PORT $SSH_PORT"
    else
        set_result crit AUD-SSH-PORT "Port $port, в .env SSH_PORT $SSH_PORT" "1-server-setup/13-ssh-restrict.sh"
    fi
    check_accounts
}

check_accounts() {
    local empty extra
    if [ ! -r /etc/passwd ]; then
        set_result warn AUD-SSH-UID0 "нет прав" "запустите скрипт от root"
        set_result warn AUD-SSH-EMPTY "нет прав" "запустите скрипт от root"
        return 0
    fi
    extra=$(awk -F: '$3 == 0 { print $1 }' /etc/passwd)
    if [ "$(printf '%s\n' "$extra" | grep -c .)" -gt 1 ]; then
        set_result crit AUD-SSH-UID0 "uid 0 у: $(printf '%s' "$extra" | tr '\n' ' ')"
    else
        set_result ok AUD-SSH-UID0 "uid 0 только у одной учётки"
    fi
    if [ ! -r /etc/shadow ]; then
        set_result warn AUD-SSH-EMPTY "нет прав" "запустите скрипт от root"
        return 0
    fi
    empty=$(awk -F: '
        NR == FNR {
            if ($7 ~ /(nologin|false|sync|halt|shutdown)$/ || $7 == "") next
            login[$1] = 1
            next
        }
        $2 == "" && ($1 in login) { print $1 }
    ' /etc/passwd /etc/shadow)
    if [ -n "$empty" ]; then
        set_result crit AUD-SSH-EMPTY "пустой пароль: $(printf '%s' "$empty" | tr '\n' ' ')" "задайте пароль вручную, скрипт его не придумывает"
    else
        set_result ok AUD-SSH-EMPTY "пустых паролей нет"
    fi
}

check_f2b() {
    if command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client status sshd >/dev/null 2>&1; then
        set_result ok AUD-F2B "jail sshd активен"
    else
        set_result warn AUD-F2B "jail sshd не активен" "1-server-setup/14-install-fail2ban.sh"
    fi
}

check_firewall() {
    local rules="" policy fwd
    if ! command -v iptables >/dev/null 2>&1 || ! rules=$(iptables -S 2>/dev/null); then
        set_result warn AUD-FW-INPUT "нет прав" "запустите скрипт от root"
        set_result warn AUD-FW-SSH "нет прав" "запустите скрипт от root"
        set_result warn AUD-FW-LOG "нет прав" "запустите скрипт от root"
        set_result warn AUD-FW-SPORT53 "нет прав" "запустите скрипт от root"
        set_result warn AUD-FW-FWD "нет прав" "запустите скрипт от root"
        set_result warn AUD-FW-SAVE "нет прав" "запустите скрипт от root"
    else
        if printf '%s\n' "$rules" | grep -qx -- '-P INPUT DROP'; then
            set_result ok AUD-FW-INPUT "политика INPUT DROP"
        else
            set_result crit AUD-FW-INPUT "политика INPUT не DROP" "1-server-setup/15-secure-firewall.sh"
        fi
        if [ -z "$SSH_PORT" ]; then
            set_result warn AUD-FW-SSH "SSH_PORT не задан" "задайте SSH_PORT и выполните скрипт 15"
        elif printf '%s\n' "$rules" | grep -E -- '-A INPUT ' | grep -q -- "--dport $SSH_PORT " && printf '%s\n' "$rules" | grep -E -- "-A INPUT .*(--dport $SSH_PORT ).*-j ACCEPT"; then
            set_result ok AUD-FW-SSH "есть ACCEPT на tcp $SSH_PORT"
        else
            set_result crit AUD-FW-SSH "нет ACCEPT на tcp $SSH_PORT" "1-server-setup/15-secure-firewall.sh"
        fi
        if printf '%s\n' "$rules" | grep -q 'FIREWALL DROP'; then
            set_result ok AUD-FW-LOG "есть лог FIREWALL DROP"
        else
            set_result warn AUD-FW-LOG "нет лога FIREWALL DROP, монитор 4-services/40-firewall-monitor.sh ничего не увидит" "1-server-setup/15-secure-firewall.sh"
        fi
        if printf '%s\n' "$rules" | grep -E -- '-A INPUT ' | grep -q -- '--sport 53'; then
            set_result crit AUD-FW-SPORT53 "во входе есть source-port 53" "1-server-setup/15-secure-firewall.sh"
        else
            set_result ok AUD-FW-SPORT53 "source-port 53 во входе нет"
        fi
        fwd=0
        if [ -r /proc/sys/net/ipv4/ip_forward ]; then
            fwd=$(tr -d '[:space:]' < /proc/sys/net/ipv4/ip_forward)
        fi
        policy=$(printf '%s\n' "$rules" | awk '/^-P FORWARD / { print $3; exit }')
        if [ "$fwd" != 1 ]; then
            set_result ok AUD-FW-FWD "пересылка IPv4 выключена"
        elif [ "$policy" = DROP ]; then
            set_result ok AUD-FW-FWD "ip_forward включён, политика FORWARD DROP"
        else
            set_result crit AUD-FW-FWD "ip_forward=$fwd, политика FORWARD ${policy:-не DROP}" "1-server-setup/15-secure-firewall.sh"
        fi
        check_fw_save "$rules"
    fi
    if ! ipv6_kernel_on; then
        set_result ok AUD-FW-V6 "IPv6 в ядре выключен"
    elif command -v ip6tables >/dev/null 2>&1 && rules=$(ip6tables -S 2>/dev/null); then
        if printf '%s\n' "$rules" | grep -qx -- '-P INPUT DROP'; then
            set_result ok AUD-FW-V6 "политика ip6tables INPUT DROP"
        else
            set_result crit AUD-FW-V6 "политика ip6tables INPUT не DROP" "1-server-setup/15-secure-firewall.sh"
        fi
    else
        set_result warn AUD-FW-V6 "нет прав" "запустите скрипт от root"
    fi
}

fw_sig() {
    awk '
        /^\*filter/ { on = 1 }
        /^\*/ && !/^\*filter/ { on = 0 }
        on && (/^-P / || /--dport / || /--sport /) { print }
    '
}

check_fw_save() {
    local rules=$1 live file diff
    if [ ! -f "$AUDIT_RULES" ]; then
        set_result warn AUD-FW-SAVE "нет файла $AUDIT_RULES" "живой filter может быть новее файла, --fix его не пишет"
        return 0
    fi
    if ! command -v iptables-save >/dev/null 2>&1 || ! live=$(iptables-save -t filter 2>/dev/null); then
        set_result warn AUD-FW-SAVE "нет прав" "запустите скрипт от root"
        return 0
    fi
    live=$(printf '%s\n' "$live" | fw_sig)
    file=$(fw_sig < "$AUDIT_RULES")
    if [ "$live" = "$file" ]; then
        set_result ok AUD-FW-SAVE "политика и порты rules.v4 совпадают с живым filter"
        return 0
    fi
    diff=$(diff -u <(printf '%s\n' "$file") <(printf '%s\n' "$live") | tr '\n' ' ' || true)
    set_result warn AUD-FW-SAVE "расходятся политика или порты. Файл против живого: $diff" "файл может быть старее живых правил, --fix его не переписывает"
}

disk_percents() {
    # Печатает «процент точка» для df. $1 — аргументы df одной строкой.
    # shellcheck disable=SC2086
    df $1 2>/dev/null | awk '
        NR == 1 {
            for (i = 1; i <= NF; i++) if ($i == "Use%" || $i == "IUse%" || $i == "Capacity") col = i
            next
        }
        $1 == "tmpfs" || $1 == "devtmpfs" { next }
        col > 0 && $col ~ /%$/ {
            gsub(/%/, "", $col)
            print $col, $NF
        }
    '
}

check_disk_kind() {
    local code=$1 args=$2 rows worst=0 level=ok fact="" pct mnt
    if ! rows=$(disk_percents "$args"); then
        set_result warn "$code" "не проверено" "df не выполнился"
        return 0
    fi
    [ -n "$rows" ] || {
        set_result warn "$code" "не проверено" "df не показал файловых систем"
        return 0
    }
    while read -r pct mnt; do
        [ "$pct" -ge "$worst" ] && worst=$pct
        if [ "$pct" -ge 90 ]; then
            level=crit
            fact="$fact $mnt:${pct}%"
        elif [ "$pct" -ge 80 ] && [ "$level" != crit ]; then
            level=warn
            fact="$fact $mnt:${pct}%"
        fi
    done <<EOF
$rows
EOF
    if [ "$level" = ok ]; then
        set_result ok "$code" "ниже 80%, максимум ${worst}%"
    elif [ "$level" = crit ]; then
        set_result crit "$code" "занято от 90%:$fact" "место скрипт не чистит"
    else
        set_result warn "$code" "занято от 80%:$fact" "место скрипт не чистит"
    fi
}

check_resources() {
    local load cores mem_tot mem_av swap_tot swap_free zombies big journal unit
    check_disk_kind AUD-DISK-USE "-hP"
    check_disk_kind AUD-DISK-INODE "-iP"
    if [ -d /tmp ]; then
        if mode_too_wide_sticky; then
            set_result crit AUD-MNT-STICKY "у /tmp нет sticky-бита" "chmod +t /tmp"
        else
            set_result ok AUD-MNT-STICKY "у /tmp есть sticky-бит"
        fi
    else
        set_result warn AUD-MNT-STICKY "не проверено" "нет /tmp"
    fi
    if [ -d /var/log ]; then
        big=$(find /var/log -xdev -type f -size +500M 2>/dev/null || true)
        if [ -n "$big" ]; then
            set_result warn AUD-LOG-BIG "больше 500 МБ: $(printf '%s' "$big" | tr '\n' ' ')" "файл не удаляется и не обнуляется"
        else
            set_result ok AUD-LOG-BIG "в /var/log нет файлов больше 500 МБ"
        fi
    else
        set_result warn AUD-LOG-BIG "не проверено" "нет /var/log"
    fi
    if command -v journalctl >/dev/null 2>&1 && journal=$(journalctl --disk-usage 2>/dev/null); then
        if printf '%s' "$journal" | awk '
            match($0, /[0-9.]+[KMGT]/) {
                s = substr($0, RSTART, RLENGTH)
                n = s + 0
                u = substr(s, length(s), 1)
                mb = n
                if (u == "G") mb = n * 1024
                if (u == "T") mb = n * 1024 * 1024
                if (u == "K") mb = n / 1024
                exit (mb > 1024 ? 0 : 1)
            }
            END { if (NR && !RSTART) exit 1 }
        '; then
            set_result warn AUD-JRN-BIG "$journal" "journalctl --vacuum-size=200M"
        else
            set_result ok AUD-JRN-BIG "journal не больше 1 ГБ"
        fi
    else
        set_result warn AUD-JRN-BIG "не проверено" "нет journalctl"
    fi
    if [ -r /proc/loadavg ] && cores=$(nproc 2>/dev/null); then
        load=$(awk '{ print $1 }' /proc/loadavg)
        if awk -v l="$load" -v c="$cores" 'BEGIN { exit !(l > c * 2) }'; then
            set_result warn AUD-RES-LOAD "load $load при $cores ядрах" "это один замер, скрипт процессы не снимает"
        else
            set_result ok AUD-RES-LOAD "load $load при $cores ядрах"
        fi
    else
        set_result warn AUD-RES-LOAD "не проверено" "нет /proc/loadavg"
    fi
    mem_av=""
    if [ -r /proc/meminfo ]; then
        mem_tot=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
        mem_av=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
        [ -n "$mem_av" ] || mem_av=$(awk '/^MemFree:/ { print $2 }' /proc/meminfo)
        if [ -n "$mem_tot" ] && [ "$mem_tot" -gt 0 ] && awk -v a="$mem_av" -v t="$mem_tot" 'BEGIN { exit !(a * 100 < t * 10) }'; then
            set_result warn AUD-RES-MEM "доступно ${mem_av}K из ${mem_tot}K" "память скрипт не освобождает"
        else
            set_result ok AUD-RES-MEM "доступной памяти не меньше 10%"
        fi
        swap_tot=$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)
        swap_free=$(awk '/^SwapFree:/ { print $2 }' /proc/meminfo)
        if [ "${swap_tot:-0}" -eq 0 ]; then
            set_result ok AUD-RES-SWAP "swap нет"
        elif awk -v t="$swap_tot" -v f="$swap_free" 'BEGIN { exit !((t - f) * 2 > t) }' && awk -v a="$mem_av" -v t="$mem_tot" 'BEGIN { exit !(a * 100 < t * 10) }'; then
            set_result warn AUD-RES-SWAP "swap занят больше чем наполовину при малой доступной памяти" "скрипт swap не чистит"
        else
            set_result ok AUD-RES-SWAP "swap не давит вместе с нехваткой памяти"
        fi
    else
        set_result warn AUD-RES-MEM "не проверено" "нет /proc/meminfo"
        set_result warn AUD-RES-SWAP "не проверено" "нет /proc/meminfo"
    fi
    if zombies=$(ps -axo stat= 2>/dev/null); then
        zombies=$(printf '%s\n' "$zombies" | awk '$1 ~ /^Z/ { n++ } END { print n + 0 }')
        if [ "$zombies" -gt 0 ]; then
            set_result warn AUD-RES-ZOMBIE "зомби: $zombies" "скрипт процессы не снимает"
        else
            set_result ok AUD-RES-ZOMBIE "зомби нет"
        fi
    else
        set_result warn AUD-RES-ZOMBIE "не проверено" "нет ps"
    fi
    if command -v systemctl >/dev/null 2>&1 && unit=$(systemctl --failed --no-legend --plain 2>/dev/null); then
        if [ -n "$unit" ]; then
            set_result warn AUD-SYS-FAILED "$(printf '%s' "$unit" | tr '\n' ' ')" "скрипт юниты не перезапускает"
        else
            set_result ok AUD-SYS-FAILED "failed-юнитов нет"
        fi
    else
        set_result warn AUD-SYS-FAILED "не проверено" "нет systemctl"
    fi
    if [ -e /var/run/reboot-required ]; then
        set_result warn AUD-SYS-REBOOT "есть /var/run/reboot-required" "скрипт машину не перезагружает"
    else
        set_result ok AUD-SYS-REBOOT "перезагрузка не запрошена"
    fi
    if command -v timedatectl >/dev/null 2>&1 && unit=$(timedatectl show -p NTPSynchronized --value 2>/dev/null); then
        if [ "$unit" = yes ]; then
            set_result ok AUD-SYS-TIME "время синхронизировано"
        else
            set_result warn AUD-SYS-TIME "время не синхронизировано" "timedatectl set-ntp true"
        fi
    else
        set_result warn AUD-SYS-TIME "не проверено" "нет timedatectl"
    fi
    check_sysctls
    check_updates
}

mode_too_wide_sticky() {
    local m
    m=$(file_mode /tmp)
    m=$((8#$m))
    [ $((m & 01000)) -eq 0 ]
}

check_sysctls() {
    local code key want level now
    while read -r code key want level; do
        [ -n "$code" ] || continue
        if ! now=$(sysctl -n "$key" 2>/dev/null); then
            set_result warn "$code" "не проверено" "sysctl не прочитал $key"
            continue
        fi
        if [ "$now" = "$want" ]; then
            set_result ok "$code" "$key=$now"
        elif [ "$level" = crit ]; then
            set_result crit "$code" "$key=$now, ожидается $want" "$AUDIT_SYSCTL"
        else
            set_result warn "$code" "$key=$now, ожидается $want" "$AUDIT_SYSCTL"
        fi
    done <<'EOF'
AUD-SYS-ASLR kernel.randomize_va_space 2 crit
AUD-SYS-REDIR net.ipv4.conf.all.accept_redirects 0 warn
AUD-SYS-RP net.ipv4.conf.all.rp_filter 1 warn
AUD-SYS-SYN net.ipv4.tcp_syncookies 1 warn
AUD-SYS-SRC net.ipv4.conf.all.accept_source_route 0 warn
EOF
}

check_updates() {
    local sim
    if ! command -v apt-get >/dev/null 2>&1; then
        set_result warn AUD-UPD "не проверено" "нет apt-get"
        return 0
    fi
    if ! sim=$(apt-get -s upgrade 2>/dev/null); then
        set_result warn AUD-UPD "не проверено" "нет сети или apt не ответил"
        return 0
    fi
    if printf '%s\n' "$sim" | grep -q -- '-security'; then
        set_result warn AUD-UPD "есть обновления из кармана security" "пакеты скрипт не ставит"
    else
        set_result ok AUD-UPD "в пробном upgrade нет кармана security"
    fi
}

check_perms() {
    local mode files home shell user
    if [ -e "$AUDIT_ENV" ]; then
        if mode=$(file_mode "$AUDIT_ENV" 2>/dev/null); then
            if mode_too_wide "$mode"; then
                set_result crit AUD-ENV-MODE "режим $mode у $AUDIT_ENV" "chmod 600"
            else
                set_result ok AUD-ENV-MODE "режим $mode у $AUDIT_ENV"
            fi
        else
            set_result warn AUD-ENV-MODE "нет прав" "запустите скрипт от root"
        fi
    elif [ -d /root ] && [ ! -r /root ]; then
        set_result warn AUD-ENV-MODE "нет прав" "запустите скрипт от root"
    else
        set_result ok AUD-ENV-MODE "файла $AUDIT_ENV нет"
    fi
    files=""
    if [ -d /root ] || [ -d /home ]; then
        files=$(find /root /home -name authorized_keys -type f 2>/dev/null || true)
    fi
    if [ -z "$files" ]; then
        set_result ok AUD-AUTH-KEY "файлов authorized_keys нет"
    else
        local worst=ok fact="" action=""
        while read -r home; do
            [ -n "$home" ] || continue
            mode=$(file_mode "$home")
            mode=$((8#$mode))
            if [ $((mode & 022)) -ne 0 ]; then
                worst=crit
                fact="$fact $home"
            elif [ $((mode & 044)) -ne 0 ]; then
                if [ "$worst" != crit ]; then
                    worst=warn
                fi
                fact="$fact $home"
            fi
        done <<EOF
$files
EOF
        if [ "$worst" = ok ]; then
            set_result ok AUD-AUTH-KEY "authorized_keys только у владельца"
        elif [ "$worst" = crit ]; then
            set_result crit AUD-AUTH-KEY "доступ на запись:$fact" "chmod 600"
        else
            set_result warn AUD-AUTH-KEY "доступ на чтение:$fact" "chmod 600"
        fi
    fi
    if [ -d /etc ]; then
        files=$(find /etc -xdev -type f -perm -0002 2>/dev/null || true)
        if [ -n "$files" ]; then
            set_result crit AUD-ETC-WW "$(printf '%s' "$files" | tr '\n' ' ')" "права скрипт сам не сужает"
        else
            set_result ok AUD-ETC-WW "в /etc нет файлов с записью для остальных"
        fi
    else
        set_result warn AUD-ETC-WW "не проверено" "нет /etc"
    fi
    files=""
    for home in /etc/crontab /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
        [ -e "$home" ] || continue
        while read -r user; do
            [ -n "$user" ] || continue
            mode=$(file_mode "$user" 2>/dev/null || true)
            [ -n "$mode" ] || continue
            if mode_world_or_group_write "$mode"; then
                files="$files $user"
            fi
        done <<EOF
$(find "$home" -type f 2>/dev/null || true)
EOF
    done
    if [ -n "$files" ]; then
        set_result crit AUD-CRON-WW "запись у группы или остальных:$files" "chmod go-w"
    else
        set_result ok AUD-CRON-WW "cron не доступен на запись группе и остальным"
    fi
    files=""
    if [ -r /etc/passwd ]; then
        while IFS=: read -r user _ _ _ _ home shell; do
            case "$shell" in
                */nologin|*/false|*/sync|*/halt|*/shutdown|"") continue ;;
            esac
            [ -d "$home" ] || continue
            mode=$(file_mode "$home" 2>/dev/null || true)
            [ -n "$mode" ] || continue
            mode=$((8#$mode))
            if [ $((mode & 002)) -ne 0 ]; then
                files="$files $home"
            fi
        done < /etc/passwd
    fi
    if [ -n "$files" ]; then
        set_result warn AUD-HOME-WW "каталог доступен на запись остальным:$files" "chmod go-w без рекурсии"
    else
        set_result ok AUD-HOME-WW "домашние каталоги не доступны на запись остальным"
    fi
    if [ -r /etc/sudoers ] || [ -d /etc/sudoers.d ]; then
        if grep -R -n -- 'NOPASSWD' /etc/sudoers /etc/sudoers.d >/dev/null 2>&1; then
            set_result warn AUD-SUDO-NOPASS "в sudoers есть NOPASSWD" "строку скрипт не удаляет"
        else
            set_result ok AUD-SUDO-NOPASS "NOPASSWD не найден"
        fi
    else
        set_result warn AUD-SUDO-NOPASS "нет прав" "запустите скрипт от root"
    fi
}

check_docker() {
    local id name flag bad=""
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    if [ ! -f /etc/cron.daily/docker-image-prune ]; then
        set_result warn AUD-DK-PRUNE "нет /etc/cron.daily/docker-image-prune" "2-install-software/23-docker-autoprune.sh"
    else
        set_result ok AUD-DK-PRUNE "расписание очистки образов есть"
    fi
    if ! docker ps -aq >/dev/null 2>&1; then
        set_result warn AUD-DK-PRIV "не проверено" "docker не ответил"
        set_result warn AUD-DK-SOCK "не проверено" "docker не ответил"
        set_result warn AUD-DK-LATEST "не проверено" "docker не ответил"
        set_result warn AUD-DK-DANGLE "не проверено" "docker не ответил"
        return 0
    fi
    bad=""
    while read -r id; do
        [ -n "$id" ] || continue
        name=$(docker inspect -f '{{.Name}}' "$id" 2>/dev/null || echo "$id")
        flag=$(docker inspect -f '{{.HostConfig.Privileged}}' "$id" 2>/dev/null || echo false)
        if [ "$flag" = true ]; then
            bad="$bad $name"
        fi
    done <<EOF
$(docker ps -aq 2>/dev/null || true)
EOF
    if [ -n "$bad" ]; then
        set_result crit AUD-DK-PRIV "Privileged:$bad" "контейнер скрипт не останавливает"
    else
        set_result ok AUD-DK-PRIV "привилегированных контейнеров нет"
    fi
    bad=""
    while read -r id; do
        [ -n "$id" ] || continue
        name=$(docker inspect -f '{{.Name}} {{range .Mounts}}{{.Source}} {{end}}{{range .HostConfig.Binds}}{{.}} {{end}}' "$id" 2>/dev/null || true)
        if printf '%s' "$name" | grep -q 'docker.sock'; then
            bad="$bad $name"
        fi
    done <<EOF
$(docker ps -aq 2>/dev/null || true)
EOF
    if [ -n "$bad" ]; then
        set_result crit AUD-DK-SOCK "смонтирован docker.sock:$bad" "монтирование скрипт не снимает"
    else
        set_result ok AUD-DK-SOCK "docker.sock в контейнеры не смонтирован"
    fi
    bad=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | awk -F: '$2 == "latest" { print }' | tr '\n' ' ' || true)
    if [ -n "$bad" ]; then
        set_result warn AUD-DK-LATEST "тег latest: $bad" "тег скрипт не меняет"
    else
        set_result ok AUD-DK-LATEST "образов с тегом latest нет"
    fi
    if [ -n "$(docker images -f dangling=true -q 2>/dev/null || true)" ]; then
        set_result warn AUD-DK-DANGLE "есть висячие образы" "docker image prune -f"
    else
        set_result ok AUD-DK-DANGLE "висячих образов нет"
    fi
}

check_nginx() {
    local hit
    if ! command -v nginx >/dev/null 2>&1; then
        return 0
    fi
    if [ ! -d /etc/nginx ]; then
        set_result warn AUD-NGX-TOK "не проверено" "нет /etc/nginx"
        set_result warn AUD-NGX-OLD "не проверено" "нет /etc/nginx"
        return 0
    fi
    if grep -R -n -- 'server_tokens off' /etc/nginx >/dev/null 2>&1; then
        set_result ok AUD-NGX-TOK "server_tokens off задан"
    else
        set_result warn AUD-NGX-TOK "в конфиге нет server_tokens off" "файл nginx скрипт не переписывает"
    fi
    hit=$(grep -R -n -E -- 'TLSv1\.0|TLSv1\.1|TLSv1([^0-9.]|$)|RC4' /etc/nginx 2>/dev/null || true)
    if [ -n "$hit" ]; then
        set_result crit AUD-NGX-OLD "$(printf '%s' "$hit" | tr '\n' ' ')" "файл скрипт не переписывает, шаблон репозитория эту строку не пишет"
    else
        set_result ok AUD-NGX-OLD "старого TLS и RC4 в конфиге нет"
    fi
}

run_checks() {
    prepare_tmp
    read_ssh_port
    capture_ss || true
    collect_info
    check_packages
    check_bin_path
    check_ports
    check_mail
    check_ssh
    check_f2b
    check_firewall
    check_resources
    check_perms
    check_docker
    check_nginx
}

print_report() {
    local title level code fix text fact action ncrit=0 nwarn=0 nok=0 path
    print_bucket() {
        local want=$1 color
        color=$(audit_color "$want")
        printf '%b== %s ==%b\n' "$color" "$2" "$COL_RES"
        while IFS='|' read -r code fix text; do
            path="$AUDIT_TMP/r/$code"
            [ -f "$path" ] || continue
            level=$(awk 'NR == 1 { print; exit }' "$path")
            [ "$level" = "$want" ] || continue
            fact=$(awk 'NR == 2 { print; exit }' "$path")
            action=$(awk 'NR == 3 { print; exit }' "$path")
            printf '%b%s%b  %s\n' "$color" "$code" "$COL_RES" "$fact"
            if [ "$want" != ok ] && [ "$want" != info ] && [ -n "$action" ]; then
                printf '  Сделать: %s\n' "$action"
            fi
            case "$want" in
                crit) ncrit=$((ncrit + 1)) ;;
                warn) nwarn=$((nwarn + 1)) ;;
                ok) nok=$((nok + 1)) ;;
            esac
        done < <(catalog)
    }
    # Нулевой счётчик серый, ненулевой — цветом своего уровня.
    total_part() {
        local color=$1 name=$2 n=$3
        if [ "$n" -eq 0 ]; then
            color=$COL_FG_GRAY
        fi
        printf '%b%s=%s%b' "$color" "$name" "$n" "$COL_RES"
    }
    print_bucket info "Собрано"
    print_bucket ok "Сильные стороны"
    print_bucket warn "Предупреждения"
    print_bucket crit "Критичное"
    printf 'Итог: %s %s %s\n' \
        "$(total_part "$COL_RED" critical "$ncrit")" \
        "$(total_part "$COL_FG_YELLOW" warning "$nwarn")" \
        "$(total_part "$COL_LIME" ok "$nok")"
    AUDIT_NCRIT=$ncrit
}

write_sysctl_key() {
    local key=$1 val=$2 tmp
    mkdir -p "$(dirname -- "$AUDIT_SYSCTL")"
    tmp=$(mktemp)
    if [ -f "$AUDIT_SYSCTL" ]; then
        awk -v k="$key" 'index($0, k "=") != 1 { print }' "$AUDIT_SYSCTL" > "$tmp"
    fi
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
    cat "$tmp" > "$AUDIT_SYSCTL"
    rm -f "$tmp"
    sysctl -w "$key=$val" >/dev/null
}

do_fix() {
    local code=$1 proc
    case "$code" in
        AUD-P-22)
            proc=$(port_proc tcp 22)
            if [ "$proc" != sshd ]; then
                logr "На порту 22 процесс не опознан как sshd (${proc:-неизвестен}). Процесс не останавливаю."
                return 2
            fi
            if [ -z "$SSH_PORT" ] || [ "$SSH_PORT" = 22 ]; then
                logr "SSH_PORT не задан или равен 22. Скрипт 13 не запускаю."
                return 2
            fi
            warn_ssh_drop
            run_project_script 1-server-setup/13-ssh-restrict.sh
            ;;
        AUD-MAIL)
            run_project_script 1-server-setup/11-remove-mail-server.sh
            ;;
        AUD-SSH-PASS|AUD-SSH-ROOT)
            warn_ssh_drop
            run_project_script 1-server-setup/13-ssh-restrict.sh
            ;;
        AUD-SSH-PORT)
            if [ -z "$SSH_PORT" ]; then
                logr "SSH_PORT не задан. Скрипт 13 не запускаю."
                return 2
            fi
            warn_ssh_drop
            run_project_script 1-server-setup/13-ssh-restrict.sh
            ;;
        AUD-F2B)
            run_project_script 1-server-setup/14-install-fail2ban.sh
            ;;
        AUD-FW-INPUT|AUD-FW-SSH|AUD-FW-LOG|AUD-FW-V6|AUD-FW-SPORT53|AUD-FW-FWD)
            warn_fw_drop
            run_project_script 1-server-setup/15-secure-firewall.sh
            ;;
        AUD-MNT-STICKY)
            chmod +t /tmp
            ;;
        AUD-JRN-BIG)
            journalctl --vacuum-size=200M
            ;;
        AUD-SYS-TIME)
            if [ ! -f /lib/systemd/system/systemd-timesyncd.service ] && [ ! -f /usr/lib/systemd/system/systemd-timesyncd.service ]; then
                logr "systemd-timesyncd нет. NTP не включаю."
                return 2
            fi
            timedatectl set-ntp true
            ;;
        AUD-SYS-ASLR) write_sysctl_key kernel.randomize_va_space 2 ;;
        AUD-SYS-REDIR) write_sysctl_key net.ipv4.conf.all.accept_redirects 0 ;;
        AUD-SYS-RP) write_sysctl_key net.ipv4.conf.all.rp_filter 1 ;;
        AUD-SYS-SYN) write_sysctl_key net.ipv4.tcp_syncookies 1 ;;
        AUD-SYS-SRC) write_sysctl_key net.ipv4.conf.all.accept_source_route 0 ;;
        AUD-ENV-MODE)
            chmod 600 "$AUDIT_ENV"
            ;;
        AUD-AUTH-KEY)
            find /root /home -name authorized_keys -type f 2>/dev/null | while read -r proc; do
                chmod 600 "$proc"
            done
            ;;
        AUD-CRON-WW)
            find /etc/crontab /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly -type f 2>/dev/null | while read -r proc; do
                chmod go-w "$proc"
            done
            ;;
        AUD-HOME-WW)
            while IFS=: read -r _ _ _ _ _ proc shell; do
                case "$shell" in
                    */nologin|*/false|*/sync|*/halt|*/shutdown|"") continue ;;
                esac
                [ -d "$proc" ] && [ "$proc" != / ] || continue
                mode=$(file_mode "$proc" 2>/dev/null || true)
                [ -n "$mode" ] || continue
                mode=$((8#$mode))
                if [ $((mode & 002)) -ne 0 ]; then
                    chmod go-w "$proc"
                fi
            done < /etc/passwd
            ;;
        AUD-DK-DANGLE)
            docker image prune -f
            ;;
        AUD-DK-PRUNE)
            run_project_script 2-install-software/23-docker-autoprune.sh
            ;;
        *)
            return 2
            ;;
    esac
}

apply_fix() {
    local code=$1 level
    if ! code_known "$code"; then
        logerr "Неизвестный код $code. См. --help"
        return 2
    fi
    run_checks
    level=$(result_level "$code")
    if [ "$level" = ok ] || [ "$level" = info ]; then
        logok "$code уже в порядке"
        return 0
    fi
    if ! code_fixable "$code"; then
        logr "Автоматического исправления нет: $code. $(code_hint "$code")"
        return 2
    fi
    if [ "$level" = none ]; then
        logr "Проверка $code не сработала. Ничего не меняю."
        return 2
    fi
    do_fix "$code" || return $?
    run_checks
    level=$(result_level "$code")
    if [ "$level" = ok ]; then
        logok "$code"
        return 0
    fi
    logerr "$code не исправлен"
    return 1
}

print_help() {
    local code fix text kind mark
    cat <<EOF
Использование:
  4-services/45-security-audit.sh
  4-services/45-security-audit.sh --help
  4-services/45-security-audit.sh --fix CODE

Без аргументов скрипт читает сервер и печатает отчёт. Файлы и правила он не меняет.
В пресеты батча скрипт не входит.
--fix запускает исправление одного кода. Ключа «починить всё» нет.
Часть кодов вызывает скрипты 1-server-setup/11-remove-mail-server.sh, 13-ssh-restrict.sh, 14-install-fail2ban.sh, 15-secure-firewall.sh и 2-install-software/23-docker-autoprune.sh.
Скрипты 13 и 15 могут оборвать текущую сессию SSH.

Код  вид  --fix  о чём
EOF
    while IFS='|' read -r code fix text; do
        if [[ "$code" == AUD-I-* ]]; then
            kind="сбор"
        else
            kind="проверка"
        fi
        if [ "$fix" = yes ]; then
            mark="меняет"
        else
            mark="не меняет"
        fi
        printf '%b%s%b  %s  %s  %s\n' "$COL_FG_BLUE" "$code" "$COL_RES" "$kind" "$mark" "$text"
    done < <(catalog)
}

main() {
    local rc
    case "${1:-}" in
        -h|--help)
            if [ $# -ne 1 ]; then
                logerr "Неизвестный аргумент. См. --help"
                exit 2
            fi
            print_help
            exit 0
            ;;
        --fix)
            if [ $# -ne 2 ]; then
                logerr "Нужен один код: --fix CODE. См. --help"
                exit 2
            fi
            if ! is_root; then
                logerr "для --fix нужен root"
                exit 2
            fi
            apply_fix "$2" || rc=$?
            exit "${rc:-0}"
            ;;
        "")
            ;;
        *)
            logerr "Неизвестный аргумент. См. --help"
            exit 2
            ;;
    esac
    run_checks
    print_report
    if ! is_root; then
        logerr "для полного отчёта нужен root"
        exit 2
    fi
    if [ "${AUDIT_NCRIT:-0}" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
