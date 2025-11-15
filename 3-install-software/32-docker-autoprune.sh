#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Скрипт добавляет расписание для очистки Docker images

checkRoot

loghead "Добавление расписания для очистки Docker images"

logr "Добавление расписания для автоматического обновления сертификатов и перезапуска nginx..."
FILE=/etc/cron.daily/docker-image-prune
cat > $FILE << EOF
#!/bin/bash -e
# Location: $FILE
# Created: $(timestamp)
docker image prune -f
EOF
chmod +x $FILE
logok "Создан файл ежедневного расписания: $FILE"
