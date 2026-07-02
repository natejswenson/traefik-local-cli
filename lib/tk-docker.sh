#!/bin/bash
# TK CLI Docker Operations Library
# Docker and Docker Compose wrapper functions

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/tk-logging.sh"

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

    # Resolve via `docker compose config` rather than grepping the raw file:
    # real labels look like Host(`${VAR:-default}`) || Host(`x.home.local`) —
    # unresolved interpolation plus a second OR'd clause. A raw-file grep with
    # a fixed context window misses services whose rule falls outside it, and
    # a greedy sed captures the LAST Host() clause, not the first/primary one.
    local rule
    rule=$(docker compose -f "$compose_file" config --format json 2>/dev/null | \
        python3 -c '
import json, sys
service = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
svc = data.get("services", {}).get(service, {})
labels = svc.get("labels", {})
if isinstance(labels, list):
    labels = dict(item.split("=", 1) for item in labels if "=" in item)
for key, value in labels.items():
    if key.startswith("traefik.http.routers.") and key.endswith(".rule"):
        print(value)
        break
' "$service_name" 2>/dev/null)

    if [ -z "$rule" ]; then
        echo ""
        return
    fi

    # Prefer a .internal host (the current primary domain); fall back to the
    # first Host() clause for services on a custom/legacy domain only.
    local domain
    domain=$(echo "$rule" | grep -oE 'Host\(`[^`]+`\)' | sed -E 's/Host\(`([^`]+)`\)/\1/' | grep '\.internal$' | head -1)
    if [ -z "$domain" ]; then
        domain=$(echo "$rule" | grep -oE 'Host\(`[^`]+`\)' | sed -E 's/Host\(`([^`]+)`\)/\1/' | head -1)
    fi

    echo "$domain"
}

list_all_service_hosts() {
    local compose_file="${1:-$DOCKER_COMPOSE_FILE}"

    # Derive every Host() from the resolved compose config, not a raw grep of
    # the file: a raw grep can't tell a real label from a commented-out line
    # (e.g. a "# TEMPLATE - ADD NEW SERVICE" block) and only captures the last
    # Host() clause on a line with more than one.
    docker compose -f "$compose_file" config --format json 2>/dev/null | python3 -c '
import json, re, sys

data = json.load(sys.stdin)
services = data.get("services", {})

for svc in services.values():
    labels = svc.get("labels", {})
    if isinstance(labels, list):
        labels = dict(item.split("=", 1) for item in labels if "=" in item)
    for key, value in labels.items():
        if key.startswith("traefik.http.routers.") and key.endswith(".rule"):
            for host in re.findall(r"Host\(`([^`]+)`\)", value):
                print(host)
'
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
    export -f docker_compose_cmd service_exists get_service_domain list_all_service_hosts list_services find_project_root
fi
