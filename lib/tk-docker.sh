#!/bin/bash
# TK CLI Docker Operations Library
# Docker and Docker Compose wrapper functions

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/tk-logging.sh"

#----------------------------------------------------
# CONFIGURATION
#----------------------------------------------------
export DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
export DOCKER_NETWORK="${DOCKER_NETWORK:-traefik}"
export DRY_RUN="${DRY_RUN:-false}"

#----------------------------------------------------
# DOCKER COMPOSE OPERATIONS
#----------------------------------------------------

docker_compose_cmd() {
    local cmd="$*"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] docker compose $cmd"
        return 0
    fi

    log_debug "Executing: docker compose $cmd"
    docker compose $cmd
}

service_exists() {
    local service_name="$1"
    local compose_file="${2:-$DOCKER_COMPOSE_FILE}"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Compose file not found: $compose_file"
        return 1
    fi

    if grep -q "^  ${service_name}:" "$compose_file"; then
        return 0
    else
        return 1
    fi
}

get_service_domain() {
    local service_name="$1"
    local compose_file="${2:-$DOCKER_COMPOSE_FILE}"

    local domain=$(grep -A 20 "^  ${service_name}:" "$compose_file" | \
                   grep "traefik.http.routers.*.rule" | \
                   sed -n "s/.*Host(\`\(.*\)\`).*/\1/p" | head -1)

    echo "$domain"
}

list_services() {
    local compose_file="${1:-$DOCKER_COMPOSE_FILE}"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Compose file not found: $compose_file"
        return 1
    fi

    grep "^  [a-z].*:" "$compose_file" | sed 's/://g' | sed 's/^  //'
}

#----------------------------------------------------
# SERVICE MANAGEMENT
#----------------------------------------------------

find_project_root() {
    local current_dir="$PWD"

    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/docker-compose.yml" ]] && [[ -d "$current_dir/traefik" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done

    log_error "Could not find project root (looking for docker-compose.yml and traefik/)"
    return 1
}

# Export functions if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f docker_compose_cmd service_exists get_service_domain list_services find_project_root
fi
