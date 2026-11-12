#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт добавляет расписание для очистки Docker images

checkRoot

loghead "Добавление расписания для очистки Docker images"

if ! command -v docker >/dev/null 2>&1; then
    logerr "Docker не установлен. Сначала выполните скрипт 22 для своего дистрибутива"
    exit 1
fi

FILE=/etc/cron.daily/docker-image-prune
if [ -f "$FILE" ] && grep -qx 'docker image prune -f' "$FILE"; then
    logok "Расписание уже есть: $FILE"
    exit 0
fi

logr "Добавление ежедневного расписания..."
cat > "$FILE" <<EOF
#!/bin/bash -e
# Location: $FILE
docker image prune -f
EOF
chmod +x "$FILE"

logok "Создан файл ежедневного расписания: $FILE"
