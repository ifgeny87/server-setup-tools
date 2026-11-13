#!/bin/bash
# Прогон tests/run.sh в четырёх образах.
# Без --privileged и без systemd. Установка Docker скриптом 22 сюда не входит:
# это Docker внутри Docker, на Mac вложенный dockerd не считается проверкой.
# Скрипты 13–15 со sshd остаются на ВМ. Настоящий iptables не вызывается.
set -euo pipefail

ROOT=$(cd "$(dirname -- "$0")/.." && pwd)
images=(ubuntu:22.04 ubuntu:24.04 debian:12 debian:13)

if ! command -v docker >/dev/null 2>&1; then
    printf 'Нет docker\n' >&2
    exit 1
fi

for image in "${images[@]}"; do
    printf '== %s ==\n' "$image"
    docker run --rm \
        -v "$ROOT:/opt/server-setup-tools:ro" \
        -w /opt/server-setup-tools \
        "$image" \
        bash tests/run.sh
done

printf 'containers: %s ok\n' "${#images[@]}"
