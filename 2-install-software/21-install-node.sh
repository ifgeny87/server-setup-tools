#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Выполняет установку Node.js
# Источник: https://timeweb.cloud/tutorials/nodejs/kak-ustanovit-node-js-v-ubuntu-22-04

checkRoot

VERSION=${VERSION:22}

loghead "Установка Node.js версии ${VERSION}"

logr "Настройка пакетов..."
curl -fsSL https://deb.nodesource.com/setup_${VERSION}.x | sudo -E bash -

logr "Установка..."
apt-get install -yy nodejs

logok "Установка Node.js завершена
----------------------------------------
Node.js: $(node -v)
NPM: $(npm -v)
----------------------------------------
"
