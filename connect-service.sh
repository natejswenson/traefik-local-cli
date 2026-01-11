#!/bin/bash
# Auto-Connect Service to Traefik
# Automatically detects service type and configures it for Traefik

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source library functions
source "${SCRIPT_DIR}/lib/tk-common.sh"
source "${SCRIPT_DIR}/lib/service-detector.sh"
source "${SCRIPT_DIR}/lib/docker-generator.sh"

# Initialize logging
log_debug "Connect-service script started"

# Usage information
usage() {
    cat <<EOF
${CYAN}╔════════════════════════════════════════════════════════════╗
║           Traefik Service Auto-Connect                     ║
╚════════════════════════════════════════════════════════════╝${NC}

${YELLOW}Usage:${NC}
  $0 <path-to-service> [service-name] [options]

${YELLOW}Arguments:${NC}
  path-to-service    Path to the service directory (required)
  service-name       Name for the service (optional, auto-detected from path)

${YELLOW}Options:${NC}
  --port PORT        Override detected port
  --domain DOMAIN    Custom domain (default: service-name.home.local)
  --no-docker        Skip Dockerfile generation (use existing)
  --dry-run          Show what would be done without making changes
  --help             Show this help message

${YELLOW}Examples:${NC}
  ${GREEN}# Auto-detect and connect a service${NC}
  $0 /path/to/my-api

  ${GREEN}# Connect with custom name${NC}
  $0 /path/to/my-service custom-api

  ${GREEN}# Override port${NC}
  $0 /path/to/my-api --port 9000

  ${GREEN}# Dry run to see what would happen${NC}
  $0 /path/to/my-api --dry-run

${YELLOW}What it does:${NC}
  1. Analyzes your service to detect language & framework
  2. Detects port, entry point, and dependencies
  3. Generates Dockerfile (if needed)
  4. Adds service to docker-compose.yml
  5. Starts the service with Traefik routing

EOF
    exit 0
}

# Parse arguments
SERVICE_PATH=""
SERVICE_NAME=""
OVERRIDE_PORT=""
CUSTOM_DOMAIN=""
NO_DOCKER=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            usage
            ;;
        --port)
            OVERRIDE_PORT="$2"
            shift 2
            ;;
        --domain)
            CUSTOM_DOMAIN="$2"
            shift 2
            ;;
        --no-docker)
            NO_DOCKER=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            if [ -z "$SERVICE_PATH" ]; then
                SERVICE_PATH="$1"
            elif [ -z "$SERVICE_NAME" ]; then
                SERVICE_NAME="$1"
            else
                echo -e "${RED}Error: Unknown argument: $1${NC}"
                usage
            fi
            shift
            ;;
    esac
done

# Validate service path
if [ -z "$SERVICE_PATH" ]; then
    echo -e "${RED}Error: Service path is required${NC}"
    usage
fi

# Check if path exists before trying to convert
if [ ! -d "$SERVICE_PATH" ]; then
    echo -e "${RED}Error: Service path does not exist: $SERVICE_PATH${NC}"
    echo -e "${YELLOW}Current directory: $(pwd)${NC}"
    echo -e "${YELLOW}Tried to access: $SERVICE_PATH${NC}"
    echo ""
    echo -e "${CYAN}Hint: Use an absolute path or ensure you're in the correct directory${NC}"
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  tk add ~/localrepo/helloworld"
    echo -e "  tk add /Users/natejswenson/localrepo/helloworld"
    exit 1
fi

# Convert to absolute path
SERVICE_PATH=$(cd "$SERVICE_PATH" && pwd)

# Auto-detect service name from path if not provided
if [ -z "$SERVICE_NAME" ]; then
    SERVICE_NAME=$(basename "$SERVICE_PATH")
    log_info "Auto-detected service name: ${SERVICE_NAME}"
fi

# Sanitize service name (replace invalid characters)
SERVICE_NAME=$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

# Validate service name
if ! validate_service_name "$SERVICE_NAME"; then
    log_fatal "Invalid service name: $SERVICE_NAME"
fi

echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║  Auto-Connecting Service to Traefik                       ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Service Name:${NC} ${SERVICE_NAME}"
echo -e "${CYAN}Service Path:${NC} ${SERVICE_PATH}"
echo ""

# Generate metadata
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
METADATA=$(generate_service_metadata "$SERVICE_PATH" "$SERVICE_NAME")

# Parse metadata (using sed for cross-platform compatibility)
LANGUAGE=$(echo "$METADATA" | sed -n 's/.*"language":[[:space:]]*"\([^"]*\)".*/\1/p')
FRAMEWORK=$(echo "$METADATA" | sed -n 's/.*"framework":[[:space:]]*"\([^"]*\)".*/\1/p')
PORT=$(echo "$METADATA" | sed -n 's/.*"port":[[:space:]]*\([0-9]*\).*/\1/p')
ENTRYPOINT=$(echo "$METADATA" | sed -n 's/.*"entrypoint":[[:space:]]*"\([^"]*\)".*/\1/p')
HAS_DOCKERFILE=$(echo "$METADATA" | sed -n 's/.*"has_dockerfile":[[:space:]]*\([^,}]*\).*/\1/p')
NEEDS_MONGODB=$(echo "$METADATA" | sed -n 's/.*"mongodb":[[:space:]]*\([^,}]*\).*/\1/p')
NEEDS_POSTGRES=$(echo "$METADATA" | sed -n 's/.*"postgres":[[:space:]]*\([^,}]*\).*/\1/p')
NEEDS_REDIS=$(echo "$METADATA" | sed -n 's/.*"redis":[[:space:]]*\([^,}]*\).*/\1/p')

# Override port if specified
if [ -n "$OVERRIDE_PORT" ]; then
    if ! validate_port "$OVERRIDE_PORT"; then
        log_fatal "Invalid port: $OVERRIDE_PORT"
    fi
    PORT="$OVERRIDE_PORT"
    log_info "Port overridden: ${PORT}"
fi

# Set domain
DOMAIN="${CUSTOM_DOMAIN:-${SERVICE_NAME}.home.local}"

# Validate domain
if ! validate_domain "$DOMAIN"; then
    log_fatal "Invalid domain: $DOMAIN"
fi

echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
echo ""

# Summary
echo -e "${CYAN}📋 Configuration Summary:${NC}"
echo -e "  Service: ${GREEN}${SERVICE_NAME}${NC}"
echo -e "  Language: ${GREEN}${LANGUAGE}${NC}"
echo -e "  Framework: ${GREEN}${FRAMEWORK}${NC}"
echo -e "  Port: ${GREEN}${PORT}${NC}"
echo -e "  Domain: ${GREEN}https://${DOMAIN}${NC}"
echo -e "  Entry Point: ${GREEN}${ENTRYPOINT}${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
    echo ""
fi

# Step 1: Generate Dockerfile if needed
if [ "$HAS_DOCKERFILE" = "false" ] && [ "$NO_DOCKER" = false ]; then
    echo -e "${BLUE}🐳 Generating Dockerfile...${NC}"

    if [ "$DRY_RUN" = false ]; then
        DOCKERFILE_CONTENT=$(generate_dockerfile "$LANGUAGE" "$FRAMEWORK" "$PORT" "$ENTRYPOINT")
        echo "$DOCKERFILE_CONTENT" > "${SERVICE_PATH}/Dockerfile"
        echo -e "${GREEN}  ✓ Dockerfile created${NC}"

        # Generate .dockerignore
        if [ "$LANGUAGE" = "python" ]; then
            generate_dockerignore_python > "${SERVICE_PATH}/.dockerignore"
        elif [ "$LANGUAGE" = "node" ]; then
            generate_dockerignore_node > "${SERVICE_PATH}/.dockerignore"
        fi
        echo -e "${GREEN}  ✓ .dockerignore created${NC}"
    else
        echo -e "${YELLOW}  Would create: ${SERVICE_PATH}/Dockerfile${NC}"
        echo -e "${YELLOW}  Would create: ${SERVICE_PATH}/.dockerignore${NC}"
    fi
elif [ "$HAS_DOCKERFILE" = "true" ]; then
    echo -e "${GREEN}✓ Using existing Dockerfile${NC}"
fi

echo ""

# Step 2: Generate docker-compose service definition
echo -e "${BLUE}📦 Generating docker-compose configuration...${NC}"

# Calculate relative path from project root (macOS compatible)
SERVICE_REL_PATH=$(python3 -c "import os.path; print(os.path.relpath('$SERVICE_PATH', '$PROJECT_ROOT'))")

COMPOSE_SERVICE=$(generate_compose_service \
    "$SERVICE_NAME" \
    "./${SERVICE_REL_PATH}" \
    "$PORT" \
    "$LANGUAGE" \
    "$NEEDS_MONGODB" \
    "$NEEDS_POSTGRES" \
    "$NEEDS_REDIS")

if [ "$DRY_RUN" = false ]; then
    # Backup docker-compose.yml
    cp "${PROJECT_ROOT}/docker-compose.yml" "${PROJECT_ROOT}/docker-compose.yml.backup"
    echo -e "${GREEN}  ✓ Backed up docker-compose.yml${NC}"

    # Check if service already exists
    if grep -q "^  ${SERVICE_NAME}:" "${PROJECT_ROOT}/docker-compose.yml"; then
        echo -e "${YELLOW}  ⚠ Service '${SERVICE_NAME}' already exists in docker-compose.yml${NC}"
        echo -e "${YELLOW}    Skipping addition to avoid duplicates${NC}"
    else
        # Insert before the networks section (end of services)
        # Using sed to insert before the networks: line

        # First, save the service definition to a temp file
        echo "$COMPOSE_SERVICE" > "${PROJECT_ROOT}/.service.tmp"

        # Use awk to insert the service before "networks:"
        awk '
            BEGIN { inserted = 0 }

            # When we find the networks section
            /^networks:/ {
                # Insert service before networks (only once)
                if (!inserted) {
                    # Read and print the service definition
                    while ((getline line < "'${PROJECT_ROOT}'/.service.tmp") > 0) {
                        print line
                    }
                    close("'${PROJECT_ROOT}'/.service.tmp")
                    print ""  # Add blank line before networks
                    inserted = 1
                }
                # Print the networks line
                print
                next
            }

            # Print all other lines as-is
            { print }
        ' "${PROJECT_ROOT}/docker-compose.yml" > "${PROJECT_ROOT}/docker-compose.yml.tmp"

        rm -f "${PROJECT_ROOT}/.service.tmp"
        mv "${PROJECT_ROOT}/docker-compose.yml.tmp" "${PROJECT_ROOT}/docker-compose.yml"

        # Verify the service was actually added
        if grep -q "^  ${SERVICE_NAME}:" "${PROJECT_ROOT}/docker-compose.yml"; then
            echo -e "${GREEN}  ✓ Added service to docker-compose.yml${NC}"
        else
            echo -e "${RED}  ✗ Failed to add service to docker-compose.yml${NC}"
            echo -e "${YELLOW}  Restoring backup...${NC}"
            mv "${PROJECT_ROOT}/docker-compose.yml.backup" "${PROJECT_ROOT}/docker-compose.yml"
            exit 1
        fi
    fi

    # Final verification before building
    if ! grep -q "^  ${SERVICE_NAME}:" "${PROJECT_ROOT}/docker-compose.yml"; then
        echo -e "${RED}Error: Service '${SERVICE_NAME}' not found in docker-compose.yml${NC}"
        echo -e "${YELLOW}Cannot proceed with build. Please check docker-compose.yml${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}  Would add to docker-compose.yml:${NC}"
    echo "$COMPOSE_SERVICE" | sed 's/^/    /'
fi

echo ""

# Step 3: Start the service
if [ "$DRY_RUN" = false ]; then
    echo -e "${BLUE}🚀 Starting service...${NC}"

    # Change to project root where docker-compose.yml is located
    cd "$PROJECT_ROOT" || {
        echo -e "${RED}Error: Cannot change to project root: $PROJECT_ROOT${NC}"
        exit 1
    }

    echo -e "${CYAN}  Working directory: $(pwd)${NC}"
    echo -e "${CYAN}  Verifying docker-compose.yml exists...${NC}"

    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${RED}  ✗ docker-compose.yml not found in $(pwd)${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ docker-compose.yml found${NC}"

    # Check if Traefik network exists
    if ! docker network inspect traefik >/dev/null 2>&1; then
        echo -e "${YELLOW}  Creating Traefik network...${NC}"
        docker network create traefik
    fi

    # Validate docker-compose.yml syntax
    echo -e "${CYAN}  Validating docker-compose.yml...${NC}"
    if ! docker compose config >/dev/null 2>&1; then
        echo -e "${RED}  ✗ Invalid docker-compose.yml syntax${NC}"
        echo -e "${YELLOW}  Run 'docker compose config' for details${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ docker-compose.yml is valid${NC}"

    # Build the service
    echo -e "${CYAN}  Building ${SERVICE_NAME}...${NC}"
    if ! docker compose build "$SERVICE_NAME"; then
        echo -e "${RED}  ✗ Failed to build service${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ Service built successfully${NC}"

    # Start the service
    echo -e "${CYAN}  Starting ${SERVICE_NAME}...${NC}"
    if ! docker compose up -d "$SERVICE_NAME"; then
        echo -e "${RED}  ✗ Failed to start service${NC}"
        echo -e "${YELLOW}  Check logs with: docker compose logs ${SERVICE_NAME}${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ Service started${NC}"
    echo ""

    # Add to /etc/hosts if not already present
    echo -e "${BLUE}📝 Updating /etc/hosts...${NC}"
    if ! grep -q "127.0.0.1[[:space:]]${DOMAIN}" /etc/hosts 2>/dev/null; then
        echo "127.0.0.1 ${DOMAIN}" | sudo tee -a /etc/hosts >/dev/null
        echo -e "${GREEN}  ✓ Added ${DOMAIN} to /etc/hosts${NC}"
    else
        echo -e "${YELLOW}  ⚠ ${DOMAIN} already exists in /etc/hosts${NC}"
    fi
    echo ""

    # Wait a moment for service to initialize
    sleep 2

    # Check service status
    if docker compose ps "$SERVICE_NAME" | grep -q "Up"; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                     SUCCESS!                               ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}🌐 Service URLs:${NC}"
        echo -e "  Main: ${GREEN}https://${DOMAIN}${NC}"
        echo -e "  Health: ${GREEN}https://${DOMAIN}/health${NC}"
        echo ""
        echo -e "${CYAN}📊 Useful Commands:${NC}"
        echo -e "  View logs: ${YELLOW}docker compose logs -f ${SERVICE_NAME}${NC}"
        echo -e "  Restart: ${YELLOW}docker compose restart ${SERVICE_NAME}${NC}"
        echo -e "  Stop: ${YELLOW}docker compose stop ${SERVICE_NAME}${NC}"
        echo -e "  Remove: ${YELLOW}docker compose down ${SERVICE_NAME}${NC}"
        echo ""
        echo -e "${CYAN}🎯 Next Steps:${NC}"
        echo -e "  1. Visit ${GREEN}https://${DOMAIN}${NC} to test your service"
        echo -e "  2. Check Traefik dashboard: ${GREEN}https://traefik.home.local${NC}"

        if [ "$NEEDS_MONGODB" = "true" ] || [ "$NEEDS_POSTGRES" = "true" ] || [ "$NEEDS_REDIS" = "true" ]; then
            echo -e "  3. Ensure required services are running:"
            [ "$NEEDS_MONGODB" = "true" ] && echo -e "     ${YELLOW}docker compose up -d mongodb${NC}"
            [ "$NEEDS_POSTGRES" = "true" ] && echo -e "     ${YELLOW}docker compose up -d postgres${NC}"
            [ "$NEEDS_REDIS" = "true" ] && echo -e "     ${YELLOW}docker compose up -d redis${NC}"
        fi
    else
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                  SERVICE FAILED TO START                   ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Check logs for errors:${NC}"
        echo -e "  ${CYAN}docker compose logs ${SERVICE_NAME}${NC}"
    fi
else
    echo -e "${YELLOW}🔍 DRY RUN COMPLETE${NC}"
    echo ""
    echo -e "To actually connect the service, run without --dry-run:"
    echo -e "  ${CYAN}$0 $SERVICE_PATH $SERVICE_NAME${NC}"
fi

echo ""
