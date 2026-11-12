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

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

logr "Обновление пакетов..."
apt-get update -yy

logr "Обновление системы..."
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

logr "Установка инструментов..."
apt-get install -yy zsh tmux vim mc htop git gh net-tools

logok "Установка базовых инструментов завершена"
