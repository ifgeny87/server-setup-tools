#!/bin/bash
set -euo pipefail
. "$(dirname -- "$0")/../common/_misc.sh" # load misc

# Общая страница ошибок nginx. Запускать после 24-install-nginx-certbot.sh.
# Повтор безопасен: include в server не дублируется.

checkRoot

if ! command -v nginx >/dev/null 2>&1; then
    logerr "nginx не установлен. Сначала выполните 2-install-software/24-install-nginx-certbot.sh"
    exit 1
fi

loghead "Страницы ошибок nginx"

PAGE=/var/www/nginx-errors/error.html
SNIPPET=/etc/nginx/snippets/sst-errors.conf
INCLUDE_LINE="include /etc/nginx/snippets/sst-errors.conf;"

mkdir -p /var/www/nginx-errors /etc/nginx/snippets

cat > "$PAGE" <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>status</title>
<style>
:root {
  color-scheme: light dark;
  --bg: #e7efe4;
  --ink: #142018;
  --dim: #3c5344;
  --accent: #0c6b34;
  --line: #1a3324;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #07110c;
    --ink: #b6f7c9;
    --dim: #6f9a7c;
    --accent: #3dff8a;
    --line: #1c3d2a;
  }
}
body {
  margin: 0;
  min-height: 100vh;
  background: var(--bg);
  color: var(--ink);
  font: 15px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}
main { max-width: 40rem; margin: 12vh auto; padding: 0 1.2rem; }
.box { border: 1px solid var(--line); padding: 1rem 1.1rem; }
.prompt { margin: 0 0 .6rem; color: var(--dim); }
h1 { margin: 0 0 .8rem; font-size: 2.6rem; font-weight: 650; letter-spacing: .04em; color: var(--accent); }
p { margin: .25rem 0; color: var(--dim); }
b { color: var(--ink); font-weight: 600; }
</style>
</head>
<body>
<main>
  <div class="box">
    <p class="prompt">root@nginx:~# status</p>
    <h1 id="code"><!--# echo var="status" default="000" --></h1>
    <p>server <b>nginx/<!--# echo var="nginx_version" default="" --></b></p>
    <p>url <b><!--# echo var="scheme" default="" -->://<!--# echo var="host" default="" --><!--# echo var="request_uri" default="" --></b></p>
    <p>time <b><!--# echo var="time_iso8601" default="" --></b></p>
  </div>
</main>
<script>
var code = document.getElementById("code").textContent.trim();
if (code) document.title = code;
</script>
</body>
</html>
EOF

cat > "$SNIPPET" <<'EOF'
error_page 400 =400 @sst_error;
error_page 401 =401 @sst_error;
error_page 403 =403 @sst_error;
error_page 404 =404 @sst_error;
error_page 405 =405 @sst_error;
error_page 408 =408 @sst_error;
error_page 413 =413 @sst_error;
error_page 414 =414 @sst_error;
error_page 429 =429 @sst_error;
error_page 500 =500 @sst_error;
error_page 502 =502 @sst_error;
error_page 503 =503 @sst_error;
error_page 504 =504 @sst_error;

location @sst_error {
    internal;
    ssi on;
    ssi_types text/html;
    ssi_silent_errors on;
    default_type text/html;
    root /var/www/nginx-errors;
    rewrite ^ /error.html break;
    add_header Cache-Control "no-store" always;
}
EOF

# Вставляет include один раз в каждый server, если его там ещё нет.
add_error_include() {
    local src="$1"
    local tmp
    [ -f "$src" ] || return 0
    tmp=$(mktemp)
    awk '
        function opens(s,    t) { t = s; return gsub(/\{/, "{", t) }
        function closes(s,    t) { t = s; return gsub(/\}/, "}", t) }
        function emit(    i) {
            if (n == 0) return
            if (has) {
                for (i = 1; i <= n; i++) print lines[i]
            } else {
                print lines[1]
                print "    include /etc/nginx/snippets/sst-errors.conf;"
                for (i = 2; i <= n; i++) print lines[i]
            }
            n = 0
            has = 0
            in_server = 0
            depth = 0
        }
        BEGIN { depth = 0; in_server = 0; n = 0; has = 0 }
        {
            o = opens($0)
            c = closes($0)
            if (!in_server && $0 ~ /^[[:space:]]*server[[:space:]]*\{/) {
                in_server = 1
                n = 1
                lines[1] = $0
                depth = o - c
                if (depth <= 0) emit()
                next
            }
            if (in_server) {
                n++
                lines[n] = $0
                if ($0 ~ /include[[:space:]]+\/etc\/nginx\/snippets\/sst-errors\.conf[[:space:]]*;/) has = 1
                depth += o - c
                if (depth <= 0) emit()
                next
            }
            print
        }
        END { if (in_server) emit() }
    ' "$src" > "$tmp"
    if ! cmp -s "$src" "$tmp"; then
        cat "$tmp" > "$src"
        logr "Подключена страница ошибок: $src"
    fi
    rm -f "$tmp"
}

shopt -s nullglob
for conf in /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/*; do
    [ -f "$conf" ] || continue
    add_error_include "$conf"
done
shopt -u nullglob

logr "Проверяем конфиг nginx..."
if ! nginx -t; then
    logerr "nginx -t не прошёл, reload не выполнен"
    exit 1
fi
if ! nginx -s reload; then
    logerr "Не удалось перечитать nginx"
    exit 1
fi

logok "Страница ошибок nginx: $PAGE"
