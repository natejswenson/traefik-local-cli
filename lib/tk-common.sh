#!/bin/bash
# TK CLI Common Library
# Shared functions for all tk commands to follow DRY principles

set -e

#----------------------------------------------------
# CONFIGURATION
#----------------------------------------------------

# Default configuration values
export DEFAULT_DOMAIN_SUFFIX="${DEFAULT_DOMAIN_SUFFIX:-home.local}"
export AUTO_UPDATE_HOSTS="${AUTO_UPDATE_HOSTS:-true}"
export CONFIRM_DESTRUCTIVE="${CONFIRM_DESTRUCTIVE:-true}"
export DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
export DOCKER_NETWORK="${DOCKER_NETWORK:-traefik}"
export BACKUP_DIR="${BACKUP_DIR:-.backups}"
export KEEP_BACKUPS="${KEEP_BACKUPS:-5}"
export DEFAULT_SERVICE_PORT="${DEFAULT_SERVICE_PORT:-8000}"
export DEFAULT_HEALTH_CHECK_PATH="${DEFAULT_HEALTH_CHECK_PATH:-/health}"

#----------------------------------------------------
# GLOBAL FLAGS
#----------------------------------------------------
export DRY_RUN="${DRY_RUN:-false}"
export VERBOSE="${VERBOSE:-false}"

#----------------------------------------------------
# CONFIGURATION LOADING
#----------------------------------------------------

# Load configuration from file
load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_debug "Config file not found: $config_file"
        return 1
    fi

    log_debug "Loading config from: $config_file"

    # Source config file in a subshell to validate it first
    if ! ( set -e; source "$config_file" ) >/dev/null 2>&1; then
        log_error "Invalid config file: $config_file"
        return 1
    fi

    # Now load it for real
    source "$config_file"

    log_info "Configuration loaded from: $config_file"
    return 0
}

# Load configuration from standard locations
load_all_configs() {
    local loaded=false

    # 1. Try project-level config
    if [[ -f ".tkrc" ]]; then
        if load_config ".tkrc"; then
            loaded=true
        fi
    fi

    # 2. Try user-level config (if project config not found)
    if [[ "$loaded" == "false" ]] && [[ -f "$HOME/.tkrc" ]]; then
        if load_config "$HOME/.tkrc"; then
            loaded=true
        fi
    fi

    if [[ "$loaded" == "false" ]]; then
        log_debug "No configuration file found (using defaults)"
    fi

    return 0
}

#----------------------------------------------------
# COLOR DEFINITIONS (Single source of truth)
#----------------------------------------------------
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

#----------------------------------------------------
# LOGGING FUNCTIONS
#----------------------------------------------------

# Log levels (using numeric comparison)
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export LOG_FILE="${LOG_FILE:-/tmp/tk.log}"

# Get numeric log level
get_log_level_value() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        FATAL) echo 4 ;;
        *)     echo 1 ;;
    esac
}

# Log with timestamp and level
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to file
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"

    # Only output to console if level is appropriate
    local current_level=$(get_log_level_value "$level")
    local min_level=$(get_log_level_value "$LOG_LEVEL")

    if [ "$current_level" -ge "$min_level" ]; then
        case "$level" in
            ERROR|FATAL)
                echo -e "${RED}[${level}] ${message}${NC}" >&2
                ;;
            WARN)
                echo -e "${YELLOW}[${level}] ${message}${NC}" >&2
                ;;
            INFO)
                echo -e "${GREEN}[${level}] ${message}${NC}"
                ;;
            DEBUG)
                echo -e "${BLUE}[${level}] ${message}${NC}"
                ;;
        esac
    fi
}

# Convenience functions
log_debug() { log DEBUG "$@"; }
log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_fatal() { log FATAL "$@"; exit 1; }

#----------------------------------------------------
# UI DISPLAY FUNCTIONS
#----------------------------------------------------

# Print header box
print_header() {
    local message="$1"
    local width=60
    echo -e "${CYAN}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
    printf "${CYAN}║%-${width}s║${NC}\n" "  $message"
    echo -e "${CYAN}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
    echo ""
}

# Print success box
print_success() {
    local message="$1"
    local width=60
    echo ""
    echo -e "${GREEN}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
    printf "${GREEN}║%-${width}s║${NC}\n" "                     SUCCESS!                               "
    echo -e "${GREEN}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
    echo ""
    echo -e "${CYAN}${message}${NC}"
    echo ""
}

# Print error box
print_error() {
    local message="$1"
    local width=60
    echo ""
    echo -e "${RED}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
    printf "${RED}║%-${width}s║${NC}\n" "                     ERROR!                                 "
    echo -e "${RED}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
    echo ""
    echo -e "${RED}${message}${NC}"
    echo ""
}

# Print status with icon
print_status() {
    local status="$1"
    local message="$2"

    case "$status" in
        success|ok)
            echo -e "${GREEN}  ✓ ${message}${NC}"
            ;;
        error|fail)
            echo -e "${RED}  ✗ ${message}${NC}"
            ;;
        warn|warning)
            echo -e "${YELLOW}  ⚠ ${message}${NC}"
            ;;
        info)
            echo -e "${BLUE}  ℹ ${message}${NC}"
            ;;
        *)
            echo -e "  ${message}"
            ;;
    esac
}

# Progress spinner
spinner() {
    local pid=$1
    local message="${2:-Processing}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r${BLUE}${spin:$i:1} ${message}...${NC}"
        sleep 0.1
    done
    printf "\r"
}

#----------------------------------------------------
# VALIDATION FUNCTIONS
#----------------------------------------------------

# Validate service name (alphanumeric, hyphens, underscores only)
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

# Validate domain name
validate_domain() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        log_error "Domain cannot be empty"
        return 1
    fi

    # Basic domain validation (allows .localhost and .home.local)
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi

    return 0
}

# Validate path exists and is accessible
validate_path() {
    local path="$1"
    local type="${2:-any}" # any, file, dir

    if [[ -z "$path" ]]; then
        log_error "Path cannot be empty"
        return 1
    fi

    # Prevent path traversal attacks
    if [[ "$path" == *".."* ]] && [[ ! "$path" =~ ^/ ]]; then
        log_error "Relative paths with .. are not allowed for security reasons"
        return 1
    fi

    # Resolve to absolute path for validation
    local abs_path
    if [[ -e "$path" ]]; then
        abs_path=$(cd "$path" 2>/dev/null && pwd || echo "$path")
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

# Validate port number
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

    # Check if port is in privileged range
    if [[ $port -lt 1024 ]]; then
        log_warn "Port $port is in privileged range (< 1024)"
    fi

    return 0
}

# Validate Docker is running
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

# Validate Docker Compose is available
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

# Validate project structure
validate_project_structure() {
    local project_root="$1"

    if [[ ! -d "$project_root" ]]; then
        log_error "Project root does not exist: $project_root"
        return 1
    fi

    if [[ ! -f "$project_root/$DOCKER_COMPOSE_FILE" ]]; then
        log_error "docker-compose.yml not found in: $project_root"
        return 1
    fi

    if [[ ! -d "$project_root/traefik" ]]; then
        log_error "traefik directory not found in: $project_root"
        return 1
    fi

    return 0
}

# Validate docker-compose.yml syntax
validate_compose_file() {
    local compose_file="${1:-$DOCKER_COMPOSE_FILE}"

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

# Validate Docker network exists
validate_docker_network() {
    local network="${1:-$DOCKER_NETWORK}"

    if ! docker network inspect "$network" >/dev/null 2>&1; then
        log_warn "Docker network '$network' does not exist"
        return 1
    fi

    return 0
}

#----------------------------------------------------
# DOCKER SECURITY VALIDATIONS
#----------------------------------------------------

# Check Dockerfile for security best practices
validate_dockerfile_security() {
    local dockerfile="$1"

    if [[ ! -f "$dockerfile" ]]; then
        log_error "Dockerfile not found: $dockerfile"
        return 1
    fi

    local warnings=0

    # Check for running as root
    if ! grep -q "^USER " "$dockerfile"; then
        log_warn "Dockerfile does not specify USER (running as root)"
        warnings=$((warnings + 1))
    fi

    # Check for HEALTHCHECK
    if ! grep -q "^HEALTHCHECK " "$dockerfile"; then
        log_warn "Dockerfile missing HEALTHCHECK instruction"
        warnings=$((warnings + 1))
    fi

    # Check for pinned base image versions
    if grep -q "FROM.*:latest" "$dockerfile"; then
        log_warn "Dockerfile uses :latest tag (pin to specific version)"
        warnings=$((warnings + 1))
    fi

    # Check for secrets in Dockerfile
    if grep -iE "(password|secret|key|token).*=" "$dockerfile"; then
        log_error "Potential secrets found in Dockerfile"
        warnings=$((warnings + 1))
    fi

    if [[ $warnings -eq 0 ]]; then
        log_info "Dockerfile security check passed"
        return 0
    else
        log_warn "Dockerfile has $warnings security warning(s)"
        return 1
    fi
}

# Check service configuration for security best practices
validate_service_security() {
    local service_name="$1"
    local compose_file="${2:-$DOCKER_COMPOSE_FILE}"

    if ! service_exists "$service_name" "$compose_file"; then
        log_error "Service not found: $service_name"
        return 1
    fi

    local warnings=0
    local service_config=$(sed -n "/^  ${service_name}:/,/^  [a-z]/p" "$compose_file")

    # Check for privileged mode
    if echo "$service_config" | grep -q "privileged.*true"; then
        log_error "Service runs in privileged mode (security risk)"
        warnings=$((warnings + 1))
    fi

    # Check for host network mode
    if echo "$service_config" | grep -q "network_mode.*host"; then
        log_warn "Service uses host network mode"
        warnings=$((warnings + 1))
    fi

    # Check for volume mounts to sensitive paths
    if echo "$service_config" | grep -qE "volumes:.*(/etc|/var/run/docker.sock)"; then
        log_warn "Service mounts sensitive host paths"
        warnings=$((warnings + 1))
    fi

    # Check for exposed ports
    if echo "$service_config" | grep -q "^    ports:"; then
        log_info "Service exposes ports (ensure this is intentional)"
    fi

    if [[ $warnings -eq 0 ]]; then
        log_info "Service security check passed"
        return 0
    else
        log_warn "Service has $warnings security warning(s)"
        return 1
    fi
}

# Sanitize environment variable value
sanitize_env_value() {
    local value="$1"

    # Remove potentially dangerous characters
    value=$(echo "$value" | sed 's/[;&|`$()]//g')

    echo "$value"
}

# Validate environment variable name
validate_env_name() {
    local name="$1"

    if [[ ! "$name" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        log_error "Invalid environment variable name: $name"
        return 1
    fi

    return 0
}

#----------------------------------------------------
# MONITORING AND HEALTH CHECKS
#----------------------------------------------------

# Check if service is healthy
check_service_health() {
    local service_name="$1"
    local timeout="${2:-30}"

    log_debug "Checking health of service: $service_name"

    # Check if service is running
    if ! docker compose ps "$service_name" 2>/dev/null | grep -q "Up"; then
        log_error "Service is not running: $service_name"
        return 1
    fi

    # Wait for healthy status
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(docker compose ps "$service_name" 2>/dev/null | grep "$service_name" | awk '{print $NF}')

        if [[ "$status" == *"healthy"* ]]; then
            log_info "Service is healthy: $service_name"
            return 0
        elif [[ "$status" == *"unhealthy"* ]]; then
            log_error "Service is unhealthy: $service_name"
            return 1
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    log_warn "Health check timed out for service: $service_name"
    return 1
}

# Test service endpoint
test_service_endpoint() {
    local url="$1"
    local expected_code="${2:-200}"

    log_debug "Testing endpoint: $url"

    local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)

    if [[ "$http_code" == "$expected_code" ]]; then
        log_info "Endpoint is accessible: $url (HTTP $http_code)"
        return 0
    else
        log_error "Endpoint returned unexpected code: $url (HTTP $http_code, expected $expected_code)"
        return 1
    fi
}

# Check Traefik routing for service
check_traefik_routing() {
    local service_name="$1"

    local domain=$(get_service_domain "$service_name")

    if [[ -z "$domain" ]]; then
        log_error "Could not extract domain for service: $service_name"
        return 1
    fi

    log_debug "Checking Traefik routing for: $domain"

    # Check if domain resolves
    if ! nslookup "$domain" >/dev/null 2>&1 && ! grep -q "127.0.0.1.*$domain" /etc/hosts 2>/dev/null; then
        log_error "Domain does not resolve: $domain"
        return 1
    fi

    # Test HTTPS endpoint
    if test_service_endpoint "https://${domain}/health" "200"; then
        log_info "Traefik routing is working for: $domain"
        return 0
    elif test_service_endpoint "https://${domain}/" "200"; then
        log_info "Service is accessible but /health endpoint missing: $domain"
        return 0
    else
        log_error "Traefik routing failed for: $domain"
        return 1
    fi
}

# Get service metrics
get_service_metrics() {
    local service_name="$1"

    echo -e "${CYAN}Service Metrics: $service_name${NC}"
    echo ""

    # Container stats
    local container_id=$(docker compose ps -q "$service_name" 2>/dev/null)

    if [[ -z "$container_id" ]]; then
        log_error "Service not found: $service_name"
        return 1
    fi

    # Get stats (one-time snapshot)
    docker stats --no-stream "$container_id" --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

    echo ""

    # Check logs for errors
    local error_count=$(docker compose logs --tail=100 "$service_name" 2>/dev/null | grep -ciE "(error|fatal|exception)" || echo "0")

    if [[ $error_count -gt 0 ]]; then
        log_warn "Found $error_count error(s) in recent logs"
    else
        log_info "No errors in recent logs"
    fi

    return 0
}

# Monitor all services
monitor_all_services() {
    print_header "Service Health Monitor"

    local services=$(list_services)
    local healthy=0
    local unhealthy=0
    local total=0

    for service in $services; do
        # Skip infrastructure services
        if [[ "$service" == "traefik" ]] || [[ "$service" == "mongodb" ]] || [[ "$service" == "postgres" ]] || [[ "$service" == "redis" ]]; then
            continue
        fi

        total=$((total + 1))

        echo -n "  • $service: "

        if check_service_health "$service" 5 >/dev/null 2>&1; then
            print_status "success" "Healthy"
            healthy=$((healthy + 1))
        else
            print_status "error" "Unhealthy"
            unhealthy=$((unhealthy + 1))
        fi
    done

    echo ""
    echo -e "${CYAN}Summary:${NC}"
    echo -e "  Total: $total"
    echo -e "  ${GREEN}Healthy: $healthy${NC}"
    echo -e "  ${RED}Unhealthy: $unhealthy${NC}"
    echo ""

    return 0
}

#----------------------------------------------------
# DRY-RUN HELPERS
#----------------------------------------------------

# Execute command or show what would be executed in dry-run mode
dry_run_execute() {
    local description="$1"
    shift

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would execute: $description${NC}"
        echo -e "${BLUE}  Command: $*${NC}"
        return 0
    else
        log_debug "Executing: $*"
        "$@"
        return $?
    fi
}

# Check if in dry-run mode
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

#----------------------------------------------------
# DOCKER HELPER FUNCTIONS
#----------------------------------------------------

# Execute docker compose command with error handling
docker_compose_cmd() {
    local cmd="$1"
    shift

    if is_dry_run; then
        echo -e "${YELLOW}[DRY-RUN] Would execute: docker compose $cmd $*${NC}"
        return 0
    fi

    log_debug "Executing: docker compose $cmd $*"

    if ! docker compose "$cmd" "$@" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Docker compose $cmd failed"
        return 1
    fi

    return 0
}

# Check if service exists in docker-compose.yml
service_exists() {
    local service_name="$1"
    local compose_file="${2:-docker-compose.yml}"

    if ! validate_path "$compose_file" "file"; then
        return 1
    fi

    if grep -q "^  ${service_name}:" "$compose_file"; then
        return 0
    fi

    return 1
}

# Extract service domain from docker-compose.yml
get_service_domain() {
    local service_name="$1"
    local compose_file="${2:-docker-compose.yml}"

    grep -A 20 "^  ${service_name}:" "$compose_file" | \
        grep "traefik.http.routers.${service_name}.rule" | \
        sed -n "s/.*Host(\`\([^']*\)\`).*/\1/p" | \
        head -n 1
}

# List all services from docker-compose.yml
list_services() {
    local compose_file="${1:-docker-compose.yml}"

    sed -n '/^services:/,/^[a-z]/p' "$compose_file" | \
        grep "^  [a-z][a-z0-9_-]*:" | \
        sed 's/://g' | \
        sed 's/^  //'
}

#----------------------------------------------------
# BACKUP/RESTORE FUNCTIONS
#----------------------------------------------------

# Global backup stack for automatic rollback (using indexed array instead of associative)
BACKUP_STACK=()

# Create backup of a file with timestamp
backup_file() {
    local file="$1"
    local backup_dir="${2:-.}"
    local auto_rollback="${3:-false}"

    if [[ ! -f "$file" ]]; then
        log_error "Cannot backup non-existent file: $file"
        return 1
    fi

    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local basename=$(basename "$file")
    local backup_path="${backup_dir}/${basename}.backup.${timestamp}"

    if cp "$file" "$backup_path"; then
        log_info "Backup created: $backup_path"

        # Add to backup stack for potential rollback
        if [[ "$auto_rollback" == "true" ]]; then
            BACKUP_STACK+=("${file}|${backup_path}")
            log_debug "Added to backup stack: $file -> $backup_path"
        fi

        echo "$backup_path"
        return 0
    else
        log_error "Failed to create backup: $backup_path"
        return 1
    fi
}

# Restore from backup
restore_file() {
    local backup_path="$1"
    local target_path="$2"

    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file not found: $backup_path"
        return 1
    fi

    if cp "$backup_path" "$target_path"; then
        log_info "Restored from backup: $target_path"
        return 0
    else
        log_error "Failed to restore from backup"
        return 1
    fi
}

# Rollback all backups in stack
rollback_all() {
    log_warn "Rolling back all changes..."

    local rollback_count=0
    local rollback_failed=0

    # Get array length
    local stack_size=${#BACKUP_STACK[@]}

    # Rollback in reverse order
    for ((i=stack_size-1; i>=0; i--)); do
        local entry="${BACKUP_STACK[$i]}"
        if [[ -n "$entry" ]]; then
            local original_file="${entry%|*}"
            local backup_file="${entry#*|}"

            log_info "Rolling back: $original_file"

            if restore_file "$backup_file" "$original_file"; then
                rollback_count=$((rollback_count + 1))
            else
                log_error "Failed to rollback: $original_file"
                rollback_failed=$((rollback_failed + 1))
            fi
        fi
    done

    if [[ $rollback_failed -eq 0 ]]; then
        log_info "Rollback complete: $rollback_count file(s) restored"
        return 0
    else
        log_error "Rollback incomplete: $rollback_failed file(s) failed"
        return 1
    fi
}

# Clear backup stack
clear_backup_stack() {
    log_debug "Clearing backup stack"
    BACKUP_STACK=()
}

#----------------------------------------------------
# SECURE SUDO OPERATIONS
#----------------------------------------------------

# Validate hosts file entry format
validate_hosts_entry() {
    local entry="$1"

    # Must match pattern: IP_ADDRESS HOSTNAME
    if [[ ! "$entry" =~ ^127\.0\.0\.1[[:space:]][a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]; then
        log_error "Invalid hosts entry format: $entry"
        return 1
    fi

    # Extract domain and validate
    local domain=$(echo "$entry" | awk '{print $2}')
    if ! validate_domain "$domain"; then
        return 1
    fi

    return 0
}

# Safely add entry to /etc/hosts with validation
safe_add_to_hosts() {
    local domain="$1"

    # Validate domain first
    if ! validate_domain "$domain"; then
        log_error "Cannot add invalid domain to /etc/hosts: $domain"
        return 1
    fi

    local entry="127.0.0.1 ${domain}"

    # Validate complete entry
    if ! validate_hosts_entry "$entry"; then
        log_error "Refusing to add invalid entry to /etc/hosts"
        return 1
    fi

    # Check if already exists
    if grep -q "^127\.0\.0\.1[[:space:]]${domain}$" /etc/hosts 2>/dev/null; then
        log_info "Entry already exists in /etc/hosts: $domain"
        return 0
    fi

    # Request sudo access
    log_info "Adding $domain to /etc/hosts (requires sudo)"

    # Use tee with a here-string to avoid shell injection
    if echo "$entry" | sudo tee -a /etc/hosts >/dev/null; then
        log_info "Added to /etc/hosts: $entry"
        return 0
    else
        log_error "Failed to add entry to /etc/hosts"
        return 1
    fi
}

# Safely remove entry from /etc/hosts with validation
safe_remove_from_hosts() {
    local domain="$1"

    # Validate domain first
    if ! validate_domain "$domain"; then
        log_error "Cannot remove invalid domain from /etc/hosts: $domain"
        return 1
    fi

    # Check if exists
    if ! grep -q "^127\.0\.0\.1[[:space:]]${domain}$" /etc/hosts 2>/dev/null; then
        log_info "Entry not found in /etc/hosts: $domain"
        return 0
    fi

    # Create backup of /etc/hosts
    log_info "Removing $domain from /etc/hosts (requires sudo)"

    # Use sed with proper escaping
    local escaped_domain=$(echo "$domain" | sed 's/\./\\./g')

    # Create backup before modifying
    if ! sudo cp /etc/hosts /etc/hosts.backup; then
        log_error "Failed to backup /etc/hosts"
        return 1
    fi

    # Remove the entry
    if sudo sed -i.bak "/^127\.0\.0\.1[[:space:]]${escaped_domain}$/d" /etc/hosts; then
        log_info "Removed from /etc/hosts: $domain"
        return 0
    else
        log_error "Failed to remove entry from /etc/hosts"
        # Restore from backup
        sudo mv /etc/hosts.backup /etc/hosts
        return 1
    fi
}

# Validate and execute sudo command (only for whitelisted operations)
safe_sudo() {
    local operation="$1"
    shift

    case "$operation" in
        add-hosts)
            safe_add_to_hosts "$@"
            ;;
        remove-hosts)
            safe_remove_from_hosts "$@"
            ;;
        *)
            log_error "Unsupported sudo operation: $operation"
            return 1
            ;;
    esac
}

#----------------------------------------------------
# CONFIRMATION FUNCTIONS
#----------------------------------------------------

# Ask for user confirmation
confirm() {
    local message="$1"
    local default="${2:-n}" # y or n

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -e "${YELLOW}${message} ${prompt}${NC}"
    read -r response

    # Use default if no response
    if [[ -z "$response" ]]; then
        response="$default"
    fi

    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Confirm destructive operation
confirm_destructive() {
    local operation="$1"

    echo -e "${RED}⚠️  WARNING: This is a destructive operation!${NC}"
    echo -e "${YELLOW}Operation: ${operation}${NC}"
    echo ""

    if ! confirm "Are you sure you want to continue?" "n"; then
        log_info "Operation cancelled by user"
        return 1
    fi

    return 0
}

#----------------------------------------------------
# PROJECT ROOT DETECTION
#----------------------------------------------------

# Find the Traefik project root directory
find_project_root() {
    local current_dir="$(pwd)"
    local max_depth=5
    local depth=0

    while [[ $depth -lt $max_depth ]]; do
        if [[ -f "docker-compose.yml" ]] && [[ -d "traefik" ]]; then
            log_debug "Found project root: $(pwd)"
            echo "$(pwd)"
            return 0
        fi

        if [[ "$(pwd)" == "/" ]]; then
            break
        fi

        cd ..
        depth=$((depth + 1))
    done

    cd "$current_dir"
    log_error "Could not find Traefik project root (docker-compose.yml + traefik/ directory)"
    return 1
}

#----------------------------------------------------
# ERROR HANDLING
#----------------------------------------------------

# Global cleanup function
CLEANUP_FUNCTIONS=()

# Register cleanup function
register_cleanup() {
    CLEANUP_FUNCTIONS+=("$1")
}

# Execute all registered cleanup functions
run_cleanup() {
    for cleanup_fn in "${CLEANUP_FUNCTIONS[@]}"; do
        log_debug "Running cleanup: $cleanup_fn"
        $cleanup_fn || true
    done
}

# Error trap handler
error_trap() {
    local exit_code=$?
    local line_number=$1

    log_error "Command failed with exit code $exit_code at line $line_number"
    log_error "Command: ${BASH_COMMAND}"

    # Run cleanup functions
    run_cleanup

    # Print stack trace if DEBUG enabled
    if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
        log_debug "Stack trace:"
        local frame=0
        while caller $frame; do
            ((frame++))
        done
    fi

    exit $exit_code
}

# Exit trap handler
exit_trap() {
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_debug "Script completed successfully"
    else
        log_error "Script exited with code: $exit_code"
    fi

    # Run cleanup functions
    run_cleanup
}

# Setup error handling
setup_error_handling() {
    # Enable error trapping
    set -eE

    # Trap errors and exits
    trap 'error_trap ${LINENO}' ERR
    trap 'exit_trap' EXIT

    # Trap interrupts
    trap 'log_warn "Script interrupted by user"; exit 130' INT TERM

    log_debug "Error handling initialized"
}

#----------------------------------------------------
# EXPORT FUNCTIONS
#----------------------------------------------------

# Export all functions if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f load_config load_all_configs
    export -f get_log_level_value log log_debug log_info log_warn log_error log_fatal
    export -f print_header print_success print_error print_status spinner
    export -f validate_service_name validate_domain validate_path validate_port
    export -f validate_docker validate_docker_compose validate_project_structure
    export -f validate_compose_file validate_docker_network
    export -f validate_dockerfile_security validate_service_security
    export -f sanitize_env_value validate_env_name
    export -f dry_run_execute is_dry_run
    export -f docker_compose_cmd service_exists get_service_domain list_services
    export -f backup_file restore_file rollback_all clear_backup_stack
    export -f confirm confirm_destructive
    export -f find_project_root
    export -f register_cleanup run_cleanup error_trap exit_trap setup_error_handling
    export -f validate_hosts_entry safe_add_to_hosts safe_remove_from_hosts safe_sudo
    export -f check_service_health test_service_endpoint check_traefik_routing
    export -f get_service_metrics monitor_all_services
fi
