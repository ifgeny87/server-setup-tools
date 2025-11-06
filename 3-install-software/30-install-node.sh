#!/bin/bash
set -e
. "$(dirname -- "$0")/_misc.sh" # load misc

# Выполняет установку Node.js
# Источник: https://timeweb.cloud/tutorials/nodejs/kak-ustanovit-node-js-v-ubuntu-22-04

checkRoot

loghead "Установка Node.js"

logr "Настройка пакетов..."
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -

logr "Установка..."
apt-get install -yy nodejs

logok "Установка выполнена
Node.js: $(node -v)
NPM: $(npm -v)"
