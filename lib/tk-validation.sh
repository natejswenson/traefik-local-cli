#!/bin/bash
# TK CLI Validation Library
# Input validation and security checking functions

# Source logging for error messages
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/tk-logging.sh"

#----------------------------------------------------
# INPUT VALIDATION
#----------------------------------------------------

validate_service_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        log_error "Service name cannot be empty"
        return 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Service name must contain only alphanumeric characters, hyphens, and underscores"
        return 1
    fi

    if [[ ${#name} -gt 50 ]]; then
        log_error "Service name must be 50 characters or less"
        return 1
    fi

    return 0
}

validate_domain() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        log_error "Domain cannot be empty"
        return 1
    fi

    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi

    return 0
}

validate_port() {
    local port="$1"

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        log_error "Port must be a number: $port"
        return 1
    fi

    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        log_error "Port must be between 1 and 65535: $port"
        return 1
    fi

    if [[ $port -lt 1024 ]]; then
        log_warn "Port $port is in privileged range (< 1024)"
    fi

    return 0
}

validate_path() {
    local path="$1"
    local type="${2:-any}"

    if [[ -z "$path" ]]; then
        log_error "Path cannot be empty"
        return 1
    fi

    if [[ "$path" == *".."* ]] && [[ ! "$path" =~ ^/ ]]; then
        log_error "Relative paths with .. are not allowed for security reasons"
        return 1
    fi

    local abs_path
    if [[ -e "$path" ]]; then
        abs_path=$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path") || echo "$path"
    else
        abs_path="$path"
    fi

    if [[ ! -e "$abs_path" ]]; then
        log_error "Path does not exist: $abs_path"
        return 1
    fi

    case "$type" in
        file)
            if [[ ! -f "$abs_path" ]]; then
                log_error "Path is not a file: $abs_path"
                return 1
            fi
            ;;
        dir)
            if [[ ! -d "$abs_path" ]]; then
                log_error "Path is not a directory: $abs_path"
                return 1
            fi
            ;;
    esac

    return 0
}

#----------------------------------------------------
# DOCKER VALIDATION
#----------------------------------------------------

validate_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi

    return 0
}

validate_docker_compose() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        return 1
    fi

    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available"
        return 1
    fi

    return 0
}

validate_compose_file() {
    local compose_file="${1:-docker-compose.yml}"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Compose file not found: $compose_file"
        return 1
    fi

    log_debug "Validating compose file: $compose_file"

    if ! docker compose -f "$compose_file" config >/dev/null 2>&1; then
        log_error "Invalid docker-compose.yml syntax"
        return 1
    fi

    return 0
}

validate_docker_network() {
    local network="${1:-traefik}"

    if ! docker network inspect "$network" >/dev/null 2>&1; then
        log_warn "Docker network '$network' does not exist"
        return 1
    fi

    return 0
}

#----------------------------------------------------
# SECURITY VALIDATION
#----------------------------------------------------

sanitize_env_value() {
    local value="$1"
    value=$(echo "$value" | sed 's/[;&|`$()]//g')
    echo "$value"
}

validate_env_name() {
    local name="$1"

    if [[ ! "$name" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        log_error "Invalid environment variable name: $name"
        return 1
    fi

    return 0
}

# Export functions if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f validate_service_name validate_domain validate_port validate_path
    export -f validate_docker validate_docker_compose validate_compose_file validate_docker_network
    export -f sanitize_env_value validate_env_name
fi
