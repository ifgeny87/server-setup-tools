#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт применяется для настройки окружения пользвоателя.
# Запускать под конкретным пользователем.
# Будет выполнено следующее:
# - выбор редактора по умолчанию
# - выбор zsh по умолчанию
# - конфигурация vimrc, zshrc, bashrc

loghead "Настройка рабочего окружения пользователя"

logr "Выбор редактора по умолчанию"
select-editor

logr "Заменяем шелл по умолчанию на zsh"
chsh -s $(which zsh)

logr "Настраиваем vimrc..."
cat >> ~/.vimrc <<EOF
"
" Author: $(whoami)
" Date: $(timestamp)
set encoding=utf-8
set hlsearch
set incsearch
set ruler
set showcmd
set smartcase
set mouse=a
colorscheme koehler
EOF

logr "Настраиваем zshrc..."
cat >> ~/.zshrc <<EOF

# Author: $(whoami)
# Date: $(timestamp)
LC_CTYPE=en_US.UTF-8
LC_ALL=en_US.UTF-8
EOF

logr "Настраиваем bashrc..."
cat >> ~/.bashrc <<EOF

# Author: $(whoami)
# Date: $(timestamp)
export HISTTIMEFORMAT=\"%Y-%m-%d %H:%M:%S  \"
# 30 black, 31, red, 36 cyan, 32 green, 33;1 yellow, 34 blue
export PS1=\"\[\033[31;1m\]\u\[\033[33;1m\]@\[\033[36;1m\]\h\[\033[m\]:\[\033[34;1m\]\w\[\033[m\]\$ \"
export CLICOLOR=1
export LSCOLORS=ExFxBxDxCxegedabagacad
EOF

logok "Конфигурации настроены"
