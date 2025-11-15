#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт для установки и настройки базового набор инструментов
# При выполнении скрипта будет выполнено:
# - apt-get update -yy
# - apt-get upgrade -y
# - apt-get install -yy <TOOLS>

checkRoot

loghead "Установка базовых инструментов"

logr "Обновление пакетов..."
apt-get update -yy

logr "Обновление системы..."
apt-get upgrade -y

logr "Установка инструментов..."
apt-get install -yy zsh tmux vim mc htop git

logok "Установка базовых инструментов завершена"
