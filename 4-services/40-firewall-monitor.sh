#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Создаём systemd unit

logr "Настраиваем автозапуск"

LOG_MONITOR="/usr/local/bin/firewall-monitor.py"
TIMER_FILE="/etc/systemd/system/firewall-monitor.timer"
MONITOR_SERVICE="/etc/systemd/system/firewall-monitor.service"

# --- Python монитор логов ---
cat > "$LOG_MONITOR" <<EOF
#!/usr/bin/env python3
import os, re, requests
from dotenv import load_dotenv, dotenv_values
from pathlib import Path

p = Path(__file__).parents[2]

dir_docker = f'~/.env'
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
                send_message(f"🚨 Попытка подключения: {src} → {dst}:{port}")
main()
EOF

chmod +x "$LOG_MONITOR"

# --- systemd units для мониторинга ---

cat > "$MONITOR_SERVICE" <<EOF
[Unit]
Description=Firewall Log Monitor to Telegram

[Service]
Type=oneshot
ExecStart=$LOG_MONITOR
EOF


cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Periodic firewall log check

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable firewall-monitor.timer
systemctl start firewall-monitor.timer

logok "Telegram уведомления будут отправляться при попытках доступа на запрещённые порты."
