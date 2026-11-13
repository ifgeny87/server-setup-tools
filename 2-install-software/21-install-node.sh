#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# Node.js из NodeSource. По умолчанию 26: линия 25 на ноябрь 2026 снята, её не ставить.
# 22 и 24 допустимы, пока у них есть поддержка.
# Источник: https://timeweb.cloud/tutorials/nodejs/kak-ustanovit-node-js-v-ubuntu-22-04

# Ставит мажор VERSION. Пустое значение — 26.
main() {
    checkRoot

    VERSION=${VERSION:-26}
    VERSION=${VERSION#v}
    if [ -z "$VERSION" ]; then
        VERSION=26
    fi
    if [ "$VERSION" = "25" ]; then
        logerr "Node 25 снят с поддержки, его не ставим. По умолчанию 26, допустимы 22 и 24"
        exit 1
    fi

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
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
