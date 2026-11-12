#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Выполняет установку Node.js
# Источник: https://timeweb.cloud/tutorials/nodejs/kak-ustanovit-node-js-v-ubuntu-22-04

checkRoot

VERSION=${VERSION:-25}
VERSION=${VERSION#v}

loghead "Установка Node.js версии ${VERSION}"

if command -v node >/dev/null 2>&1; then
    major=$(node -v | sed -E 's/^v([0-9]+).*/\1/')
    if [ "$major" = "$VERSION" ]; then
        logok "Node.js уже нужной версии: $(node -v)"
        exit 0
    fi
fi

NODE_SETUP_URL="https://deb.nodesource.com/setup_${VERSION}.x"
logr "Проверяем скрипт nodesource: $NODE_SETUP_URL"
if ! curl -fsSL -o /dev/null "$NODE_SETUP_URL"; then
    logerr "Нет скрипта nodesource: $NODE_SETUP_URL"
    exit 1
fi

logr "Настройка пакетов..."
curl -fsSL "$NODE_SETUP_URL" | sudo -E bash -

logr "Установка..."
apt-get install -yy nodejs

logok "Установка Node.js завершена
----------------------------------------
Node.js: $(node -v)
NPM: $(npm -v)
----------------------------------------
"
