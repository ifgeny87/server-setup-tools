#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# oh-my-zsh с зафиксированной ревизии. У upstream нет релизных тегов, записан коммит.
# Установщик скачивается файлом и запускается отдельно, без конвейера в оболочку.
# Ревизия на 2026-11-13.

OMZ_REV=6010fb6260f359e71d99ba25f05f9215809b3ed2

if ! command -v zsh >/dev/null 2>&1; then
    logerr "zsh не установлен. Сначала выполните 1-server-setup/10-prepare-tools.sh"
    exit 1
fi

if [ -d "${HOME}/.oh-my-zsh" ]; then
    logok "oh-my-zsh уже установлен"
    exit 0
fi

if ! command -v git >/dev/null 2>&1; then
    logerr "git не установлен. Сначала выполните 1-server-setup/10-prepare-tools.sh"
    exit 1
fi

loghead "Установка oh-my-zsh"
logr "Устанавливаем oh-my-zsh, ревизия $OMZ_REV"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
installer="$work/install.sh"
pin="$work/pin"
url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/${OMZ_REV}/tools/install.sh"

if ! curl -fsSL -o "$installer" "$url"; then
    logerr "Не скачан установщик oh-my-zsh: $url"
    exit 1
fi

# Локальная копия этой ревизии. Установщик забирает её, а не движущуюся ветку.
git init -q -b pinned "$pin"
git -C "$pin" remote add origin https://github.com/ohmyzsh/ohmyzsh.git
if ! git -C "$pin" fetch --depth 1 origin "$OMZ_REV"; then
    logerr "Не получена ревизия oh-my-zsh $OMZ_REV"
    exit 1
fi
git -C "$pin" checkout -q -B pinned FETCH_HEAD

export RUNZSH=no
export CHSH=no
export BRANCH=pinned
export REMOTE="$pin"
sh "$installer"

if [ -d "${HOME}/.oh-my-zsh/.git" ]; then
    git -C "${HOME}/.oh-my-zsh" remote set-url origin https://github.com/ohmyzsh/ohmyzsh.git
fi

logok "Установлено"
