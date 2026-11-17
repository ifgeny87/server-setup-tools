#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# Батч: пресет, при INTERACTIVE=prompt меню шагов, затем скрипты.
# Аргументы команд лежат в batch/commands.conf, не в пресете.
# Без интерактива пустой обязательный аргумент останавливает батч до скриптов.
# В интерактиве аргумент спрашивает сам скрипт, когда до него доходит очередь.
# Первая ошибка дочернего скрипта останавливает очередь.
# batch_prompt=1 только когда пресет просит ввод, есть терминал и нет --yes.

ROOT=$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PRESET_DIR="$ROOT/batch/presets"

preset_id=""
preset_title=""
preset_interactive=""
step_path=()
step_user=()
step_enabled=()
cmd_path=()
cmd_user=()
arg_cmd=()
arg_name=()
arg_type=()
arg_required=()
batch_prompt=0
menu_pos=0
menu_hold=0
menu_lines=0
add_choice=()
add_on=()

usage() {
    echo "Использование: sudo $0 [--preset <id>] [--yes] [--list]"
}

# Сбрасывает набор и читает batch/presets/<id>.conf. Аргументы берёт из каталога команд.
load_preset() {
    local id="$1"
    local file="$PRESET_DIR/${id}.conf"
    local line key val rest path
    if [ ! -f "$file" ]; then
        logerr "Нет пресета: $id"
        return 1
    fi
    load_commands || return 1
    preset_id=""
    preset_title=""
    preset_interactive=""
    step_path=()
    step_user=()
    step_enabled=()
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        if [[ "$line" == STEP\ * ]]; then
            rest="${line#STEP }"
            rest="${rest#"${rest%%[![:space:]]*}"}"
            path="${rest%%[[:space:]]*}"
            rest="${rest#"$path"}"
            rest="${rest#"${rest%%[![:space:]]*}"}"
            if [ -n "$rest" ] && [ "$rest" != "user" ]; then
                logerr "Неизвестный суффикс STEP в пресете $id: $rest"
                return 1
            fi
            if [ -z "$path" ]; then
                logerr "Пустой STEP в пресете $id"
                return 1
            fi
            step_path+=("$path")
            if [ "$rest" = "user" ] || [ "$(step_runs_as_user "$path")" = 1 ]; then
                step_user+=(1)
            else
                step_user+=(0)
            fi
            step_enabled+=(1)
            continue
        fi
        if [[ "$line" == NEED\ * ]]; then
            logerr "NEED пишут в batch/commands.conf, не в пресете $id"
            return 1
        fi
        if [[ "$line" != *=* ]]; then
            logerr "Не понял строку пресета $id: $line"
            return 1
        fi
        key="${line%%=*}"
        val="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        key="${key#"${key%%[![:space:]]*}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        case "$key" in
            ID) preset_id="$val" ;;
            TITLE) preset_title="$val" ;;
            INTERACTIVE) preset_interactive="$val" ;;
            *)
                logerr "Неизвестное поле пресета $id: $key"
                return 1
                ;;
        esac
    done < "$file"
    if [ "$preset_id" != "$id" ]; then
        logerr "ID пресета ($preset_id) не совпадает с именем файла $id"
        return 1
    fi
    if [ -z "$preset_title" ]; then
        logerr "В пресете $id нет TITLE"
        return 1
    fi
    if [ "$preset_interactive" != "prompt" ] && [ "$preset_interactive" != "no" ]; then
        logerr "В пресете $id поле INTERACTIVE должно быть prompt или no"
        return 1
    fi
    if [ "${#step_path[@]}" -eq 0 ]; then
        logerr "В пресете $id нет шагов"
        return 1
    fi
    local i path
    for i in "${!step_path[@]}"; do
        path="${step_path[$i]}"
        if [ ! -f "$ROOT/$path" ]; then
            logerr "Нет файла шага: $path"
            return 1
        fi
        if ! cmd_index "$path" >/dev/null; then
            logerr "Нет команды в batch/commands.conf: $path"
            return 1
        fi
    done
    local local_file="$PRESET_DIR/${id}.local"
    if [ -f "$local_file" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$local_file"
        set +a
    fi
}

# Абсолютный путь к файлу. Сравнение нужно, чтобы корневой .env не читать второй раз.
abs_file() {
    local dir base
    base=$(basename -- "$1")
    dir=$(cd "$(dirname -- "$1")" && pwd -P) || return 1
    printf '%s/%s\n' "$dir" "$base"
}

# Число в начале имени файла. Без числа команда встаёт в конец.
script_code() {
    local base
    base=$(basename -- "$1")
    if [[ "$base" =~ ^([0-9]+) ]]; then
        printf '%s' "$((10#${BASH_REMATCH[1]}))"
        return 0
    fi
    printf '9999'
}

# Индекс пути в каталоге команд. 1, если такой команды нет.
cmd_index() {
    local path=$1 i
    for i in "${!cmd_path[@]}"; do
        if [ "${cmd_path[$i]}" = "$path" ]; then
            printf '%s' "$i"
            return 0
        fi
    done
    return 1
}

# 1, если каталог говорит запускать скрипт от TARGET_USER.
step_runs_as_user() {
    local path=$1 idx
    if [ "${#cmd_path[@]}" -eq 0 ]; then
        printf '0'
        return 0
    fi
    idx=$(cmd_index "$path") || {
        printf '0'
        return 0
    }
    printf '%s' "${cmd_user[$idx]}"
}

# Читает batch/commands.conf. Команды уже отсортированы по коду в имени файла.
load_commands() {
    local file="$ROOT/batch/commands.conf"
    local line rest path key typ mode extra idx prev_code prev_path code
    cmd_path=()
    cmd_user=()
    arg_cmd=()
    arg_name=()
    arg_type=()
    arg_required=()
    idx=-1
    prev_code=-1
    prev_path=""
    if [ ! -f "$file" ]; then
        logerr "Нет файла команд: $file"
        return 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        if [[ "$line" == CMD\ * ]]; then
            path="${line#CMD }"
            path="${path#"${path%%[![:space:]]*}"}"
            path="${path%%[[:space:]]*}"
            if ! path_ok "$path"; then
                logerr "Нет файла команды: $path"
                return 1
            fi
            if cmd_index "$path" >/dev/null; then
                logerr "Команда повторяется: $path"
                return 1
            fi
            code=$(script_code "$path")
            if [ "$prev_code" -gt "$code" ] || { [ "$prev_code" -eq "$code" ] && [[ "$prev_path" > "$path" ]]; }; then
                logerr "Команды в batch/commands.conf не по коду файла: $path"
                return 1
            fi
            cmd_path+=("$path")
            cmd_user+=(0)
            idx=$((${#cmd_path[@]} - 1))
            prev_code=$code
            prev_path=$path
            continue
        fi
        if [ "$idx" -lt 0 ]; then
            logerr "Строка без CMD в batch/commands.conf: $line"
            return 1
        fi
        if [ "$line" = "RUN user" ]; then
            cmd_user[$idx]=1
            continue
        fi
        if [[ "$line" == ARG\ * ]]; then
            rest="${line#ARG }"
            extra=""
            read -r key typ mode extra <<< "$rest"
            if [ -n "$extra" ]; then
                logerr "Лишнее в ARG: $line"
                return 1
            fi
            if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                logerr "Некорректная переменная в batch/commands.conf: $key"
                return 1
            fi
            case "$typ" in
                string|ssh-key|email|domain|user|version|token|flag|port|ip) ;;
                *)
                    logerr "Неизвестный тип аргумента $typ у $key"
                    return 1
                    ;;
            esac
            case "$mode" in
                required|optional) ;;
                *)
                    logerr "Неизвестный режим аргумента $mode у $key"
                    return 1
                    ;;
            esac
            arg_cmd+=("$idx")
            arg_name+=("$key")
            arg_type+=("$typ")
            if [ "$mode" = "required" ]; then
                arg_required+=(1)
            else
                arg_required+=(0)
            fi
            continue
        fi
        logerr "Не понял строку batch/commands.conf: $line"
        return 1
    done < "$file"
    if [ "${#cmd_path[@]}" -eq 0 ]; then
        logerr "В batch/commands.conf нет команд"
        return 1
    fi
}

print_list() {
    local file id title line
    local found=0
    for file in "$PRESET_DIR"/*.conf; do
        [ -f "$file" ] || continue
        id=$(basename -- "$file" .conf)
        title=""
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line#"${line%%[![:space:]]*}"}"
            if [[ "$line" == TITLE=* ]]; then
                title="${line#TITLE=}"
            fi
        done < "$file"
        printf '%s\t%s\n' "$id" "$title"
        found=1
    done
    if [ "$found" -eq 0 ]; then
        logerr "В $PRESET_DIR нет пресетов"
        return 1
    fi
}

# Путь скрипта из каталогов настройки, без выхода выше корня.
path_ok() {
    local path=$1
    [[ "$path" == *.sh ]] || return 1
    [[ "$path" != *..* ]] || return 1
    case "$path" in
        1-server-setup/*|2-install-software/*|3-user-setup/*|4-services/*) ;;
        *) return 1 ;;
    esac
    [ -f "$ROOT/$path" ]
}

# Команды каталога, которых ещё нет в наборе. Порядок — как в commands.conf.
collect_add_choices() {
    local i j path skip
    add_choice=()
    for i in "${!cmd_path[@]}"; do
        path="${cmd_path[$i]}"
        skip=0
        if [ "${#step_path[@]}" -gt 0 ]; then
            for j in "${!step_path[@]}"; do
                if [ "${step_path[$j]}" = "$path" ]; then
                    skip=1
                    break
                fi
            done
        fi
        [ "$skip" -eq 1 ] && continue
        add_choice+=("$path")
    done
}

# Вставляет скрипт по числу в имени файла и отмечает его. Уже присутствующий только отмечается.
insert_step() {
    local path=$1 i code new_code placed=0 user
    local -a np=() nu=() ne=()
    if [ "${#step_path[@]}" -gt 0 ]; then
        for i in "${!step_path[@]}"; do
            if [ "${step_path[$i]}" = "$path" ]; then
                step_enabled[$i]=1
                menu_pos=$i
                logr "Уже в наборе, отмечен: $path"
                return 0
            fi
        done
    fi
    new_code=$(script_code "$path")
    user=$(step_runs_as_user "$path")
    if [ "${#step_path[@]}" -eq 0 ]; then
        step_path=("$path")
        step_user=("$user")
        step_enabled=(1)
        menu_pos=0
        logr "Добавлен шаг: $path"
        return 0
    fi
    for i in "${!step_path[@]}"; do
        if [ "$placed" -eq 0 ]; then
            code=$(script_code "${step_path[$i]}")
            if [ "$new_code" -lt "$code" ]; then
                np+=("$path")
                nu+=("$user")
                ne+=(1)
                placed=1
            fi
        fi
        np+=("${step_path[$i]}")
        nu+=("${step_user[$i]}")
        ne+=("${step_enabled[$i]}")
    done
    if [ "$placed" -eq 0 ]; then
        np+=("$path")
        nu+=("$user")
        ne+=(1)
    fi
    step_path=("${np[@]}")
    step_user=("${nu[@]}")
    step_enabled=("${ne[@]}")
    for i in "${!step_path[@]}"; do
        if [ "${step_path[$i]}" = "$path" ]; then
            menu_pos=$i
            break
        fi
    done
    logr "Добавлен шаг: $path"
}

# Переключает отметку шага в наборе.
toggle_step_at() {
    local idx=$1
    if [ "${step_enabled[$idx]}" = 1 ]; then
        step_enabled[$idx]=0
    else
        step_enabled[$idx]=1
    fi
}

# Кладёт отмеченные команды в основной набор. Если отметок нет, берёт строку под курсором.
commit_add_selection() {
    local pos=$1 i any=0 first="" path
    for i in "${!add_on[@]}"; do
        [ "${add_on[$i]}" = 1 ] && any=1
    done
    if [ "$any" -eq 1 ]; then
        for i in "${!add_choice[@]}"; do
            [ "${add_on[$i]}" = 1 ] || continue
            path="${add_choice[$i]}"
            [ -z "$first" ] && first=$path
            insert_step "$path"
        done
    elif [ "$pos" -lt "${#add_choice[@]}" ]; then
        first="${add_choice[$pos]}"
        insert_step "$first"
    fi
    if [ -n "$first" ]; then
        for i in "${!step_path[@]}"; do
            if [ "${step_path[$i]}" = "$first" ]; then
                menu_pos=$i
                break
            fi
        done
    fi
}

# Стрелки и Enter, как в скрипте 42. Экран целиком не стирается.
read_key() {
    local key rest
    KEY=""
    IFS= read -rsn1 key || return 1
    if [ "$key" = $'\e' ]; then
        IFS= read -rsn2 -t 1 rest || rest=""
        KEY="ESC$rest"
    elif [ -z "$key" ]; then
        KEY=ENTER
    else
        KEY=$key
    fi
}

# Поднять курсор на n строк и стереть вниз. Коды tput идут в терминал, не в /dev/null.
menu_rewind() {
    local n=$1
    [ -t 1 ] || return 1
    if tput cuu "$n" && tput ed; then
        return 0
    fi
    printf '\033[%sA\033[J' "$n"
}

# Список шагов пресета, затем пункты добавить, выполнить и выйти.
draw_batch_menu() {
    local i mark plain title rows action_at n
    rows=$((${#step_path[@]} + 3))
    action_at=${#step_path[@]}
    n=0
    if [ "$menu_hold" -eq 1 ] && [ "$menu_lines" -gt 0 ]; then
        menu_rewind "$menu_lines" || true
    fi
    title="Пресет: $preset_id"
    if [ -n "$preset_title" ]; then
        title="$title — $preset_title"
    fi
    printf '%b%s%b\n' "$COL_FG_WHITE" "$title" "$COL_RES"
    for i in "${!step_path[@]}"; do
        if [ "${step_enabled[$i]}" = 1 ]; then
            plain="[x]"
            mark=$(printf '%b%s%b' "$COL_LIME" "[x]" "$COL_RES")
        else
            plain="[ ]"
            mark=$(printf '%b%s%b' "$COL_FG_GRAY" "[ ]" "$COL_RES")
        fi
        if [ "$i" -eq "$menu_pos" ]; then
            tput rev 2>/dev/null || true
            printf '  %s  %s\n' "$plain" "${step_path[$i]}"
            tput sgr0 2>/dev/null || true
        else
            printf '  %s  %s\n' "$mark" "${step_path[$i]}"
        fi
    done
    for i in "a  Добавить команду" "Выполнить" "Выход"; do
        if [ "$menu_pos" -eq $((action_at + n)) ]; then
            tput rev 2>/dev/null || true
            printf '  %s\n' "$i"
            tput sgr0 2>/dev/null || true
        else
            printf '  %s\n' "$i"
        fi
        n=$((n + 1))
    done
    printf '%b%s%b\n' "$COL_FG_GRAY" "Стрелки — выбор, пробел — отметить, a — добавить, Enter — подтвердить, q — выход" "$COL_RES"
    menu_lines=$((rows + 2))
    menu_hold=1
}

# Список команд, которых нет в наборе, и пункт «Назад». pos — текущая строка.
draw_add_menu() {
    local pos=$1 i plain mark
    if [ "$add_hold" -eq 1 ] && [ "$add_lines" -gt 0 ]; then
        menu_rewind "$add_lines" || true
    fi
    printf '%b%s%b\n' "$COL_FG_WHITE" "Добавить команду" "$COL_RES"
    for i in "${!add_choice[@]}"; do
        if [ "${add_on[$i]}" = 1 ]; then
            plain="[x]"
            mark=$(printf '%b%s%b' "$COL_LIME" "[x]" "$COL_RES")
        else
            plain="[ ]"
            mark=$(printf '%b%s%b' "$COL_FG_GRAY" "[ ]" "$COL_RES")
        fi
        if [ "$i" -eq "$pos" ]; then
            tput rev 2>/dev/null || true
            printf '  %s  %s\n' "$plain" "${add_choice[$i]}"
            tput sgr0 2>/dev/null || true
        else
            printf '  %s  %s\n' "$mark" "${add_choice[$i]}"
        fi
    done
    if [ "$pos" -eq "${#add_choice[@]}" ]; then
        tput rev 2>/dev/null || true
        printf '  %s\n' "Назад"
        tput sgr0 2>/dev/null || true
    else
        printf '  %s\n' "Назад"
    fi
    printf '%b%s%b\n' "$COL_FG_GRAY" "Стрелки — выбор, пробел — отметить, Enter — добавить, q — назад" "$COL_RES"
    add_lines=$((${#add_choice[@]} + 3))
    add_hold=1
}

# Меню добавления вместо ручного пути. 0 — вернулись в список шагов.
pick_step() {
    local pos=0 rows choice
    collect_add_choices
    if [ "$menu_hold" -eq 1 ] && [ "$menu_lines" -gt 0 ]; then
        menu_rewind "$menu_lines" || true
    fi
    menu_hold=0
    if [ "${#add_choice[@]}" -eq 0 ]; then
        logr "Нечего добавить: все команды уже в списке"
        return 0
    fi
    add_hold=0
    add_lines=0
    add_on=()
    for choice in "${add_choice[@]}"; do
        add_on+=(0)
    done
    while true; do
        draw_add_menu "$pos"
        read_key || return 1
        rows=$((${#add_choice[@]} + 1))
        case "$KEY" in
            ESC'[A') pos=$(((pos + rows - 1) % rows)) ;;
            ESC'[B') pos=$(((pos + 1) % rows)) ;;
            ' ')
                if [ "$pos" -lt "${#add_choice[@]}" ]; then
                    if [ "${add_on[$pos]}" = 1 ]; then
                        add_on[$pos]=0
                    else
                        add_on[$pos]=1
                    fi
                fi
                ;;
            q)
                menu_rewind "$add_lines" || true
                add_hold=0
                return 0
                ;;
            ENTER)
                menu_rewind "$add_lines" || true
                add_hold=0
                if [ "$pos" -eq "${#add_choice[@]}" ]; then
                    return 0
                fi
                commit_add_selection "$pos"
                return 0
                ;;
        esac
    done
}

# Возвращает 0, когда набор подтверждён. 2 — выход без запуска.
confirm_steps() {
    local rows
    menu_pos=0
    menu_hold=0
    while true; do
        rows=$((${#step_path[@]} + 3))
        draw_batch_menu
        read_key || return 1
        case "$KEY" in
            ESC'[A') menu_pos=$(((menu_pos + rows - 1) % rows)) ;;
            ESC'[B') menu_pos=$(((menu_pos + 1) % rows)) ;;
            ' ')
                if [ "$menu_pos" -lt "${#step_path[@]}" ]; then
                    toggle_step_at "$menu_pos"
                fi
                ;;
            a|A)
                pick_step || return 1
                ;;
            q) return 2 ;;
            ENTER)
                if [ "$menu_pos" -eq $((${#step_path[@]})) ]; then
                    pick_step || return 1
                elif [ "$menu_pos" -eq $((${#step_path[@]} + 1)) ]; then
                    menu_hold=0
                    return 0
                elif [ "$menu_pos" -eq $((${#step_path[@]} + 2)) ]; then
                    menu_hold=0
                    return 2
                fi
                ;;
        esac
    done
}

env_value() {
    local var="$1"
    eval "printf '%s' \"\${$var-}\""
}

set_env_value() {
    local var="$1" val="$2"
    printf -v "$var" '%s' "$val"
    export "$var"
}

# Имена обязательных аргументов отмеченных шагов, которых нет в окружении.
missing_required() {
    local i path idx j name seen="" val
    for i in "${!step_path[@]}"; do
        [ "${step_enabled[$i]}" = 1 ] || continue
        path="${step_path[$i]}"
        idx=$(cmd_index "$path") || continue
        for j in "${!arg_cmd[@]}"; do
            [ "${arg_cmd[$j]}" = "$idx" ] || continue
            [ "${arg_required[$j]}" = 1 ] || continue
            name="${arg_name[$j]}"
            case " $seen " in
                *" $name "*) continue ;;
            esac
            val=$(env_value "$name")
            if [ -z "$val" ]; then
                printf '%s\n' "$name"
                seen="$seen $name"
            else
                export "$name"
            fi
        done
    done
}

# Без интерактива останавливает батч, если обязательного аргумента нет.
# В интерактиве ничего не проверяет: значение спросит сам скрипт.
require_args() {
    local name
    local -a missing=()
    [ "$batch_prompt" -eq 1 ] && return 0
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        missing+=("$name")
    done < <(missing_required)
    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi
    for name in "${missing[@]}"; do
        logerr "Нет переменной $name"
    done
    return 1
}

# Спрашивает TARGET_USER сразу перед шагом, который запускается от пользователя.
prompt_target_user() {
    local answer
    if [ -n "${TARGET_USER:-}" ]; then
        export TARGET_USER
        return 0
    fi
    if [ "$batch_prompt" -ne 1 ]; then
        logerr "Нет переменной TARGET_USER"
        return 1
    fi
    while true; do
        read -r -p "Пользователь, от которого запустить шаг: " answer || {
            logerr "Ввод закрыт"
            return 1
        }
        if [ -n "$answer" ]; then
            set_env_value TARGET_USER "$answer"
            return 0
        fi
        logr "Пустое значение не принимается: TARGET_USER"
    done
}

enabled_count() {
    local i n=0
    for i in "${!step_enabled[@]}"; do
        [ "${step_enabled[$i]}" = 1 ] && n=$((n + 1))
    done
    echo "$n"
}

run_steps() {
    local i path script code name started=0 finished=0
    for i in "${!step_path[@]}"; do
        [ "${step_enabled[$i]}" = 1 ] || continue
        path="${step_path[$i]}"
        script="$ROOT/$path"
        name=$(basename -- "$path")
        if [ "$started" -eq 1 ]; then
            echo
        fi
        started=1
        finished=$((finished + 1))
        if [ "$name" = "13-ssh-restrict.sh" ]; then
            logwarn "Сейчас сменится порт SSH на ${SSH_PORT:-порт из .env}. Текущая сессия оборвётся"
        fi
        log "${COL_FG_WHITE}# ${name}${COL_RES}"
        set +e
        if [ "${step_user[$i]}" = 1 ]; then
            prompt_target_user || exit 1
            sudo -u "$TARGET_USER" -H bash "$script"
        else
            bash "$script"
        fi
        code=$?
        set -e
        if [ "$code" -ne 0 ]; then
            log "${COL_RED}[ERROR] Остановлено на ${path}, код ${code}${COL_RES}"
            exit "$code"
        fi
        log "${COL_LIME}[OK] ${name}${COL_RES}"
    done
    log "${COL_LIME}[OK] Готово, шагов: ${finished}${COL_RES}"
}

main() {
    local preset_arg="" yes=0 do_list=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --preset)
                if [ $# -lt 2 ]; then
                    logerr "У --preset нет id"
                    usage
                    exit 1
                fi
                preset_arg="$2"
                shift 2
                ;;
            --yes)
                yes=1
                shift
                ;;
            --list)
                do_list=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                logerr "Неизвестный аргумент: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [ "$do_list" -eq 1 ]; then
        print_list
        exit 0
    fi

    if [ ! -t 0 ]; then
        if [ -z "$preset_arg" ] || [ "$yes" -ne 1 ]; then
            logerr "Нет терминала. Нужны флаги --preset и --yes"
            exit 1
        fi
    fi

    local env_file="$ROOT/.env" launch_env launch_abs repo_abs
    if [ ! -f "$env_file" ]; then
        logerr "Файл $env_file не найден!"
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$env_file"
    launch_env="$PWD/.env"
    if [ -f "$launch_env" ]; then
        repo_abs=$(abs_file "$env_file") || exit 1
        launch_abs=$(abs_file "$launch_env") || exit 1
        if [ "$launch_abs" != "$repo_abs" ]; then
            logr "Читаем .env из каталога запуска: $launch_abs"
            set -a
            # shellcheck disable=SC1090
            . "$launch_env"
            set +a
        fi
    fi

    if [ -z "$preset_arg" ]; then
        preset_arg=default
    fi
    load_preset "$preset_arg"

    batch_prompt=0
    if [ "$preset_interactive" = "prompt" ] && [ -t 0 ] && [ "$yes" -eq 0 ]; then
        batch_prompt=1
    fi

    # Без меню нехватку аргументов сообщаем до root и до первого скрипта.
    if [ "$batch_prompt" -ne 1 ]; then
        require_args || exit 1
    fi

    checkRoot

    if [ "$batch_prompt" -eq 1 ]; then
        local menu_status=0
        if confirm_steps; then
            menu_status=0
        else
            menu_status=$?
        fi
        if [ "$menu_status" -eq 2 ]; then
            exit 0
        fi
        if [ "$menu_status" -ne 0 ]; then
            exit "$menu_status"
        fi
    fi

    if [ "$(enabled_count)" -eq 0 ]; then
        log "Нет отмеченных шагов"
        exit 0
    fi

    run_steps
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
