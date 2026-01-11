#!/bin/bash
# TK CLI Logging Library
# Logging, output formatting, and UI functions

#----------------------------------------------------
# COLOR DEFINITIONS
#----------------------------------------------------
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

#----------------------------------------------------
# LOGGING CONFIGURATION
#----------------------------------------------------
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export LOG_FILE="${LOG_FILE:-/tmp/tk.log}"

# Get numeric log level
get_log_level_value() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO) echo 1 ;;
        WARN) echo 2 ;;
        ERROR) echo 3 ;;
        FATAL) echo 4 ;;
        *) echo 1 ;; # Default to INFO
    esac
}

# Main logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local current_level_value=$(get_log_level_value "$LOG_LEVEL")
    local message_level_value=$(get_log_level_value "$level")

    if [[ $message_level_value -ge $current_level_value ]]; then
        local color=""
        case "$level" in
            DEBUG) color="$CYAN" ;;
            INFO) color="$GREEN" ;;
            WARN) color="$YELLOW" ;;
            ERROR|FATAL) color="$RED" ;;
        esac

        echo -e "${color}[${level}]${NC} ${message}" >&2
    fi

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Convenience logging functions
log_debug() { log DEBUG "$@"; }
log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_fatal() { log FATAL "$@"; exit 1; }

#----------------------------------------------------
# OUTPUT FORMATTING
#----------------------------------------------------

print_header() {
    local text="$1"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $text${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    local text="$1"
    local emoji="${2:-✓}"
    echo -e "${GREEN}${emoji} $text${NC}"
}

print_error() {
    local text="$1"
    local emoji="${2:-✗}"
    echo -e "${RED}${emoji} $text${NC}" >&2
}

print_status() {
    local service="$1"
    local status="$2"
    local details="$3"

    local color="$GREEN"
    local symbol="●"

    case "$status" in
        running|healthy|active) color="$GREEN" ;;
        starting|building) color="$YELLOW" ;;
        stopped|inactive) color="$RED" ;;
        *) color="$NC" ;;
    esac

    printf "${color}${symbol}${NC} %-20s ${color}%-12s${NC} %s\n" "$service" "$status" "$details"
}

# Show spinner during long operations
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Export functions if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f get_log_level_value log log_debug log_info log_warn log_error log_fatal
    export -f print_header print_success print_error print_status spinner
fi
