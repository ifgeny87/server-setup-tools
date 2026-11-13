# Проверка бана и лимита лога

Прогон на ВМ Ubuntu 24.04 со sshd и systemd. Контейнер без systemd этот файл не заменяет. Locust и k6 не используются.

Скрипты 10–15 уже пройдены, сессия открыта на `SSH_PORT` из `.env` (в репозитории это `9999`). `maxretry` в jail `sshd` равен 3. Правило лога в скрипте 15: `-m limit --limit 5/min`, префикс `FIREWALL DROP:`.

## Бан

С другой машины, не с той, с которой держится рабочая сессия:

```shell
for i in 1 2 3 4; do
  ssh -p 9999 \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o NumberOfPasswordPrompts=1 \
    invaliduser@SERVER
done
```

На сервере:

```shell
sudo fail2ban-client status sshd
```

Ожидание: в `Banned IP list` есть адрес атакующего. Вход с другого адреса на порт `9999` по-прежнему проходит. Чужой адрес в список бана не попадает.

На Ubuntu 24.04 клиент без ключа часто не доходит до пароля: `AuthenticationMethods` начинается с `publickey`. Для jail достаточно четырёх отказов по ключу с того же адреса. Строка в логе содержит `Invalid user` или `Failed publickey`.

## Лимит лога

С адреса не из `lo` послать 30 SYN на закрытый порт, не 80, 443 и не `SSH_PORT`:

```shell
python3 - << 'PY'
import socket
for _ in range(30):
    s = socket.socket()
    s.settimeout(0.2)
    try:
        s.connect(("SERVER", 1))
    except OSError:
        pass
    finally:
        s.close()
PY
```

```shell
sudo journalctl -k --since "1 min ago" | grep -c 'FIREWALL DROP'
sudo grep 'FIREWALL DROP' /var/log/syslog | tail
```

Ожидание: в journal около 5 новых строк, не 30 и не тысячи в секунду. В строке есть `FIREWALL DROP:` и `DPT=1`. Пакеты на `lo` в это правило не попадают: для них есть `ACCEPT` раньше.

## Прогон 2026-11-13

ВМ Lima, Ubuntu 24.04.5 LTS, aarch64, systemd. Скрипты 10–15 завершились. `ss` показал `0.0.0.0:9999` и `[::]:9999`. Jail: `port = 9999`, `maxretry = 3`, `bantime = 604800`.

Лимит. 30 SYN с `10.66.0.2` на `10.66.0.1:1`. В journal было 16 строк `FIREWALL DROP`, стало 21, разница 5. В `/var/log/syslog` было 11, стало 17, разница 6: лишняя строка — `message repeated`. Пять строк на `DPT=1` пришли за пару секунд, не по строке на каждый SYN.

Бан. Четыре отказа с `192.168.5.2` в `16:37:55`. `fail2ban` записал `Ban 192.168.5.2`. Статус jail:

```text
|- Currently failed: 1
|- Total failed: 4
|- Currently banned: 1
`- Banned IP list: 192.168.5.2
```

Вход `dev` с `10.66.0.2` на `10.66.0.1:9999` ключом и паролем прошёл: `GOOD_LOGIN_OK`. Этот адрес в списке бана нет.

Повторные 30 SYN в ту же минуту добавили 1 строку, не 30: ведро лимита уже было занято первой пачкой и повторами на порт 22.

Первый заход в тот же день бана не дал: `ssh.socket` с `ListenStream=9999` слушал только `[::]:9999`, IPv4 получал `Connection refused`, в jail было 0. Скрипт 13 после этого выключает `ssh.socket` и отдаёт порт сервису `ssh`. Без сокета `sshd` пишет в лог `Server listening on 0.0.0.0 port 9999` и `Server listening on :: port 9999`.
