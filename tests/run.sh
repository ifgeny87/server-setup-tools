#!/bin/bash
# Регрессия без root, без Docker и без сети. apt, sshd и iptables здесь заглушки.
set -euo pipefail

ROOT=$(cd "$(dirname -- "$0")/.." && pwd)
STUBS="$ROOT/tests/stubs"
PASS=0

# Печатает причину и останавливает прогон.
fail() {
    printf 'FAIL %s\n' "$1" >&2
    if [ -n "${2:-}" ]; then
        printf '%s\n' "$2" >&2
    fi
    exit 1
}

# Считает успешную проверку и печатает её имя.
ok() {
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$1"
}

# Время изменения файла в секундах. На Linux и на macOS формат stat разный.
mtime_of() {
    if stat -c %Y "$1" >/dev/null 2>&1; then
        stat -c %Y "$1"
    else
        stat -f %m "$1"
    fi
}

# Запускает команду и сохраняет код. set -e родителя из-за этого не срабатывает.
capture() {
    set +e
    CAP_OUT=$("$@" 2>&1)
    CAP_CODE=$?
    set -e
}

# Пресет без вопросов к пользователю - clean-server
BATCH_PRESET=clean-server

# --list печатает default, clean-server и web-server и выходит с кодом 0.
test_list() {
    capture "$ROOT/batch/run.sh" --list
    [ "$CAP_CODE" -eq 0 ] || fail "list: код $CAP_CODE" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q '^default	' || fail "list: нет default" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q "^${BATCH_PRESET}	" || fail "list: нет $BATCH_PRESET" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q '^web-server	' || fail "list: нет web-server" "$CAP_OUT"
    ok "presets --list"
}

# .env из каталога запуска даёт NEED. Одноимённый файл в корне репозитория при этом не подменяется.
test_launch_env() {
    local dir
    dir=$(mktemp -d)
    printf '%s\n' 'NEW_USER_LOGIN=from-file' 'NEW_USER_SSH_KEY=test-marker' > "$dir/.env"
    capture env -u NEW_USER_LOGIN -u NEW_USER_SSH_KEY \
        STUB_LOG="$dir/stub.log" PATH="$STUBS:$PATH" \
        bash -c "cd '$dir' && exec '$ROOT/batch/run.sh' --preset '$BATCH_PRESET' --yes"
    printf '%s\n' "$CAP_OUT" | grep -q 'Нет переменной' && fail "launch-env: переменные из .env не прочитаны" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'Читаем .env из каталога запуска' || fail "launch-env: файл запуска не читался" "$CAP_OUT"
    rm -rf "$dir"
    ok ".env из каталога запуска"
}

# Без NEW_USER_LOGIN батч пишет ошибку до скрипта 10 и не вызывает apt.
test_missing_var() {
    local log
    log=$(mktemp)
    capture env -u NEW_USER_LOGIN -u NEW_USER_SSH_KEY \
        STUB_LOG="$log" PATH="$STUBS:$PATH" \
        "$ROOT/batch/run.sh" --preset "$BATCH_PRESET" --yes
    [ "$CAP_CODE" -ne 0 ] || fail "missing: ждали ошибку" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'Нет переменной NEW_USER_LOGIN' || fail "missing: нет текста про переменную" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'Установка базовых инструментов' && fail "missing: скрипт 10 уже стартовал" "$CAP_OUT"
    [ ! -s "$log" ] || fail "missing: заглушка apt вызвана до скрипта 10" "$(cat "$log")"
    rm -f "$log"
    ok "missing NEW_USER_LOGIN до скрипта 10"
}

# Первый шаг падает на заглушке apt-get, второй не стартует.
test_stop_on_error() {
    local log
    log=$(mktemp)
    : > "$log"
    # checkRoot батча требует root до очереди. Здесь вызывается сама очередь run_steps:
    # первый шаг бьётся об заглушку apt-get, второй не стартует.
    capture env STUB_LOG="$log" PATH="$STUBS:$PATH" ROOT="$ROOT" bash -s << 'EOF'
set -euo pipefail
source "$ROOT/batch/run.sh"
checkRoot() { return 0; }
step_path=("tests/fixtures/fail.sh" "tests/fixtures/second.sh")
step_enabled=(1 1)
step_user=(0 0)
run_steps
EOF
    [ "$CAP_CODE" -ne 0 ] || fail "stop: очередь не остановилась" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'Остановлено на tests/fixtures/fail.sh' \
        || fail "stop: нет остановки на первом шаге" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'SECOND_RAN' && fail "stop: второй шаг запустился" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'AFTER_APT' && fail "stop: шаг пошёл дальше apt" "$CAP_OUT"
    grep -q '^apt-get update$' "$log" || fail "stop: apt-get не заглушка" "$(cat "$log")"
    grep -q '^sshd ' "$log" && fail "stop: вызван sshd" "$(cat "$log")"
    rm -f "$log"
    ok "очередь останавливается на первой ошибке"
}

# Число правил -A в filter и nat заглушки iptables.
rule_count() {
    local n=0 file
    for file in "$1/filter.rules" "$1/nat.rules"; do
        [ -f "$file" ] || continue
        n=$((n + $(grep -c '^-A ' "$file" || true)))
    done
    printf '%s' "$n"
}

# Повтор той же шестёрки не добавляет правила. Ответ не yes не вызывает iptables-restore.
test_forward() {
    local work state six
    work=$(mktemp -d)
    state="$work/ipt"
    mkdir -p "$state"
    : > "$state/calls"
    printf '*filter\nCOMMIT\n' > "$work/rules.v4"
    six=$'9901\n49901\n10.1.1.1\n9999\n49901\n10.2.2.2\n'
    capture env IPT_STATE="$state" STUB_LOG="$work/stub.log" PATH="$STUBS:$PATH" \
        ROOT="$ROOT" WORK="$work" SIX="$six" bash -s << 'EOF'
set -euo pipefail
source "$ROOT/4-services/42-manage-forward.sh"
checkRoot() { return 0; }
CONF=$WORK/forward-rules.conf
RULES=$WORK/rules.v4
IPTABLES_DIR=$WORK
SYSCTL_FILE=$WORK/ip-forward.conf
SYSCTL_DIR=$WORK
SYSCTL_MAIN=$WORK/sysctl.conf
printf '%s' "$SIX" | do_add
printf '%s' "$SIX" | do_add
EOF
    [ "$CAP_CODE" -ne 0 ] || fail "forward: повтор шестёрки не отклонился" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'Такая запись уже есть в конфиге' \
        || fail "forward: нет отказа на дубль" "$CAP_OUT"
    local n
    n=$(rule_count "$state")
    [ "$n" -eq 7 ] || fail "forward: правил $n, ждали 7" "$CAP_OUT"
    local adds
    adds=$(grep -c ' iptables .*-A ' "$state/calls" || true)
    capture env IPT_STATE="$state" STUB_LOG="$work/stub.log" PATH="$STUBS:$PATH" \
        ROOT="$ROOT" WORK="$work" bash -s << 'EOF'
set -euo pipefail
source "$ROOT/4-services/42-manage-forward.sh"
checkRoot() { return 0; }
CONF=$WORK/forward-rules.conf
RULES=$WORK/rules.v4
IPTABLES_DIR=$WORK
SYSCTL_FILE=$WORK/ip-forward.conf
SYSCTL_DIR=$WORK
SYSCTL_MAIN=$WORK/sysctl.conf
printf 'no\n' | do_load
EOF
    [ "$CAP_CODE" -eq 0 ] || fail "forward: отказ от загрузки завершился ошибкой" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'Загрузка отменена' || fail "forward: загрузка не отменена" "$CAP_OUT"
    grep -q '^iptables-restore$' "$state/calls" && fail "forward: iptables-restore вызвался" "$(cat "$state/calls")"
    local adds2
    adds2=$(grep -c ' iptables .*-A ' "$state/calls" || true)
    [ "$adds" = "$adds2" ] || fail "forward: отказ от загрузки дописал правила"
    rm -rf "$work"
    ok "форвард: дубль и отказ от restore"
}

# Пишет минимальный server nginx во временный файл.
write_server() {
    local dest=$1 body=$2
    mkdir -p "$(dirname -- "$dest")"
    cat > "$dest" << EOF
server {
    listen 80;
$body
    location / { return 200; }
}
EOF
}

# Скрипт 43 не трогает server, у которого уже есть свой error_page.
test_foreign_error_page() {
    local work src before
    work=$(mktemp -d)
    src="$work/conf.d/own.conf"
    write_server "$src" "    error_page 404 /404.html;"
    before=$(cksum "$src")
    capture env STUB_LOG="$work/nginx.log" PATH="$STUBS:$PATH" \
        PAGE="$work/www/error.html" SNIPPET="$work/snip/sst-errors.conf" \
        NGINX_CONF_D="$work/conf.d" NGINX_SITES="$work/sites" \
        ROOT="$ROOT" bash -s << 'EOF'
set -euo pipefail
source "$ROOT/4-services/43-add-nginx-error-pages.sh"
checkRoot() { return 0; }
mkdir -p "$NGINX_SITES"
main
EOF
    [ "$CAP_CODE" -eq 0 ] || fail "error_page: код $CAP_CODE" "$CAP_OUT"
    [ "$(cksum "$src")" = "$before" ] || fail "error_page: чужой server изменён" "$CAP_OUT"
    grep -q 'include ' "$src" && fail "error_page: в чужой server попал include" "$(cat "$src")"
    printf '%s\n' "$CAP_OUT" | grep -q 'уже есть error_page' || fail "error_page: нет предупреждения" "$CAP_OUT"
    rm -rf "$work"
    ok "чужой error_page не меняется"
}

# Если nginx -t не прошёл, скрипт 43 возвращает конфиг, сниппет и страницу.
test_nginx_rollback() {
    local work src before
    work=$(mktemp -d)
    src="$work/conf.d/plain.conf"
    write_server "$src" ""
    before=$(cksum "$src")
    capture env STUB_LOG="$work/nginx.log" NGINX_FAIL_T=1 PATH="$STUBS:$PATH" \
        PAGE="$work/www/error.html" SNIPPET="$work/snip/sst-errors.conf" \
        NGINX_CONF_D="$work/conf.d" NGINX_SITES="$work/sites" \
        ROOT="$ROOT" bash -s << 'EOF'
set -euo pipefail
source "$ROOT/4-services/43-add-nginx-error-pages.sh"
checkRoot() { return 0; }
mkdir -p "$NGINX_SITES"
main
EOF
    [ "$CAP_CODE" -ne 0 ] || fail "rollback: ждали ошибку nginx -t" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'Подключена страница ошибок' || fail "rollback: include не вставлялся" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'nginx -t не прошёл' || fail "rollback: нет сообщения об откате" "$CAP_OUT"
    [ "$(cksum "$src")" = "$before" ] || fail "rollback: конфиг не вернулся" "$(cat "$src")"
    [ ! -e "$work/snip/sst-errors.conf" ] || fail "rollback: сниппет остался"
    [ ! -e "$work/www/error.html" ] || fail "rollback: страница осталась"
    grep -q 'nginx -s reload' "$work/nginx.log" && fail "rollback: был reload" "$(cat "$work/nginx.log")"
    rm -rf "$work"
    ok "nginx -t откатывает файлы"
}

# Пустой сниппет для скрипта 44 — не установка: файлы и сертификат остаются.
test_empty_stub_not_install() {
    local work snip conf cert
    work=$(mktemp -d)
    snip="$work/snip/sst-errors.conf"
    conf="$work/conf.d/site.conf"
    cert="$work/ssl/default-reject.crt"
    mkdir -p "$(dirname -- "$snip")" "$(dirname -- "$conf")" "$(dirname -- "$cert")"
    : > "$snip"
    printf 'include %s;\nserver { listen 80; }\n' "$snip" > "$conf"
    printf 'cert\n' > "$cert"
    local before_conf before_snip
    before_conf=$(cksum "$conf")
    before_snip=$(cksum "$snip")
    capture env STUB_LOG="$work/nginx.log" PATH="$STUBS:$PATH" \
        PAGE="$work/www/error.html" SNIPPET="$snip" \
        NGINX_CONF_D="$work/conf.d" NGINX_SITES="$work/sites" \
        ROOT="$ROOT" bash -s << 'EOF'
set -euo pipefail
source "$ROOT/4-services/44-remove-nginx-error-pages.sh"
checkRoot() { return 0; }
mkdir -p "$NGINX_SITES"
main
EOF
    [ "$CAP_CODE" -eq 0 ] || fail "stub: код $CAP_CODE" "$CAP_OUT"
    printf '%s\n' "$CAP_OUT" | grep -q 'кастомные страницы не применены' || fail "stub: страницы посчитали установленными" "$CAP_OUT"
    [ "$(cksum "$conf")" = "$before_conf" ] || fail "stub: конфиг изменён" "$(cat "$conf")"
    [ "$(cksum "$snip")" = "$before_snip" ] || fail "stub: пустой сниппет тронут"
    [ -f "$cert" ] || fail "stub: сертификат заглушки удалён"
    [ ! -s "$work/nginx.log" ] || fail "stub: nginx вызывался" "$(cat "$work/nginx.log")"
    rm -rf "$work"
    ok "пустая заглушка для 44 не установка"
}

# Повтор блока sst с теми же байтами не переписывает файл.
test_sst_same_bytes() {
    local work file stamp
    work=$(mktemp -d)
    file="$work/demo.conf"
    (
        # shellcheck disable=SC1091
        source "$ROOT/common/_misc.sh"
        sst_replace_block "$file" demo $'alpha\nbeta'
        [ "$SST_FILE_CHANGED" -eq 1 ]
        touch -t 202001010000 "$file"
        stamp=$(mtime_of "$file")
        sst_replace_block "$file" demo $'alpha\nbeta'
        [ "$SST_FILE_CHANGED" -eq 0 ]
        [ "$(mtime_of "$file")" = "$stamp" ]
        grep -q '# BEGIN sst demo' "$file"
        grep -q alpha "$file"
    ) || fail "sst: повтор переписал файл"
    rm -rf "$work"
    ok "повтор блока sst не переписывает файл"
}

test_list
test_launch_env
test_missing_var
test_stop_on_error
test_forward
test_foreign_error_page
test_nginx_rollback
test_empty_stub_not_install
test_sst_same_bytes

printf 'tests: %s ok\n' "$PASS"
