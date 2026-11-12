#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# Интерактив форварда SSH (tcp) и AWG (udp).
# Конфиг помнит намерение, rules.v4 — весь iptables, который переживёт перезагрузку.

IPTABLES_DIR=/etc/iptables
CONF=/etc/iptables/forward-rules.conf
RULES=/etc/iptables/rules.v4
SYSCTL_FILE=/etc/sysctl.d/99-sst-ip-forward.conf
SYSCTL_DIR=/etc/sysctl.d
SYSCTL_MAIN=/etc/sysctl.conf

MENU_ITEMS=(
    "1  Список правил"
    "2  Добавить правило"
    "3  Удалить правило"
    "4  Сохранить правила iptables"
    "5  Загрузить правила iptables"
    "0  Выход"
)
menu_pos=0

is_port() {
    local value=$1
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    [ "$((10#$value))" -ge 1 ] && [ "$((10#$value))" -le 65535 ]
}

# Экранирует метасимволы, чтобы порт 22 не совпал с 222, а точка в IP не стала «любым символом».
re_quote() {
    printf '%s' "$1" | sed -e 's/[.[\*^$()+?{|]/\\&/g'
}

is_ipv4() {
    local ip=$1 octet
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local IFS=.
    # shellcheck disable=SC2086
    set -- $ip
    for octet in "$1" "$2" "$3" "$4"; do
        [ "$((10#$octet))" -le 255 ] || return 1
    done
}

config_entries() {
    local line
    [ -f "$CONF" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        printf '%s\n' "$line"
    done < "$CONF"
}

# Следующий id больше и текущих записей, и # last_id. Удалённые номера не выдаются снова.
next_id() {
    local max=0 id rest line
    if [ -f "$CONF" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                "# last_id "*)
                    id=${line#\# last_id }
                    [ "$id" -gt "$max" ] 2>/dev/null && max=$id
                    ;;
            esac
        done < "$CONF"
    fi
    while read -r id rest; do
        [ "$id" -gt "$max" ] 2>/dev/null && max=$id
    done < <(config_entries)
    echo $((max + 1))
}

entry_exists() {
    local want=$1 id rest
    while read -r id rest; do
        [ "$rest" = "$want" ] && return 0
    done < <(config_entries)
    return 1
}

# Совпадение по цепочке, протоколу, портам и адресам. Комментарий не обязателен.
rule_matches() {
    local kind=$1 line=$2 proto=$3 a=$4 b=$5 c=$6
    a=$(re_quote "$a")
    b=$(re_quote "$b")
    c=$(re_quote "$c")
    [[ "$line" =~ (^|[[:space:]])-p[[:space:]]+${proto}([[:space:]]|$) ]] || return 1
    case "$kind" in
        fwd)
            [[ "$line" == -A\ FORWARD\ * ]] || return 1
            [[ "$line" =~ (^|[[:space:]])-d[[:space:]]+${b}(/32)?([[:space:]]|$) ]] || return 1
            [[ "$line" =~ (^|[[:space:]])--dport[[:space:]]+${a}([[:space:]]|$) ]] || return 1
            [[ "$line" == *" -j ACCEPT"* ]] || return 1
            ;;
        snat)
            [[ "$line" == -A\ POSTROUTING\ * ]] || return 1
            [[ "$line" =~ (^|[[:space:]])-d[[:space:]]+${b}(/32)?([[:space:]]|$) ]] || return 1
            [[ "$line" =~ (^|[[:space:]])--dport[[:space:]]+${a}([[:space:]]|$) ]] || return 1
            [[ "$line" =~ (^|[[:space:]])--to-source[[:space:]]+${c}([[:space:]]|$) ]] || return 1
            [[ "$line" == *" -j SNAT"* ]] || return 1
            ;;
        dnat)
            [[ "$line" == -A\ PREROUTING\ * ]] || return 1
            [[ "$line" =~ (^|[[:space:]])--dport[[:space:]]+${a}([[:space:]]|$) ]] || return 1
            [[ "$line" =~ --to-destination[[:space:]]+${c}([[:space:]]|$) ]] || return 1
            [[ "$line" == *" -j DNAT"* ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

chain_dump() {
    local table=$1 chain=$2
    if [ "$table" = nat ]; then
        iptables -t nat -S "$chain"
    else
        iptables -S "$chain"
    fi
}

rule_present() {
    local table=$1 kind=$2 proto=$3 a=$4 b=$5 c=$6 line chain
    case "$kind" in
        fwd) chain=FORWARD ;;
        snat) chain=POSTROUTING ;;
        dnat) chain=PREROUTING ;;
    esac
    while IFS= read -r line; do
        rule_matches "$kind" "$line" "$proto" "$a" "$b" "$c" && return 0
    done < <(chain_dump "$table" "$chain")
    return 1
}

count_six() {
    local text=$1 lssh=$2 lawg=$3 lip=$4 sssh=$5 sawg=$6 sip=$7
    local n=0 line table=""
    while IFS= read -r line; do
        case "$line" in
            \*nat) table=nat ;;
            \*filter) table=filter ;;
            \**) table=other ;;
            COMMIT) table="" ;;
            -A\ *)
                if [ "$table" = nat ] || [ -z "$table" ]; then
                    rule_matches dnat "$line" tcp "$lssh" "" "$sip:$sssh" && n=$((n + 1))
                    rule_matches dnat "$line" udp "$lawg" "" "$sip:$sawg" && n=$((n + 1))
                    rule_matches snat "$line" tcp "$sssh" "$sip" "$lip" && n=$((n + 1))
                    rule_matches snat "$line" udp "$sawg" "$sip" "$lip" && n=$((n + 1))
                fi
                if [ "$table" = filter ] || [ -z "$table" ]; then
                    rule_matches fwd "$line" tcp "$sssh" "$sip" "" && n=$((n + 1))
                    rule_matches fwd "$line" udp "$sawg" "$sip" "" && n=$((n + 1))
                fi
                ;;
        esac
    done <<< "$text"
    echo "$n"
}

live_dump() {
    {
        echo "*nat"
        iptables -t nat -S
        echo "COMMIT"
        echo "*filter"
        iptables -S
        echo "COMMIT"
    } 2>/dev/null || true
}

status_word() {
    local n=$1
    if [ "$n" -ge 6 ]; then
        printf '%s' "[OK]"
    elif [ "$n" -gt 0 ]; then
        printf '%s' "[WARN]"
    else
        printf '%s' "[ERROR]"
    fi
}

forward_persists() {
    local file
    if [ -f "$SYSCTL_FILE" ] && grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*1([[:space:]]|$)' "$SYSCTL_FILE"; then
        return 0
    fi
    if [ -f "$SYSCTL_MAIN" ] && grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*1([[:space:]]|$)' "$SYSCTL_MAIN"; then
        return 0
    fi
    for file in "$SYSCTL_DIR"/*.conf; do
        [ -f "$file" ] || continue
        if grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*1([[:space:]]|$)' "$file"; then
            return 0
        fi
    done
    return 1
}

reboot_word() {
    local live=$1 snap=$2 in_config=$3
    local persists=0
    forward_persists && persists=1
    if [ "$snap" -ge 6 ] && [ "$persists" -eq 1 ]; then
        printf '%s' "[OK] сохранится"
    elif [ "$snap" -gt 0 ] && [ "$persists" -eq 0 ]; then
        printf '%s' "[ERROR] не поднимется"
    elif [ "$live" -gt 0 ] && [ "$snap" -lt 6 ]; then
        printf '%s' "[WARN] пропадёт"
    elif [ "$in_config" -eq 1 ] && [ "$live" -eq 0 ]; then
        printf '%s' "[WARN] не в iptables"
    else
        printf '%s' "[WARN] пропадёт"
    fi
}

pad() {
    local text=$1 width=$2 n
    n=${#text}
    printf '%s' "$text"
    while [ "$n" -lt "$width" ]; do
        printf ' '
        n=$((n + 1))
    done
}

print_row() {
    pad "$1" 4
    pad "$2" 34
    pad "$3" 34
    pad "$4" 20
    pad "$5" 11
    pad "$6" 11
    printf '%s\n' "$7"
}

comment_ids() {
    local text=$1
    printf '%s\n' "$text" | grep -oE 'sst-fwd-[0-9]+' | sed 's/sst-fwd-//' | sort -u || true
}

do_list() {
    local live snap_text id lssh lawg lip sssh sawg sip
    local live_n snap_n conf_col reboot local_col remote_col
    local -a seen=()
    live=$(live_dump)
    if [ -f "$RULES" ]; then
        snap_text=$(cat "$RULES")
    else
        snap_text=""
    fi
    print_row "id" "куда на этом шлюзе" "куда на сервере" "конфиг" "iptables" "rules.v4" "после ребута"
    local rows=0
    while read -r id lssh lawg lip sssh sawg sip; do
        [ -n "${id:-}" ] || continue
        rows=$((rows + 1))
        seen+=("$id")
        live_n=$(count_six "$live" "$lssh" "$lawg" "$lip" "$sssh" "$sawg" "$sip")
        snap_n=$(count_six "$snap_text" "$lssh" "$lawg" "$lip" "$sssh" "$sawg" "$sip")
        local_col="$lip tcp/$lssh udp/$lawg"
        remote_col="$sip tcp/$sssh udp/$sawg"
        reboot=$(reboot_word "$live_n" "$snap_n" 1)
        print_row "$id" "$local_col" "$remote_col" "да" "$(status_word "$live_n")" "$(status_word "$snap_n")" "$reboot"
    done < <(config_entries)
    local oid found
    for oid in $( { comment_ids "$live"; comment_ids "$snap_text"; } | sort -u ); do
        found=0
        if [ "${#seen[@]}" -gt 0 ]; then
            for id in "${seen[@]}"; do
                [ "$id" = "$oid" ] && found=1
            done
        fi
        [ "$found" -eq 1 ] && continue
        rows=$((rows + 1))
        live_n=$(printf '%s\n' "$live" | grep -c "sst-fwd-${oid}-" || true)
        snap_n=$(printf '%s\n' "$snap_text" | grep -c "sst-fwd-${oid}-" || true)
        if [ "$live_n" -gt 0 ] && [ "$snap_n" -gt 0 ]; then
            conf_col="iptables и снимок"
        elif [ "$live_n" -gt 0 ]; then
            conf_col="только в iptables"
        else
            conf_col="только в снимке"
        fi
        reboot=$(reboot_word "$live_n" "$snap_n" 0)
        print_row "$oid" "-" "-" "$conf_col" "$(status_word "$live_n")" "$(status_word "$snap_n")" "$reboot"
    done
    if [ "$rows" -eq 0 ]; then
        logr "Записей нет"
    fi
    echo "Конфиг форварда: $CONF | Постоянные правила iptables: $RULES"
}

ask_value() {
    local prompt=$1 kind=$2 value
    while true; do
        if ! IFS= read -r -p "$prompt" value; then
            logerr "Ввод закрыт"
            return 1
        fi
        if [ -z "$value" ]; then
            logr "Пустое значение не принимается"
            continue
        fi
        if [ "$kind" = port ] && ! is_port "$value"; then
            logr "Порт должен быть от 1 до 65535"
            continue
        fi
        if [ "$kind" = ip ] && ! is_ipv4 "$value"; then
            logr "Нужен IPv4-адрес"
            continue
        fi
        ASKED=$value
        return 0
    done
}

# Пишет sysctl только когда FORWARD уже DROP. Иначе хост маршрутизирует чужой трафик.
enable_forward_if_needed() {
    local current
    if ! iptables -S 2>/dev/null | grep -qx -- '-P FORWARD DROP'; then
        logerr "Политика FORWARD не DROP. Сначала выполните 1-server-setup/15-secure-firewall.sh"
        return 1
    fi
    current=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)
    if [ "$current" != "0" ]; then
        return 0
    fi
    mkdir -p "$(dirname -- "$SYSCTL_FILE")"
    printf '%s\n' "net.ipv4.ip_forward=1" > "$SYSCTL_FILE"
    if ! sysctl --system >/dev/null; then
        logerr "Не удалось включить net.ipv4.ip_forward"
        return 1
    fi
    logok "Включён ip_forward: $SYSCTL_FILE"
}

ensure_rule() {
    local table=$1 kind=$2 proto=$3 a=$4 b=$5 c=$6
    shift 6
    if rule_present "$table" "$kind" "$proto" "$a" "$b" "$c"; then
        return 0
    fi
    if ! iptables "$@"; then
        logerr "Не удалось добавить правило iptables"
        return 1
    fi
}

remember_id() {
    local id=$1 tmp line found=0
    tmp=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "# last_id "*)
                printf '# last_id %s\n' "$id"
                found=1
                ;;
            *)
                printf '%s\n' "$line"
                ;;
        esac
    done < "$CONF" > "$tmp"
    if [ "$found" -eq 0 ]; then
        printf '# last_id %s\n' "$id" >> "$tmp"
    fi
    cat "$tmp" > "$CONF"
    rm -f "$tmp"
}

append_entry() {
    local id=$1 lssh=$2 lawg=$3 lip=$4 sssh=$5 sawg=$6 sip=$7
    mkdir -p "$(dirname -- "$CONF")"
    if [ ! -s "$CONF" ]; then
        printf '%s\n' "# id local_ssh_port local_awg_port local_ip server_ssh_port server_awg_port server_ip" > "$CONF"
    fi
    printf '%s\n' "$id $lssh $lawg $lip $sssh $sawg $sip" >> "$CONF"
    remember_id "$id"
}

do_add() {
    local lssh lawg lip sssh sawg sip id
    ask_value "LOCAL_SSH_PORT (локальный tcp): " port || return 1
    lssh=$ASKED
    ask_value "LOCAL_AWG_PORT (локальный udp): " port || return 1
    lawg=$ASKED
    ask_value "LOCAL_IP (адрес этого шлюза): " ip || return 1
    lip=$ASKED
    ask_value "SERVER_SSH_PORT (tcp на сервере): " port || return 1
    sssh=$ASKED
    ask_value "SERVER_AWG_PORT (udp на сервере): " port || return 1
    sawg=$ASKED
    ask_value "SERVER_IP (куда уходит DNAT): " ip || return 1
    sip=$ASKED
    if [ "$lip" = "$sip" ]; then
        logerr "LOCAL_IP и SERVER_IP совпадают"
        return 1
    fi
    if entry_exists "$lssh $lawg $lip $sssh $sawg $sip"; then
        logerr "Такая запись уже есть в конфиге, iptables не меняю"
        return 1
    fi
    enable_forward_if_needed || return 1
    id=$(next_id)
    ensure_rule nat dnat tcp "$lssh" "" "$sip:$sssh" \
        -t nat -A PREROUTING -p tcp --dport "$lssh" \
        -m comment --comment "sst-fwd-$id-ssh-dnat" \
        -j DNAT --to-destination "$sip:$sssh" || return 1
    ensure_rule nat snat tcp "$sssh" "$sip" "$lip" \
        -t nat -A POSTROUTING -p tcp -d "$sip" --dport "$sssh" \
        -m comment --comment "sst-fwd-$id-ssh-snat" \
        -j SNAT --to-source "$lip" || return 1
    ensure_rule filter fwd tcp "$sssh" "$sip" "" \
        -A FORWARD -p tcp -d "$sip" --dport "$sssh" \
        -m comment --comment "sst-fwd-$id-ssh-fwd" \
        -j ACCEPT || return 1
    ensure_rule nat dnat udp "$lawg" "" "$sip:$sawg" \
        -t nat -A PREROUTING -p udp --dport "$lawg" \
        -m comment --comment "sst-fwd-$id-awg-dnat" \
        -j DNAT --to-destination "$sip:$sawg" || return 1
    ensure_rule nat snat udp "$sawg" "$sip" "$lip" \
        -t nat -A POSTROUTING -p udp -d "$sip" --dport "$sawg" \
        -m comment --comment "sst-fwd-$id-awg-snat" \
        -j SNAT --to-source "$lip" || return 1
    ensure_rule filter fwd udp "$sawg" "$sip" "" \
        -A FORWARD -p udp -d "$sip" --dport "$sawg" \
        -m comment --comment "sst-fwd-$id-awg-fwd" \
        -j ACCEPT || return 1
    append_entry "$id" "$lssh" "$lawg" "$lip" "$sssh" "$sawg" "$sip"
    logok "Добавлен форвард id $id. Снимок $RULES не менялся"
}

purge_chain() {
    local table=$1 kind=$2 proto=$3 a=$4 b=$5 c=$6
    local chain line i found
    case "$kind" in
        fwd) chain=FORWARD ;;
        snat) chain=POSTROUTING ;;
        dnat) chain=PREROUTING ;;
    esac
    while true; do
        found=0
        i=0
        local -a rules=()
        while IFS= read -r line; do
            [[ "$line" == -A\ * ]] || continue
            rules+=("$line")
        done < <(chain_dump "$table" "$chain")
        for ((i = ${#rules[@]} - 1; i >= 0; i--)); do
            if rule_matches "$kind" "${rules[$i]}" "$proto" "$a" "$b" "$c"; then
                if [ "$table" = nat ]; then
                    iptables -t nat -D "$chain" $((i + 1))
                else
                    iptables -D "$chain" $((i + 1))
                fi
                found=1
                break
            fi
        done
        [ "$found" -eq 1 ] || break
    done
}

remove_entry_rules() {
    local lssh=$1 lawg=$2 lip=$3 sssh=$4 sawg=$5 sip=$6
    purge_chain filter fwd tcp "$sssh" "$sip" ""
    purge_chain filter fwd udp "$sawg" "$sip" ""
    purge_chain nat snat tcp "$sssh" "$sip" "$lip"
    purge_chain nat snat udp "$sawg" "$sip" "$lip"
    purge_chain nat dnat tcp "$lssh" "" "$sip:$sssh"
    purge_chain nat dnat udp "$lawg" "" "$sip:$sawg"
}

do_delete() {
    local -a entries=()
    local line n=1 num ans id lssh lawg lip sssh sawg sip
    while IFS= read -r line; do
        [ -n "$line" ] && entries+=("$line")
    done < <(config_entries)
    if [ "${#entries[@]}" -eq 0 ]; then
        logwarn "Конфиг форварда пуст"
        return 0
    fi
    for line in "${entries[@]}"; do
        read -r id lssh lawg lip sssh sawg sip <<< "$line"
        printf '%s  id=%s  %s tcp/%s udp/%s -> %s tcp/%s udp/%s\n' \
            "$n" "$id" "$lip" "$lssh" "$lawg" "$sip" "$sssh" "$sawg"
        n=$((n + 1))
    done
    while true; do
        if ! IFS= read -r -p "Номер записи: " num; then
            logerr "Ввод закрыт"
            return 1
        fi
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#entries[@]}" ]; then
            break
        fi
        logr "Нет такого номера"
    done
    if ! IFS= read -r -p "Введите yes для удаления: " ans; then
        return 1
    fi
    if [ "$ans" != "yes" ]; then
        logr "Удаление отменено"
        return 0
    fi
    read -r id lssh lawg lip sssh sawg sip <<< "${entries[$((num - 1))]}"
    remove_entry_rules "$lssh" "$lawg" "$lip" "$sssh" "$sawg" "$sip"
    local tmp
    tmp=$(mktemp)
    if [ -f "$CONF" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            if [ "$line" = "$id $lssh $lawg $lip $sssh $sawg $sip" ]; then
                continue
            fi
            printf '%s\n' "$line"
        done < "$CONF" > "$tmp"
        cat "$tmp" > "$CONF"
        rm -f "$tmp"
    fi
    logok "Удалена запись id $id. Снимок $RULES не менялся"
}

confirm_yes() {
    local ans
    if ! IFS= read -r -p "Введите yes для подтверждения: " ans; then
        return 1
    fi
    [ "$ans" = "yes" ]
}

do_save() {
    echo "В $RULES попадёт весь текущий iptables, включая правила скрипта 15, не только форвард."
    if ! confirm_yes; then
        logr "Сохранение отменено"
        return 0
    fi
    mkdir -p "$(dirname -- "$RULES")"
    local tmp
    tmp=$(mktemp)
    if ! iptables-save > "$tmp"; then
        rm -f "$tmp"
        logerr "Не удалось сохранить iptables в $RULES"
        return 1
    fi
    cat "$tmp" > "$RULES"
    rm -f "$tmp"
    if command -v netfilter-persistent >/dev/null 2>&1; then
        if ! netfilter-persistent save; then
            logwarn "netfilter-persistent save не выполнен, файл $RULES уже записан"
        fi
    fi
    logok "Сохранены правила iptables: $RULES"
}

do_load() {
    if [ ! -f "$RULES" ]; then
        logerr "Нет файла $RULES"
        return 1
    fi
    logwarn "Пропадут несохранённые правила. SSH может оборваться, если в снимке другой порт или нет accept для текущего порта"
    if ! confirm_yes; then
        logr "Загрузка отменена"
        return 0
    fi
    if ! iptables-restore < "$RULES"; then
        logerr "iptables-restore не выполнился"
        return 1
    fi
    logok "Загружен снимок iptables: $RULES"
}

draw_menu() {
    local i
    tput clear 2>/dev/null || true
    echo "Конфиг форварда: $CONF"
    echo "Постоянные правила iptables: $RULES"
    echo
    for i in 0 1 2 3 4 5; do
        if [ "$i" -eq "$menu_pos" ]; then
            tput rev 2>/dev/null || true
        fi
        printf '  %s\n' "${MENU_ITEMS[$i]}"
        tput sgr0 2>/dev/null || true
    done
}

read_key() {
    local key rest
    KEY=""
    IFS= read -rsn1 key || return 1
    if [ "$key" = $'\e' ]; then
        IFS= read -rsn2 -t 1 rest || rest=""
        KEY="ESC$rest"
    elif [ -z "$key" ]; then
        KEY=ENTER
    else
        KEY=$key
    fi
}

run_menu_index() {
    case "$1" in
        0) do_list ;;
        1) do_add ;;
        2) do_delete ;;
        3) do_save ;;
        4) do_load ;;
        5) exit 0 ;;
    esac
    if ! IFS= read -r -p "Нажмите Enter для возврата в меню " _; then
        exit 0
    fi
}

menu_loop() {
    while true; do
        draw_menu
        read_key || exit 0
        case "$KEY" in
            ESC'[A') menu_pos=$(( (menu_pos + 5) % 6 )) ;;
            ESC'[B') menu_pos=$(( (menu_pos + 1) % 6 )) ;;
            ENTER) run_menu_index "$menu_pos" ;;
            1|2|3|4|5) run_menu_index $((KEY - 1)) ;;
            0|q) exit 0 ;;
        esac
    done
}

main() {
    checkRoot
    mkdir -p "$IPTABLES_DIR"
    echo "Конфиг форварда: $CONF"
    echo "Постоянные правила iptables: $RULES"
    if ! command -v iptables >/dev/null 2>&1; then
        logerr "iptables не установлен"
        exit 1
    fi
    if [ ! -t 0 ]; then
        logerr "Нужен терминал: это интерактив, не шаг батча"
        exit 1
    fi
    trap 'tput sgr0 2>/dev/null || true' EXIT
    menu_loop
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
