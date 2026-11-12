# Цвет только в терминале. NO_COLOR или перенаправление в файл оставляют метки без ANSI.
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then
    COL_RES="\033[0m"
    COL_RED="\033[31;40m"
    COL_LIME="\033[92;40m"
    COL_GRAY="\033[37;40m"
    COL_FG_BLUE="\033[0;34m"
    COL_FG_WHITE="\033[97m"
    COL_FG_YELLOW="\033[93m"
    COL_FG_GRAY="\033[37m"
else
    COL_RES=""
    COL_RED=""
    COL_LIME=""
    COL_GRAY=""
    COL_FG_BLUE=""
    COL_FG_WHITE=""
    COL_FG_YELLOW=""
    COL_FG_GRAY=""
fi

# timestamp [OPTION] - prints formatted timestamp
# options:
#   h - human format 'dd.mm.YYYY HH:MM:SS'
#   s - short format 'YYYYmmdd-HHMMSS'
#   t - human time format 'HH:MM:SS'
#   default - ISO format 'YYYY-mm-dd HH:MM:SS'
function timestamp() {
	FORMAT=${1:-}
    if [[ "$FORMAT" == "h" ]]; then date +"%d.%m.%Y %H:%M:%S"
    elif [[ "$FORMAT" == "s" ]]; then date +"%Y%m%d-%H%M%S"
    elif [[ "$FORMAT" == "t" ]]; then date +"%H:%M:%S"
    else date +"%Y-%m-%d %H:%M:%S"
    fi
}

# log simple
function log() {
    echo -e "[$(timestamp t)] $*"
}

# log big step
function loghead() {
    echo -e "\n#-----------------------------------------------------------"
    printf "# "
    log "$*"
    echo -e "#-----------------------------------------------------------\n"
}

# log small step
function logr() {
    log "${COL_FG_BLUE}$*${COL_RES}"
}

# log debug
function logd() {
    log "${COL_GRAY}[DEBUG]${COL_RES} $*"
}

# log OK
function logok() {
    log "${COL_LIME}[OK]${COL_RES} $*"
}

# log warn text
function logwarn() {
    log "${COL_FG_YELLOW}[WARN]${COL_RES} $*"
}

# log error text
function logerr() {
    log "${COL_RED}[ERROR]${COL_RES} $*"
}

# Проверка прав суперпользователя
function checkRoot() {
    if [ "$UID" -ne 0 ]; then
        logerr "Запустите скрипт с правами суперпользователя (sudo)"
        exit 1
    fi
}

# Загружает .env
function loadEnv() {
	ENV_FILE="$(dirname -- "$0")/../.env"

    if [ ! -f "$ENV_FILE" ]; then
        logerr "Файл $ENV_FILE не найден!"
        exit 1
    fi
    source "$ENV_FILE"
}

# Пишет stdin в файл только если содержимое отличается.
# SST_FILE_CHANGED=1, если файл записан, иначе 0.
function sst_write_if_changed() {
    local dest="$1"
    local tmp
    tmp=$(mktemp)
    cat > "$tmp"
    SST_FILE_CHANGED=0
    if [ -f "$dest" ] && cmp -s "$dest" "$tmp"; then
        rm -f "$tmp"
        return 0
    fi
    mkdir -p "$(dirname -- "$dest")"
    cat "$tmp" > "$dest"
    rm -f "$tmp"
    SST_FILE_CHANGED=1
}

# Заменяет блок между метками BEGIN/END sst. Совпавший блок файл не трогает.
# Текст вне блока сохраняется. SST_FILE_CHANGED=1, если файл записан.
function sst_replace_block() {
    local file="$1"
    local name="$2"
    local body="$3"
    local begin="# BEGIN sst ${name}"
    local end="# END sst ${name}"
    local current=""
    local tmp
    SST_FILE_CHANGED=0
    if [ -f "$file" ]; then
        current=$(awk -v b="$begin" -v e="$end" '
            $0 == b { grab = 1; next }
            $0 == e { grab = 0; next }
            grab { print }
        ' "$file")
    fi
    if [ "$current" = "$body" ]; then
        return 0
    fi
    tmp=$(mktemp)
    if [ -f "$file" ]; then
        awk -v b="$begin" -v e="$end" '
            $0 == b { skip = 1; next }
            $0 == e { skip = 0; next }
            skip { next }
            { print }
        ' "$file" > "$tmp"
    fi
    {
        if [ -s "$tmp" ]; then
            cat "$tmp"
            echo
        fi
        printf '%s\n' "$begin"
        printf '%s\n' "$body"
        printf '%s\n' "$end"
    } > "${tmp}.new"
    sst_write_if_changed "$file" < "${tmp}.new"
    rm -f "$tmp" "${tmp}.new"
}
