#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Тонкая обёртка: ubuntu и debian остаются отдельными скриптами.

checkRoot

if [ ! -f /etc/os-release ]; then
    logerr "Нет /etc/os-release, дистрибутив не определён"
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

case "${ID:-}" in
    ubuntu)
        exec bash "$(dirname -- "$0")/22-install-docker-ubuntu.sh"
        ;;
    debian)
        exec bash "$(dirname -- "$0")/22-install-docker-debian.sh"
        ;;
    *)
        logerr "Дистрибутив не поддерживается: ${ID:-неизвестен}"
        exit 1
        ;;
esac
