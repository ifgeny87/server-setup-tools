#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# Установка Docker и Compose под Debian.
# Источник: https://docs.docker.com/engine/install/debian/#install-using-the-repository
# Отпечаток ключа Docker Release (CE deb) тот же, что в документации Ubuntu и Debian.

DOCKER_GPG_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88

# 0, если файл ключа имеет отпечаток DOCKER_GPG_FPR.
docker_key_matches() {
    local fpr
    fpr=$(gpg --batch --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
    [ "$fpr" = "$DOCKER_GPG_FPR" ]
}

# Ставит пакеты Docker, если compose ещё не выполняется.
install_docker() {
    checkRoot

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        logok "Docker Compose уже установлен
----------------------------------------
$(docker -v)
$(docker compose version)
----------------------------------------
"
        exit 0
    fi

    loghead "Установка Docker и Docker Compose под Debian"

    apt-get update -y
    apt-get install -yy ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    key=$(mktemp)
    curl -fsSL https://download.docker.com/linux/debian/gpg -o "$key"
    if ! docker_key_matches "$key"; then
        logerr "Отпечаток ключа Docker не совпал с документацией"
        rm -f "$key"
        exit 1
    fi
    install -m 0644 "$key" /etc/apt/keyrings/docker.asc
    rm -f "$key"
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y

    apt-get install -yy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    logok "Установка Docker + Compose завершена
----------------------------------------
$(docker -v)
$(docker compose version)
----------------------------------------
"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    install_docker
fi
