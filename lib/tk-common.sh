#!/bin/bash
# TK CLI Common Library
# Main entry point that sources all modular libraries

set -e

#----------------------------------------------------
# LIBRARY DIRECTORY
#----------------------------------------------------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#----------------------------------------------------
# DEFAULT CONFIGURATION
#----------------------------------------------------
export DEFAULT_DOMAIN_SUFFIX="${DEFAULT_DOMAIN_SUFFIX:-home.local}"
export AUTO_UPDATE_HOSTS="${AUTO_UPDATE_HOSTS:-true}"
export CONFIRM_DESTRUCTIVE="${CONFIRM_DESTRUCTIVE:-true}"
export DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
export DOCKER_NETWORK="${DOCKER_NETWORK:-traefik}"
export BACKUP_DIR="${BACKUP_DIR:-.backups}"
export KEEP_BACKUPS="${KEEP_BACKUPS:-5}"
export DEFAULT_SERVICE_PORT="${DEFAULT_SERVICE_PORT:-8000}"
export DEFAULT_HEALTH_CHECK_PATH="${DEFAULT_HEALTH_CHECK_PATH:-/health}"

# Security configuration
export STRICT_DOCKER_SECURITY="${STRICT_DOCKER_SECURITY:-true}"
export ALLOW_UNTRUSTED_REGISTRIES="${ALLOW_UNTRUSTED_REGISTRIES:-false}"
export SECURITY_MODE="${SECURITY_MODE:-normal}"

#----------------------------------------------------
# GLOBAL FLAGS
#----------------------------------------------------
export DRY_RUN="${DRY_RUN:-false}"
export VERBOSE="${VERBOSE:-false}"

#----------------------------------------------------
# CONFIGURATION LOADING
#----------------------------------------------------

load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    # Validate config file in subshell
    if ! ( set -e; source "$config_file" ) >/dev/null 2>&1; then
        echo "Error: Invalid config file: $config_file" >&2
        return 1
    fi

    source "$config_file"
    return 0
}

load_all_configs() {
    # Try project-level config
    if [[ -f ".tkrc" ]]; then
        load_config ".tkrc" && return 0
    fi

    # Try user-level config
    if [[ -f "$HOME/.tkrc" ]]; then
        load_config "$HOME/.tkrc" && return 0
    fi

    return 0
}

#----------------------------------------------------
# SOURCE MODULAR LIBRARIES
#----------------------------------------------------

# Load libraries in dependency order
source "$LIB_DIR/tk-logging.sh"
source "$LIB_DIR/tk-validation.sh"
source "$LIB_DIR/tk-security.sh"
source "$LIB_DIR/tk-docker.sh"

#----------------------------------------------------
# UTILITY FUNCTIONS
#----------------------------------------------------

confirm() {
    local prompt="$1"
    local default="${2:-n}"

    local yn_prompt="[y/N]"
    [[ "$default" == "y" ]] && yn_prompt="[Y/n]"

    read -p "$prompt $yn_prompt " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    elif [[ -z $REPLY ]] && [[ "$default" == "y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_destructive() {
    local action="$1"

    if [[ "$CONFIRM_DESTRUCTIVE" != "true" ]]; then
        return 0
    fi

    print_error "⚠️  DESTRUCTIVE ACTION: $action"
    confirm "Are you sure you want to continue?" "n"
}

is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

dry_run_execute() {
    if is_dry_run; then
        log_info "[DRY RUN] $*"
        return 0
    fi

    log_debug "Executing: $*"
    "$@"
}

#----------------------------------------------------
# BACKUP FUNCTIONS
#----------------------------------------------------

backup_file() {
    local file="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/${file}.backup.${timestamp}"

    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"

    # Copy file to backup location
    if cp "$file" "$backup_path"; then
        echo "$backup_path"
        return 0
    else
        return 1
    fi
}

restore_file() {
    local backup_path="$1"
    local target_file="$2"

    if [ ! -f "$backup_path" ]; then
        log_error "Backup file not found: $backup_path"
        return 1
    fi

    if cp "$backup_path" "$target_file"; then
        return 0
    else
        return 1
    fi
}

#----------------------------------------------------
# ERROR HANDLING
#----------------------------------------------------

error_trap() {
    local line_number=$1
    local command="$2"
    log_error "Command failed at line $line_number: $command"
}

exit_trap() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with code: $exit_code"
    fi
}

setup_error_handling() {
    set -eE
    trap 'error_trap ${LINENO} "$BASH_COMMAND"' ERR
    trap 'exit_trap' EXIT
}

#----------------------------------------------------
# EXPORT FUNCTIONS
#----------------------------------------------------

if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f load_config load_all_configs
    export -f confirm confirm_destructive is_dry_run dry_run_execute
    export -f backup_file restore_file
    export -f error_trap exit_trap setup_error_handling
fi
