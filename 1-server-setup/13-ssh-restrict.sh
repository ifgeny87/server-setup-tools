#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

checkRoot
loadEnv

# Проверка обязательной группы
if [ -z "$SSH_GROUP" ]; then
    logerr "В .env не задана SSH_GROUP"
    exit 1
fi

# Проверка обязательных переменных
if [ -z "$SSH_PORT" ] || [ -z "$SSH_CONFIG_BACKUP" ]; then
    logerr "В .env не заданы SSH_PORT или SSH_CONFIG_BACKUP"
    exit 1
fi

# Создаём группу для пользвоателей SSH
# Проверка дублируется при создании пользователя
if ! getent group "$SSH_GROUP"; then
  groupadd "$SSH_GROUP"
  logok "Создана группа: $SSH_GROUP"
fi

loghead "Настройка SSH‑сервера"

# 1. Бэкап конфигурации
cp /etc/ssh/sshd_config "$SSH_CONFIG_BACKUP"

if [ $? -ne 0 ]; then
    logerr "Не удалось создать бэкап файла /etc/ssh/sshd_config"
    exit 1
fi
logok "Бэкап конфигурации сохранен: $SSH_CONFIG_BACKUP"

# 2. Удаляем или меняем старые директивы, если они есть в sshd_config
sed -i -E "/^PermitRootLogin\s.*/d" /etc/ssh/sshd_config
sed -i -E "/^PasswordAuthentication\s.*/d" /etc/ssh/sshd_config
sed -i -E "/^PubkeyAuthentication\s.*/d" /etc/ssh/sshd_config
sed -i -E "/^AuthenticationMethods\s.*/d" /etc/ssh/sshd_config
sed -i -E "/^AllowGroups\s.*/d" /etc/ssh/sshd_config
sed -i -E "/^Port\s.*/d" /etc/ssh/sshd_config

# 3. Добавляем новые правила
cat >> /etc/ssh/sshd_config <<EOF

# --- Restrict SSH Access ---
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthenticationMethods publickey,password
AllowGroups ${SSH_GROUP}
Port ${SSH_PORT}
EOF

# 4. Перезапускаем SSH
logr "Перезапускаем SSH‑сервер..."
systemctl restart ssh
if [ $? -ne 0 ]; then
    logerr "Yе удалось перезапустить SSH‑сервер. Проверьте: journalctl -u sshd"
    exit 1
fi

# 4. Проверяем конфигурацию
logr "Проверяем конфигурацию SSH..."
sshd -t
if [ $? -eq 0 ]; then
    logok "Настройка SSH‑сервера завершена.
----------------------------------------
Порт SSH: $SSH_PORT
Вход root по SSH: запрещён (check: $(sshd -T | grep -E PermitRootLogin))
Двухфакторная аутентификация: RSA ключ + пароль
Бэкап конфигурации: $SSH_CONFIG_BACKUP
----------------------------------------
"
else
    logerr "Конфигурация SSH недействительна. Проверьте /etc/ssh/sshd_config"
    exit 1
fi

exit 0
