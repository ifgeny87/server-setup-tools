#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт выполняет установку oh-my-zsh

if ! command -v zsh >/dev/null 2>&1; then
    logerr "zsh не установлен. Сначала выполните 1-server-setup/10-prepare-tools.sh"
    exit 1
fi

loghead "Установка oh-my-zsh"
logr "Устанавливаем oh-my-zsh"
export RUNZSH=no
export CHSH=no
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

logok "Установлено"
