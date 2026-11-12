#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт для отключения и удаления почтовых серверов по умолчанию:
# (Postfix, Exim, Sendmail и др.)

checkRoot

loghead "Начало удаления почтовых серверов"

# Юнит, который надо остановить до purge. У mailutils своего сервиса нет.
unit_for_mail_pkg() {
    case "$1" in
        postfix) echo postfix ;;
        exim4) echo exim4 ;;
        sendmail) echo sendmail ;;
        dovecot) echo dovecot ;;
        cyrus-imap) echo cyrus-imapd ;;
        *) echo "" ;;
    esac
}

stop_mail_unit() {
    local unit="$1"
    [ -n "$unit" ] || return 0
    if systemctl list-unit-files "${unit}.service" --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${unit}.service"; then
        logr "Останавливаю юнит: $unit"
        if ! systemctl disable --now "$unit"; then
            logwarn "Не удалось остановить юнит: $unit"
        fi
    fi
}


# Список известных почтовых серверов (MTA) в Ubuntu
MAIL_SERVERS=(
    "postfix"
    "exim4"
    "sendmail"
    "mailutils"
    "cyrus-imap"
    "dovecot"
)

# Флаг для отслеживания удалённых пакетов
removed=false

# Перебираем пакеты и пытаемся удалить
for pkg in "${MAIL_SERVERS[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg"; then
        logr "Удаляю $pkg..."
        stop_mail_unit "$(unit_for_mail_pkg "$pkg")"
        apt-get purge -y "$pkg"* || {
            logwarn "Ошибка при удалении $pkg. Продолжаем..."
            continue
        }
        removed=true
    else
        logr "$pkg не установлен"
    fi
done

# Дополнительно удаляем конфигурационные файлы и логи
logr "Очищаю остатки конфигураций и логов..."
rm -rf /etc/postfix /etc/exim4 /etc/sendmail* /var/log/exim4 /var/log/mail*

# Очищаем очередь почты (если есть)
rm -rf /var/spool/postfix/* /var/spool/exim4/*

# Обновляем кэш пакетов
apt-get autoremove -y
apt-get clean

if [ "$removed" = true ]; then
    logok "Почтовые серверы удалены
----------------------------------------
Рекомендации:
 - перезагрузить систему: sudo reboot
 - проверить, что порты 25/587/465 свободны: sudo ss -tulnp | grep -E '25|587|465'
----------------------------------------
"
else
    logok "Никаких почтовых серверов не найдено"
fi
