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
