#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Выполняет установку Docker и Compose под Debian
# Источник: https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

checkRoot

loghead "Установка Docker и Docker Compose под Debian"

apt-get update -y
apt-get install -yy ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y

apt-get install -yy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

logok "Установка Docker + Compose завершена
----------------------------------------
$(docker -v)
$(docker rcompose version)
----------------------------------------
"
