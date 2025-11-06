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
if ! getent group "$SSH_GROUP" >/dev/null; then
  groupadd "$SSH_GROUP"
  logok "Создана группа: $SSH_GROUP"
fi

# 1. Запрашиваем имя пользователя
NEWUSERNAME=${NEWUSERNAME:-}
if [ -z "$NEWUSERNAME" ]; then
    read -p "Введите имя нового пользователя: " NEWUSERNAME
fi
if [ -z "$NEWUSERNAME" ]; then
    logerr "Имя пользователя не может быть пустым"
    exit 1
fi

# 2. Проверяем существование пользователя
if id "$NEWUSERNAME" &>/dev/null; then
    logerr "Пользователь '$NEWUSERNAME' уже существует"
    exit 1
fi

HOME_DIR="/home/$NEWUSERNAME"

# 3. Создаём пользователя (без пароля, с домашней директорией)
logr "Создаём пользователя '$NEWUSERNAME'..."
adduser --disabled-password --gecos "" "$NEWUSERNAME"
if [ $? -ne 0 ]; then
    logerr "Не удалось создать пользователя: $NEWUSERNAME"
    exit 1
fi

# 4. Добавляем в группы
logr "Добавляем '$NEWUSERNAME' в группы: $USER_GROUPS..."
for group in $USER_GROUPS; do
    usermod -aG "$group" "$NEWUSERNAME"
    if [ $? -ne 0 ]; then
        logerr "Не удалось добавить пользователя $NEWUSERNAME в группу: $group"
        exit 1
    fi
done

# 5. Запрашиваем SSH‑ключ
SSH_KEY=${SSH_KEY:-}
if [ -z "$SSH_KEY" ]; then
    echo "Введите публичный SSH‑ключ (одна строка, начинается с 'ssh-rsa' и т.п.):"
    read SSH_KEY
fi
if [[ -z "$SSH_KEY" ]] || [[ ! "$SSH_KEY" =~ ^ssh-[^[:space:]]+[[:space:]]+ ]]; then
    logerr "Некорректный формат SSH‑ключа"
    exit 1
fi

# 6. Настраиваем ключ для пользователя
logr "Настраиваем SSH‑ключ для '$NEWUSERNAME'"
mkdir -p "$HOME_DIR/.ssh"
echo "$SSH_KEY" > "$HOME_DIR/.ssh/authorized_keys"
chmod 700 "$HOME_DIR/.ssh"
chmod 600 "$HOME_DIR/.ssh/authorized_keys"
chown -R "$NEWUSERNAME:$NEWUSERNAME" "$HOME_DIR/.ssh"
if [ $? -ne 0 ]; then
    logerr "Не удалось настроить SSH‑ключ для '$NEWUSERNAME'."
    exit 1
fi

logok "Пользователь '$NEWUSERNAME' создан и настроен.
----------------------------------------
Рекомендации:
 - задать пароль для этого пользователя: passwd $NEWUSERNAME
 - запустить скрипт для настройки SSH сервера: ./1-server-setup/13-ssh-restrict.sh
----------------------------------------
"
