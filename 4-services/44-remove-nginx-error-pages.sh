#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# Снимает кастомные страницы ошибок и возвращает штатные ответы nginx.
# Пустая заглушка сниппета, сертификат default-reject и чужие файлы не трогает.

PAGE=${PAGE:-/var/www/nginx-errors/error.html}
SNIPPET=${SNIPPET:-/etc/nginx/snippets/sst-errors.conf}
NGINX_CONF_D=${NGINX_CONF_D:-/etc/nginx/conf.d}
NGINX_SITES=${NGINX_SITES:-/etc/nginx/sites-enabled}

snippet_re() {
    printf '%s' "$SNIPPET" | sed -e 's/[.[*^$()+?{|\\]/\\&/g'
}

# Канонический путь без завершающего симлинка. Нужен, чтобы один файл не править дважды.
resolve_path() {
    local path=$1 target dir guard=0
    case "$path" in
        /*) ;;
        *) path=$PWD/$path ;;
    esac
    while [ -L "$path" ]; do
        guard=$((guard + 1))
        [ "$guard" -le 20 ] || break
        target=$(readlink "$path")
        case "$target" in
            /*) path=$target ;;
            *) path=$(dirname -- "$path")/$target ;;
        esac
    done
    dir=$(cd "$(dirname -- "$path")" && pwd -P)
    printf '%s\n' "$dir/$(basename -- "$path")"
}

include_line() {
    local pre
    pre=$(snippet_re)
    grep -Eq "^[[:space:]]*include[[:space:]]+${pre}[[:space:]]*;[[:space:]]*$" "$1"
}

# Страницы стоят, если есть директивы сниппета, сам HTML или непустой сниппет вместе с include.
pages_applied() {
    local conf nullglob_was=0 applied=1
    if [ -f "$SNIPPET" ] && grep -Eq 'error_page|@sst_error' "$SNIPPET"; then
        return 0
    fi
    if [ -f "$PAGE" ]; then
        return 0
    fi
    if [ ! -s "$SNIPPET" ]; then
        return 1
    fi
    shopt -q nullglob && nullglob_was=1
    shopt -s nullglob
    for conf in "$NGINX_CONF_D"/*.conf "$NGINX_SITES"/*; do
        [ -f "$conf" ] || continue
        if include_line "$conf"; then
            applied=0
            break
        fi
    done
    [ "$nullglob_was" -eq 0 ] && shopt -u nullglob
    return "$applied"
}

# Собирает конфиги с include. Повтор одного inode и sites-available сами по себе не обходятся.
collect_targets() {
    local conf canon nullglob_was=0
    : > "$BACKUP/targets"
    : > "$BACKUP/seen"
    shopt -q nullglob && nullglob_was=1
    shopt -s nullglob
    for conf in "$NGINX_CONF_D"/*.conf "$NGINX_SITES"/*; do
        [ -f "$conf" ] || continue
        include_line "$conf" || continue
        canon=$(resolve_path "$conf")
        if grep -Fxq "$canon" "$BACKUP/seen"; then
            continue
        fi
        printf '%s\n' "$canon" >> "$BACKUP/seen"
        printf '%s\n' "$conf" >> "$BACKUP/targets"
    done
    [ "$nullglob_was" -eq 0 ] && shopt -u nullglob
}

strip_includes() {
    local conf tmp pre
    pre=$(snippet_re)
    while IFS= read -r conf; do
        [ -n "$conf" ] || continue
        tmp=$(mktemp)
        awk -v pre="$pre" '
            $0 ~ ("^[[:space:]]*include[[:space:]]+" pre "[[:space:]]*;[[:space:]]*$") { next }
            { print }
        ' "$conf" > "$tmp"
        cat "$tmp" > "$conf"
        rm -f "$tmp"
    done < "$BACKUP/targets"
}

backup_targets() {
    local conf n=0
    while IFS= read -r conf; do
        [ -n "$conf" ] || continue
        n=$((n + 1))
        cp "$conf" "$BACKUP/conf.$n"
        printf '%s\n' "$conf" > "$BACKUP/confpath.$n"
    done < "$BACKUP/targets"
    printf '%s\n' "$n" > "$BACKUP/count"
}

# Возвращает конфиги, сниппет и страницу, если nginx -t не принял снятие.
restore_removed() {
    local n=0 i path
    if [ -f "$BACKUP/count" ]; then
        n=$(cat "$BACKUP/count")
    fi
    i=1
    while [ "$i" -le "$n" ]; do
        path=$(cat "$BACKUP/confpath.$i")
        cat "$BACKUP/conf.$i" > "$path"
        i=$((i + 1))
    done
    if [ "$HAD_PAGE" -eq 1 ]; then
        mkdir -p "$(dirname -- "$PAGE")"
        cat "$BACKUP/page" > "$PAGE"
    fi
    if [ "$HAD_SNIPPET" -eq 1 ]; then
        mkdir -p "$(dirname -- "$SNIPPET")"
        cat "$BACKUP/snippet" > "$SNIPPET"
    fi
}

remove_page_files() {
    if [ -f "$PAGE" ]; then
        rm -f "$PAGE"
        rmdir "$(dirname -- "$PAGE")" 2>/dev/null || true
    fi
    if [ -f "$SNIPPET" ]; then
        rm -f "$SNIPPET"
        rmdir "$(dirname -- "$SNIPPET")" 2>/dev/null || true
    fi
}

main() {
    checkRoot
    loghead "Снятие страниц ошибок nginx"
    if ! pages_applied; then
        logok "кастомные страницы не применены"
        exit 0
    fi

    BACKUP=$(mktemp -d)
    HAD_PAGE=0
    HAD_SNIPPET=0
    if [ -f "$PAGE" ]; then
        cp "$PAGE" "$BACKUP/page"
        HAD_PAGE=1
    fi
    if [ -f "$SNIPPET" ]; then
        cp "$SNIPPET" "$BACKUP/snippet"
        HAD_SNIPPET=1
    fi
    collect_targets
    backup_targets
    strip_includes
    remove_page_files

    if command -v nginx >/dev/null 2>&1; then
        if ! nginx -t; then
            restore_removed
            rm -rf "$BACKUP"
            logerr "nginx -t не прошёл, reload не выполнен"
            exit 1
        fi
        rm -rf "$BACKUP"
        if ! nginx -s reload; then
            logerr "Не удалось перечитать nginx"
            exit 1
        fi
    else
        rm -rf "$BACKUP"
        logr "nginx не установлен, reload не выполнялся"
    fi
    logok "Кастомные страницы ошибок сняты"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
