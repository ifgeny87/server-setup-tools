#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Пара ed25519 в ~/.ssh текущего пользователя. Существующий ключ не перезаписывается.
# Пароль на ключ не ставится: повторный запуск и батч без терминала не должны спрашивать.

loghead "Генерация SSH-ключей"

if ! command -v ssh-keygen >/dev/null 2>&1; then
    logerr "Нет ssh-keygen"
    exit 1
fi

ssh_dir="${HOME}/.ssh"
priv="${ssh_dir}/id_ed25519"
pub="${ssh_dir}/id_ed25519.pub"

if [ -f "$priv" ] && [ -f "$pub" ]; then
    logok "Ключи уже есть: $priv"
    logr "Публичный ключ:"
    cat "$pub"
    exit 0
fi

if [ -f "$priv" ] || [ -f "$pub" ]; then
    logerr "Неполная пара ключей в $ssh_dir. Файлы не перезаписываем"
    exit 1
fi

if ! mkdir -p "$ssh_dir"; then
    logerr "Не удалось создать каталог: $ssh_dir"
    exit 1
fi
chmod 700 "$ssh_dir"

comment="${SSH_KEY_COMMENT:-$(id -un)@$(hostname)}"
if ! ssh-keygen -t ed25519 -f "$priv" -N "" -C "$comment" -q; then
    logerr "Не удалось создать ключ: $priv"
    exit 1
fi
chmod 600 "$priv"
chmod 644 "$pub"

logok "Созданы ключи: $priv и $pub"
logr "Публичный ключ:"
cat "$pub"
