#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт применяется для настройки окружения пользвоателя.
# Запускать под конкретным пользователем.
# Конфиги дописываются блоком sst: повтор заменяет блок и не копит строки.

loghead "Настройка рабочего окружения пользователя"

if ! command -v zsh >/dev/null 2>&1; then
    logerr "zsh не установлен. Сначала выполните 1-server-setup/10-prepare-tools.sh"
    exit 1
fi

if [ -n "${EDITOR:-}" ]; then
    logr "Редактор уже задан: $EDITOR"
elif [ ! -t 0 ]; then
    logr "Нет терминала, выбор редактора пропущен"
else
    logr "Выбор редактора по умолчанию"
    select-editor
fi

login_shell=$(getent passwd "$(id -un)" | awk -F: '{print $7}')
if [ "$(basename -- "$login_shell")" = "zsh" ]; then
    logr "Шелл по умолчанию уже zsh"
else
    logr "Заменяем шелл по умолчанию на zsh"
    chsh -s "$(command -v zsh)"
fi

vim_body=$(cat <<'EOF'
set encoding=utf-8
set hlsearch
set incsearch
set ruler
set showcmd
set smartcase
set mouse=a
colorscheme koehler
EOF
)
zsh_body=$(cat <<'EOF'
LC_CTYPE=en_US.UTF-8
LC_ALL=en_US.UTF-8
EOF
)
bash_body=$(cat <<'EOF'
export HISTTIMEFORMAT=\"%Y-%m-%d %H:%M:%S  \"
# 30 black, 31, red, 36 cyan, 32 green, 33;1 yellow, 34 blue
export PS1=\"\[\033[31;1m\]\u\[\033[33;1m\]@\[\033[36;1m\]\h\[\033[m\]:\[\033[34;1m\]\w\[\033[m\]$ \"
export CLICOLOR=1
export LSCOLORS=ExFxBxDxCxegedabagacad
EOF
)

sst_replace_block "${HOME}/.vimrc" "vimrc" "$vim_body"
if [ "$SST_FILE_CHANGED" = 1 ]; then
    logr "Обновлён ~/.vimrc"
else
    logr "Блок vimrc уже записан"
fi

sst_replace_block "${HOME}/.zshrc" "zshrc" "$zsh_body"
if [ "$SST_FILE_CHANGED" = 1 ]; then
    logr "Обновлён ~/.zshrc"
else
    logr "Блок zshrc уже записан"
fi

sst_replace_block "${HOME}/.bashrc" "bashrc" "$bash_body"
if [ "$SST_FILE_CHANGED" = 1 ]; then
    logr "Обновлён ~/.bashrc"
else
    logr "Блок bashrc уже записан"
fi

logok "Конфигурации настроены"
