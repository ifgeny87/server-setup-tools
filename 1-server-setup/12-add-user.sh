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
NEW_USER_LOGIN=${NEW_USER_LOGIN:-}
if [ -z "$NEW_USER_LOGIN" ]; then
    if [ -t 0 ]; then
        read -r -p "Введите логин нового пользователя: " NEW_USER_LOGIN
    fi
fi
if [ -z "$NEW_USER_LOGIN" ]; then
    logerr "Имя пользователя не может быть пустым"
    exit 1
fi

# 2. Создаём пользователя только если его ещё нет
if id "$NEW_USER_LOGIN" &>/dev/null; then
    logr "Пользователь уже есть: $NEW_USER_LOGIN"
else
    logr "Создаём пользователя: $NEW_USER_LOGIN"
    if ! adduser --disabled-password --gecos "" "$NEW_USER_LOGIN"; then
        logerr "Не удалось создать пользователя: $NEW_USER_LOGIN"
        exit 1
    fi
fi

HOME_DIR=$(getent passwd "$NEW_USER_LOGIN" | awk -F: '{print $6}')
if [ -z "$HOME_DIR" ]; then
    logerr "Не найден домашний каталог пользователя: $NEW_USER_LOGIN"
    exit 1
fi

# 3. Добавляем недостающие группы
logr "Проверяем группы пользователя $NEW_USER_LOGIN: $USER_GROUPS"
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
    if id -nG "$NEW_USER_LOGIN" | tr ' ' '\n' | grep -qx "$group"; then
        logr "Группа уже назначена: $group"
        continue
    fi
    if ! usermod -aG "$group" "$NEW_USER_LOGIN"; then
        logerr "Не удалось добавить пользователя $NEW_USER_LOGIN в группу: $group"
        exit 1
    fi
done

# 4. Ключ дописывается, чужие строки не затираются
AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"
NEW_USER_SSH_KEY=${NEW_USER_SSH_KEY:-}
if [ -z "$NEW_USER_SSH_KEY" ] && [ -t 0 ] && [ ! -s "$AUTH_KEYS" ]; then
    echo "Введите публичный SSH‑ключ (одна строка, начинается с 'ssh-rsa' и т.п.):"
    read -r NEW_USER_SSH_KEY || true
fi
if [ -z "$NEW_USER_SSH_KEY" ]; then
    if [ -s "$AUTH_KEYS" ]; then
        logr "Ключ не передан, authorized_keys уже есть — пропуск"
    else
        logerr "Нужен SSH-ключ: authorized_keys пуст или отсутствует"
        exit 1
    fi
elif [[ ! "$NEW_USER_SSH_KEY" =~ ^ssh-[^[:space:]]+[[:space:]]+ ]]; then
    logerr "Некорректный формат SSH‑ключа"
    exit 1
else
    logr "Настраиваем SSH‑ключ для '$NEW_USER_LOGIN'"
    if ! mkdir -p "$HOME_DIR/.ssh"; then
        logerr "Не удалось настроить SSH-ключ для '$NEW_USER_LOGIN'."
        exit 1
    fi
    if [ -f "$AUTH_KEYS" ] && grep -Fxq -- "$NEW_USER_SSH_KEY" "$AUTH_KEYS"; then
        logr "Такой ключ уже записан"
    elif ! printf '%s\n' "$NEW_USER_SSH_KEY" >> "$AUTH_KEYS"; then
        logerr "Не удалось настроить SSH-ключ для '$NEW_USER_LOGIN'."
        exit 1
    fi
fi

if [ -f "$AUTH_KEYS" ]; then
    if ! chmod 700 "$HOME_DIR/.ssh" \
        || ! chmod 600 "$AUTH_KEYS" \
        || ! chown -R "$NEW_USER_LOGIN:$NEW_USER_LOGIN" "$HOME_DIR/.ssh"
    then
        logerr "Не удалось настроить SSH-ключ для '$NEW_USER_LOGIN'."
        exit 1
    fi
fi

logok "Пользователь настроен: $NEW_USER_LOGIN
----------------------------------------
Рекомендации:
 - задать пароль для этого пользователя: passwd $NEW_USER_LOGIN
----------------------------------------
"
