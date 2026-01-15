#!/bin/bash
# TK CLI Validation Library
# Input validation and security checking functions

# Source logging for error messages
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/tk-logging.sh"

#----------------------------------------------------
# VALIDATION CONSTANTS
#----------------------------------------------------

# Validation regex patterns
readonly VALID_SERVICE_NAME_REGEX='^[a-z][a-z0-9-]{0,62}$'
readonly VALID_PORT_REGEX='^[0-9]+$'
readonly VALID_DOMAIN_REGEX='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$'
readonly MAX_PATH_LENGTH=4096

# Reserved service names
readonly RESERVED_NAMES=("traefik" "mongodb" "postgres" "redis" "localhost" "docker" "host" "mysql" "nginx")

#----------------------------------------------------
# INPUT VALIDATION
#----------------------------------------------------

validate_service_name() {
    local name="$1"

    # Check for empty
    if [[ -z "$name" ]]; then
        log_error "Service name cannot be empty"
        return 1
    fi

    # Check length (max 63 characters per DNS spec)
    if [[ ${#name} -gt 63 ]]; then
        log_error "Service name too long (max 63 characters)"
        return 1
    fi

    # Check format (must start with letter, lowercase only, no underscores)
    if [[ ! "$name" =~ $VALID_SERVICE_NAME_REGEX ]]; then
        log_error "Invalid service name format"
        log_error "Must start with lowercase letter and contain only lowercase letters, numbers, and hyphens"
        return 1
    fi

    # Check for reserved names
    for reserved in "${RESERVED_NAMES[@]}"; do
        if [[ "$name" == "$reserved" ]]; then
            log_error "Service name '$name' is reserved and cannot be used"
            return 1
        fi
    done

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

validate_path_safe() {
    local path="$1"
    local context="${2:-path}"

    # Check for empty
    if [[ -z "$path" ]]; then
        log_error "$context cannot be empty"
        return 1
    fi

    # Check length
    if [[ ${#path} -gt $MAX_PATH_LENGTH ]]; then
        log_error "$context exceeds maximum length ($MAX_PATH_LENGTH characters)"
        return 1
    fi

    # Get canonical path
    local canonical_path
    if command -v realpath >/dev/null 2>&1; then
        # Use realpath if available
        if [[ -e "$path" ]]; then
            canonical_path=$(realpath "$path" 2>/dev/null) || {
                log_error "Failed to resolve $context: $path"
                return 1
            }
        else
            # Path doesn't exist yet, check parent
            local parent=$(dirname "$path")
            if [[ -d "$parent" ]]; then
                canonical_path=$(realpath "$parent" 2>/dev/null)/$(basename "$path")
            else
                log_error "$context parent directory does not exist: $parent"
                return 1
            fi
        fi
    else
        # Fallback for systems without realpath
        if [[ -e "$path" ]]; then
            canonical_path=$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path") || {
                log_error "Failed to resolve $context: $path"
                return 1
            }
        else
            canonical_path="$path"
        fi
    fi

    # Block path traversal attempts in canonical path
    if [[ "$canonical_path" =~ \.\. ]]; then
        log_error "Path traversal detected in $context"
        return 1
    fi

    # Ensure path is within allowed directories
    local allowed_dirs=(
        "$HOME"
        "/tmp"
        "/var/tmp"
    )

    # Add project root if we can find it
    if command -v find_project_root >/dev/null 2>&1; then
        local project_root=$(find_project_root 2>/dev/null)
        if [[ -n "$project_root" ]]; then
            allowed_dirs+=("$project_root")
        fi
    fi

    local path_allowed=false
    for allowed_dir in "${allowed_dirs[@]}"; do
        if [[ "$canonical_path" == "$allowed_dir"* ]]; then
            path_allowed=true
            break
        fi
    done

    if [[ "$path_allowed" == "false" ]]; then
        log_error "$context is outside allowed directories"
        log_debug "Path: $canonical_path"
        log_debug "Allowed: ${allowed_dirs[*]}"
        return 1
    fi

    # Block sensitive system paths
    local blocked_paths=("/etc" "/usr" "/bin" "/sbin" "/boot" "/sys" "/proc" "/root")
    for blocked in "${blocked_paths[@]}"; do
        if [[ "$canonical_path" == "$blocked"* ]]; then
            log_error "$context points to protected system directory: $blocked"
            return 1
        fi
    done

    log_debug "Path validation passed: $canonical_path"
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
    # Remove potentially dangerous characters
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

validate_env_value_safe() {
    local name="$1"
    local value="$2"

    # Validate environment variable name
    if [[ ! "$name" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        log_error "Invalid environment variable name: $name"
        return 1
    fi

    # Check for injection attempts in value
    if [[ "$value" =~ (\$\{|\$\(|;|\||&|>|<|\`) ]]; then
        log_error "Potential injection detected in environment variable value"
        log_error "Variable: $name"
        return 1
    fi

    # Limit value length
    if [[ ${#value} -gt 4096 ]]; then
        log_error "Environment variable value too long (max 4096 characters)"
        log_error "Variable: $name"
        return 1
    fi

    return 0
}

# Export functions if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f validate_service_name validate_domain validate_port validate_path validate_path_safe
    export -f validate_docker validate_docker_compose validate_compose_file validate_docker_network
    export -f sanitize_env_value validate_env_name validate_env_value_safe
fi
