#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# Запускать после 1-server-setup/15-secure-firewall.sh:
# монитор читает строки с префиксом FIREWALL DROP.
# Повтор переписывает unit только если текст изменился и тогда же перезапускает таймер.

# 0, если файла нет или его не читают группа и остальные.
env_file_private() {
    local path=$1 mode
    [ -f "$path" ] || return 0
    if ! mode=$(stat -c %a "$path" 2>/dev/null); then
        mode=$(stat -f %OLp "$path")
    fi
    [ $((8#$mode & 077)) -eq 0 ]
}

# Пишет монитор и включает таймер, если секреты не открыты группе и остальным.
main() {
checkRoot

ENV_PATH="${ENV_PATH:-/root/.env}"
if ! env_file_private "$ENV_PATH"; then
    logerr "Файл $ENV_PATH доступен группе или остальным. Таймер не включён"
    exit 1
fi
if [ -f "$ENV_PATH" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_PATH"
    set +a
fi
if [ -z "${TELEGRAM_API_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    logerr "Нет TELEGRAM_API_TOKEN или TELEGRAM_CHAT_ID в окружении или в $ENV_PATH. Таймер не включён"
    exit 1
fi

loghead "Монитор firewall в Telegram"

need_install=0
for pkg in python3 python3-requests python3-dotenv; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        need_install=1
    fi
done
if [ "$need_install" -eq 0 ]; then
    logok "Пакеты монитора уже установлены"
else
    logr "Ставим пакеты для монитора"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -yy python3 python3-requests python3-dotenv
fi

logr "Настраиваем автозапуск"

LOG_MONITOR="/usr/local/bin/firewall-monitor.py"
TIMER_FILE="/etc/systemd/system/firewall-monitor.timer"
MONITOR_SERVICE="/etc/systemd/system/firewall-monitor.service"
changed=0

sst_write_if_changed "$LOG_MONITOR" <<EOF
#!/usr/bin/env python3
import os, re, requests
from dotenv import load_dotenv, dotenv_values
from pathlib import Path

p = Path(__file__).parents[2]

dir_docker = "$ENV_PATH"
dotenv_path = (dir_docker)
if os.path.exists(dotenv_path):
    load_dotenv(dotenv_path)

# реквизиты telegram
token = os.getenv('TELEGRAM_API_TOKEN')
chat_id = os.getenv('TELEGRAM_CHAT_ID')

logfile = "/var/log/syslog"
statefile = "/tmp/firewall_lastpos"

prefix = "FIREWALL DROP:"
pattern = re.compile(r'FIREWALL DROP:.*SRC=([0-9.]+).*DST=([0-9.]+).*DPT=(\\d+)')

def send_message(text):
    try:
        requests.post(f"https://api.telegram.org/bot{token}/sendMessage",
                      data={"chat_id": chat_id, "text": text})
    except Exception as e:
        print("Telegram error:", e)

def main():
    lastpos = 0
    if os.path.exists(statefile):
        lastpos = int(open(statefile).read().strip() or 0)
    with open(logfile, "r") as f:
        f.seek(lastpos)
        lines = f.readlines()
        newpos = f.tell()
    with open(statefile, "w") as s:
        s.write(str(newpos))
    for line in lines:
        if prefix in line:
            m = pattern.search(line)
            if m:
                src, dst, port = m.groups()
                send_message(f"Попытка подключения: {src} -> {dst}:{port}")
main()
EOF
[ "$SST_FILE_CHANGED" = 1 ] && changed=1
chmod +x "$LOG_MONITOR"

sst_write_if_changed "$MONITOR_SERVICE" <<EOF
[Unit]
Description=Firewall Log Monitor to Telegram

[Service]
Type=oneshot
ExecStart=$LOG_MONITOR
EOF
[ "$SST_FILE_CHANGED" = 1 ] && changed=1

sst_write_if_changed "$TIMER_FILE" <<EOF
[Unit]
Description=Periodic firewall log check

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s

[Install]
WantedBy=timers.target
EOF
[ "$SST_FILE_CHANGED" = 1 ] && changed=1

systemctl daemon-reload
systemctl enable firewall-monitor.timer
if [ "$changed" -eq 1 ]; then
    logr "Текст монитора изменился, перезапускаем таймер"
    if ! systemctl restart firewall-monitor.timer; then
        logerr "Не удалось перезапустить firewall-monitor.timer"
        exit 1
    fi
elif ! systemctl is-active --quiet firewall-monitor.timer; then
    if ! systemctl start firewall-monitor.timer; then
        logerr "Не удалось запустить firewall-monitor.timer"
        exit 1
    fi
else
    logr "Таймер уже запущен, restart не нужен"
fi

logok "Telegram уведомления будут отправляться при попытках доступа на запрещённые порты"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
