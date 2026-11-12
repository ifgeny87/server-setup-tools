#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

checkRoot
loadEnv

loghead "Настройка SSH сервера"

# Проверка обязательной группы
if [ -z "$SSH_GROUP" ]; then
    logerr "Отсутствует переменная окружения: SSH_GROUP"
    exit 1
fi

# Проверка обязательных переменных
if [ -z "$SSH_PORT" ] || [ -z "$SSH_CONFIG_BACKUP" ]; then
    logerr "Отсутствует переменная окружения: SSH_PORT или SSH_CONFIG_BACKUP"
    exit 1
fi

if [ ! -f /etc/ssh/sshd_config ]; then
    logerr "Нет файла /etc/ssh/sshd_config"
    exit 1
fi

# Создаём группу для пользвоателей SSH
# Проверка дублируется при создании пользователя
if ! getent group "$SSH_GROUP" > /dev/null; then
    logr "Создается группа: $SSH_GROUP"
    groupadd "$SSH_GROUP"
fi

BEGIN="# BEGIN sst ssh-restrict"
END="# END sst ssh-restrict"
BODY="PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthenticationMethods publickey,password
AllowGroups ${SSH_GROUP}
Port ${SSH_PORT}"

# Один блок в конце файла. Те же директивы вне блока снимаются, чтобы не копиться.
DESIRED=$(mktemp)
awk -v b="$BEGIN" -v e="$END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip { next }
    $0 == "# --- Restrict SSH Access ---" { next }
    $0 ~ /^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AuthenticationMethods|AllowGroups|Port)[[:space:]]/ { next }
    { line[++n] = $0 }
    END {
        last = n
        while (last > 0 && line[last] ~ /^[[:space:]]*$/) last--
        for (i = 1; i <= last; i++) print line[i]
    }
' /etc/ssh/sshd_config > "$DESIRED.out"
{
    if [ -s "$DESIRED.out" ]; then
        cat "$DESIRED.out"
        echo
    fi
    printf '%s\n' "$BEGIN"
    printf '%s\n' "$BODY"
    printf '%s\n' "$END"
} > "$DESIRED"
rm -f "$DESIRED.out"

current_port=$(sshd -T -f /etc/ssh/sshd_config 2>/dev/null | awk 'tolower($1)=="port" { print $2; exit }' || true)
made_backup=0

if cmp -s /etc/ssh/sshd_config "$DESIRED"; then
    logr "Конфиг SSH уже совпадает"
    rm -f "$DESIRED"
    need_restart=0
else
    if ! cp /etc/ssh/sshd_config "$SSH_CONFIG_BACKUP"; then
        logerr "Не удалось создать бэкап файла: /etc/ssh/sshd_config"
        rm -f "$DESIRED"
        exit 1
    fi
    logd "Бэкап конфигурации сохранен: $SSH_CONFIG_BACKUP"
    made_backup=1
    cat "$DESIRED" > /etc/ssh/sshd_config
    rm -f "$DESIRED"
    need_restart=1

    logr "Проверяем конфигурацию SSH..."
    if ! sshd -t; then
        logerr "Конфигурация SSH недействительна. Возвращаю $SSH_CONFIG_BACKUP"
        cp "$SSH_CONFIG_BACKUP" /etc/ssh/sshd_config
        exit 1
    fi
fi

if [ -n "$current_port" ] && [ "$current_port" != "$SSH_PORT" ]; then
    logwarn "Порт SSH сменится с ${current_port} на ${SSH_PORT}. Текущая сессия оборвётся"
    need_restart=1
elif command -v ss >/dev/null 2>&1 && ! ss -lnt | awk '{ print $4 }' | grep -Eq "(^|:)${SSH_PORT}$"; then
    logr "sshd ещё не слушает порт ${SSH_PORT}"
    need_restart=1
fi

if [ "$need_restart" -eq 0 ]; then
    logok "Настройка SSH-сервера уже применена, перезапуск не нужен
----------------------------------------
Порт SSH: $SSH_PORT
----------------------------------------
"
    exit 0
fi

if systemctl cat ssh.service >/dev/null 2>&1; then
    SSH_UNIT=ssh
elif systemctl cat sshd.service >/dev/null 2>&1; then
    SSH_UNIT=sshd
else
    logerr "Не найден юнит ssh или sshd"
    exit 1
fi

logr "Перезапускаем SSH-сервер ($SSH_UNIT)..."
if ! systemctl restart "$SSH_UNIT"; then
    logerr "Не удалось перезапустить SSH-сервер. Проверьте: journalctl -u $SSH_UNIT"
    exit 1
fi

permit_root="не прочитано"
if found=$(sshd -T | grep -E -i 'permitrootlogin'); then
    permit_root="$found"
fi

logok "Настройка SSH-сервера завершена
----------------------------------------
Порт SSH: $SSH_PORT
Вход root по SSH: запрещён (check: ${permit_root})
Двухфакторная аутентификация: RSA ключ + пароль
Бэкап конфигурации: $( [ "$made_backup" -eq 1 ] && printf '%s' "$SSH_CONFIG_BACKUP" || printf '%s' "не создавался" )
----------------------------------------
"

exit 0
