#!/bin/bash
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../common/_misc.sh" # load misc

# Батч: пресет, при INTERACTIVE=prompt меню шагов, вопросы NEED, затем скрипты.
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
need_step=()
need_var=()
need_prompt=()
batch_prompt=0
menu_pos=0
menu_hold=0
menu_lines=0

usage() {
    echo "Использование: sudo $0 [--preset <id>] [--yes] [--list]"
}

# Сбрасывает набор и читает batch/presets/<id>.conf. NEED относится к предыдущему STEP.
load_preset() {
    local id="$1"
    local file="$PRESET_DIR/${id}.conf"
    local line key val rest prompt path
    local step_index=-1
    if [ ! -f "$file" ]; then
        logerr "Нет пресета: $id"
        return 1
    fi
    preset_id=""
    preset_title=""
    preset_interactive=""
    step_path=()
    step_user=()
    step_enabled=()
    need_step=()
    need_var=()
    need_prompt=()
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
            if [ "$rest" = "user" ] || is_user_script "$path"; then
                step_user+=(1)
            else
                step_user+=(0)
            fi
            step_enabled+=(1)
            step_index=$((${#step_path[@]} - 1))
            continue
        fi
        if [[ "$line" == NEED\ * ]]; then
            if [ "$step_index" -lt 0 ]; then
                logerr "NEED без STEP в пресете $id"
                return 1
            fi
            rest="${line#NEED }"
            key="${rest%%[[:space:]]*}"
            if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                logerr "Некорректная переменная в пресете $id: $key"
                return 1
            fi
            prompt=""
            if [[ "$rest" =~ prompt=\"(.*)\" ]]; then
                prompt="${BASH_REMATCH[1]}"
            fi
            add_need "$step_index" "$key" "$prompt"
            continue
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
        if [ "${step_user[$i]}" = 1 ]; then
            add_need "$i" "TARGET_USER" "Пользователь, от которого запустить $path"
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

# Шаги 20 и 30 всегда от TARGET_USER, даже без суффикса user в пресете.
is_user_script() {
    local base
    base=$(basename -- "$1")
    [ "$base" = "20-install-oh-my-zsh.sh" ] || [ "$base" = "30-setup-user-tools.sh" ]
}

add_need() {
    local idx="$1" var="$2" prompt="$3" j
    if [ "${#need_var[@]}" -gt 0 ]; then
        for j in "${!need_var[@]}"; do
            if [ "${need_step[$j]}" = "$idx" ] && [ "${need_var[$j]}" = "$var" ]; then
                if [ -n "$prompt" ] && [ -z "${need_prompt[$j]}" ]; then
                    need_prompt[$j]="$prompt"
                fi
                return 0
            fi
        done
    fi
    need_step+=("$idx")
    need_var+=("$var")
    need_prompt+=("$prompt")
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

# NEED этого пути из всех пресетов. Повтор той же переменной не дублируется.
import_needs_for() {
    local path=$1 idx=$2 file line rest key prompt step_here
    for file in "$PRESET_DIR"/*.conf; do
        [ -f "$file" ] || continue
        step_here=0
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [ -z "$line" ] && continue
            [[ "$line" == \#* ]] && continue
            if [[ "$line" == STEP\ * ]]; then
                rest="${line#STEP }"
                rest="${rest#"${rest%%[![:space:]]*}"}"
                rest="${rest%%[[:space:]]*}"
                if [ "$rest" = "$path" ]; then
                    step_here=1
                else
                    step_here=0
                fi
                continue
            fi
            if [ "$step_here" -eq 1 ] && [[ "$line" == NEED\ * ]]; then
                rest="${line#NEED }"
                key="${rest%%[[:space:]]*}"
                prompt=""
                if [[ "$rest" =~ prompt=\"(.*)\" ]]; then
                    prompt="${BASH_REMATCH[1]}"
                fi
                add_need "$idx" "$key" "$prompt"
            fi
        done < "$file"
    done
}

# Добавляет скрипт в конец набора и отмечает его. Уже присутствующий только отмечается.
append_step() {
    local path=$1 i idx
    for i in "${!step_path[@]}"; do
        if [ "${step_path[$i]}" = "$path" ]; then
            step_enabled[$i]=1
            menu_pos=$i
            logr "Уже в наборе, отмечен: $path"
            return 0
        fi
    done
    step_path+=("$path")
    if is_user_script "$path"; then
        step_user+=(1)
    else
        step_user+=(0)
    fi
    step_enabled+=(1)
    idx=$((${#step_path[@]} - 1))
    if is_user_script "$path"; then
        add_need "$idx" "TARGET_USER" "Пользователь, от которого запустить $path"
    fi
    import_needs_for "$path" "$idx"
    menu_pos=$idx
    logr "Добавлен шаг: $path"
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

# Список шагов пресета, затем пункты добавить, выполнить и выйти.
draw_batch_menu() {
    local i mark plain title rows action_at n
    rows=$((${#step_path[@]} + 3))
    action_at=${#step_path[@]}
    n=0
    if [ "$menu_hold" -eq 1 ] && [ "$menu_lines" -gt 0 ]; then
        if tput cuu "$menu_lines" >/dev/null 2>&1; then
            tput ed >/dev/null 2>&1 || true
        fi
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
    for i in "Добавить команду" "Выполнить" "Выход"; do
        if [ "$menu_pos" -eq $((action_at + n)) ]; then
            tput rev 2>/dev/null || true
            printf '  %s\n' "$i"
            tput sgr0 2>/dev/null || true
        else
            printf '  %s\n' "$i"
        fi
        n=$((n + 1))
    done
    printf '%b%s%b\n' "$COL_FG_GRAY" "Стрелки — выбор, Enter — переключить или подтвердить, q — выход" "$COL_RES"
    menu_lines=$((rows + 2))
    menu_hold=1
}

# Возвращает 0, когда набор подтверждён. 2 — выход без запуска.
confirm_steps() {
    local rows idx path
    menu_pos=0
    menu_hold=0
    while true; do
        rows=$((${#step_path[@]} + 3))
        draw_batch_menu
        read_key || return 1
        case "$KEY" in
            ESC'[A') menu_pos=$(((menu_pos + rows - 1) % rows)) ;;
            ESC'[B') menu_pos=$(((menu_pos + 1) % rows)) ;;
            q) return 2 ;;
            ENTER)
                if [ "$menu_pos" -lt "${#step_path[@]}" ]; then
                    idx=$menu_pos
                    if [ "${step_enabled[$idx]}" = 1 ]; then
                        step_enabled[$idx]=0
                    else
                        step_enabled[$idx]=1
                    fi
                elif [ "$menu_pos" -eq $((${#step_path[@]})) ]; then
                    menu_hold=0
                    if ! IFS= read -r -p "Путь скрипта от корня репозитория: " path; then
                        logerr "Ввод закрыт"
                        return 1
                    fi
                    if [ -z "$path" ]; then
                        logr "Добавление отменено"
                    elif ! path_ok "$path"; then
                        logr "Нет такого скрипта: $path"
                    else
                        append_step "$path"
                    fi
                elif [ "$menu_pos" -eq $((${#step_path[@]} + 1)) ]; then
                    menu_hold=0
                    return 0
                else
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

# Спрашивает переменные только отмеченных шагов. Пустое значение не принимается.
collect_needs() {
    local j idx var prompt text answer val
    local -a missing
    missing=()
    for j in "${!need_var[@]}"; do
        idx="${need_step[$j]}"
        [ "${step_enabled[$idx]}" = 1 ] || continue
        var="${need_var[$j]}"
        val=$(env_value "$var")
        if [ -n "$val" ]; then
            export "$var"
            continue
        fi
        if [ "$batch_prompt" -ne 1 ]; then
            local already=0 m
            for m in "${missing[@]+"${missing[@]}"}"; do
                [ "$m" = "$var" ] && already=1
            done
            [ "$already" -eq 1 ] || missing+=("$var")
            continue
        fi
        prompt="${need_prompt[$j]}"
        [ -n "$prompt" ] || prompt="$var"
        if [ "$var" = "VERSION" ] && [[ "$prompt" != *"(26)"* ]]; then
            prompt="$prompt (26)"
        fi
        while true; do
            read -r -p "$prompt: " answer || {
                logerr "Ввод закрыт"
                return 1
            }
            if [ -z "$answer" ] && [ "$var" = "VERSION" ]; then
                answer=26
            fi
            if [ -n "$answer" ]; then
                set_env_value "$var" "$answer"
                break
            fi
            logr "Пустое значение не принимается: $var"
        done
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        for var in "${missing[@]}"; do
            logerr "Нет переменной $var"
        done
        return 1
    fi
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

    # Без меню нехватку NEED сообщаем до root и до первого скрипта.
    if [ "$batch_prompt" -ne 1 ]; then
        collect_needs || exit 1
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
        collect_needs || exit 1
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
