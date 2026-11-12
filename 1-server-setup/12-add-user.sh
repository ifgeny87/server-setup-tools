#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

checkRoot
loadEnv

# Проверка обязательной группы
if [ -z "$SSH_GROUP" ]; then
    logerr "В .env не задана SSH_GROUP"
    exit 1
fi

# Проверка обязательных переменных
if [ -z "${USER_GROUPS:-}" ]; then
    logerr "В .env не задана USER_GROUPS"
    exit 1
fi

loghead "Создание нового пользователя"

# Создаём группу для пользвоателей SSH
# Проверка дублируется при настройке ssh
if ! getent group "$SSH_GROUP" > /dev/null; then
    logr "Создается группа: $SSH_GROUP"
    groupadd "$SSH_GROUP"
fi

# 1. Запрашиваем имя пользователя
NEWUSERNAME=${NEWUSERNAME:-}
if [ -z "$NEWUSERNAME" ]; then
    if [ -t 0 ]; then
        read -r -p "Введите имя нового пользователя: " NEWUSERNAME
    fi
fi
if [ -z "$NEWUSERNAME" ]; then
    logerr "Имя пользователя не может быть пустым"
    exit 1
fi

# 2. Создаём пользователя только если его ещё нет
if id "$NEWUSERNAME" &>/dev/null; then
    logr "Пользователь уже есть: $NEWUSERNAME"
else
    logr "Создаём пользователя: $NEWUSERNAME"
    if ! adduser --disabled-password --gecos "" "$NEWUSERNAME"; then
        logerr "Не удалось создать пользователя: $NEWUSERNAME"
        exit 1
    fi
fi

HOME_DIR=$(getent passwd "$NEWUSERNAME" | awk -F: '{print $6}')
if [ -z "$HOME_DIR" ]; then
    logerr "Не найден домашний каталог пользователя: $NEWUSERNAME"
    exit 1
fi

# 3. Добавляем недостающие группы
logr "Проверяем группы пользователя $NEWUSERNAME: $USER_GROUPS"
for group in $USER_GROUPS; do
    if ! getent group "$group" >/dev/null; then
        if [ "$group" = "sudo" ]; then
            logerr "Группы sudo нет. Сначала выполните 1-server-setup/10-prepare-tools.sh"
            exit 1
        fi
        logr "Создается группа: $group"
        if ! groupadd "$group"; then
            logerr "Не удалось создать группу: $group"
            exit 1
        fi
    fi
    if id -nG "$NEWUSERNAME" | tr ' ' '\n' | grep -qx "$group"; then
        logr "Группа уже назначена: $group"
        continue
    fi
    if ! usermod -aG "$group" "$NEWUSERNAME"; then
        logerr "Не удалось добавить пользователя $NEWUSERNAME в группу: $group"
        exit 1
    fi
done

# 4. Ключ дописывается, чужие строки не затираются
AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"
SSH_KEY=${SSH_KEY:-}
if [ -z "$SSH_KEY" ] && [ -t 0 ] && [ ! -s "$AUTH_KEYS" ]; then
    echo "Введите публичный SSH‑ключ (одна строка, начинается с 'ssh-rsa' и т.п.):"
    read -r SSH_KEY || true
fi
if [ -z "$SSH_KEY" ]; then
    if [ -s "$AUTH_KEYS" ]; then
        logr "Ключ не передан, authorized_keys уже есть — пропуск"
    else
        logerr "Нужен SSH-ключ: authorized_keys пуст или отсутствует"
        exit 1
    fi
elif [[ ! "$SSH_KEY" =~ ^ssh-[^[:space:]]+[[:space:]]+ ]]; then
    logerr "Некорректный формат SSH‑ключа"
    exit 1
else
    logr "Настраиваем SSH‑ключ для '$NEWUSERNAME'"
    if ! mkdir -p "$HOME_DIR/.ssh"; then
        logerr "Не удалось настроить SSH-ключ для '$NEWUSERNAME'."
        exit 1
    fi
    if [ -f "$AUTH_KEYS" ] && grep -Fxq -- "$SSH_KEY" "$AUTH_KEYS"; then
        logr "Такой ключ уже записан"
    elif ! printf '%s\n' "$SSH_KEY" >> "$AUTH_KEYS"; then
        logerr "Не удалось настроить SSH-ключ для '$NEWUSERNAME'."
        exit 1
    fi
fi

if [ -f "$AUTH_KEYS" ]; then
    if ! chmod 700 "$HOME_DIR/.ssh" \
        || ! chmod 600 "$AUTH_KEYS" \
        || ! chown -R "$NEWUSERNAME:$NEWUSERNAME" "$HOME_DIR/.ssh"
    then
        logerr "Не удалось настроить SSH-ключ для '$NEWUSERNAME'."
        exit 1
    fi
fi

logok "Пользователь настроен: $NEWUSERNAME
----------------------------------------
Рекомендации:
 - задать пароль для этого пользователя: passwd $NEWUSERNAME
----------------------------------------
"
