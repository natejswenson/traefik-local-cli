#!/bin/bash
# Test Helper Functions
# Common utilities for all tests

# Set strict mode
set -euo pipefail

#----------------------------------------------------
# TEST ENVIRONMENT
#----------------------------------------------------

# Get directories
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${TEST_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${SCRIPTS_DIR}/.." && pwd)"
FIXTURES_DIR="${TEST_DIR}/fixtures"
COVERAGE_DIR="${TEST_DIR}/coverage"

# Export for tests
export TEST_DIR
export SCRIPTS_DIR
export PROJECT_ROOT
export FIXTURES_DIR
export COVERAGE_DIR

# Test project directory (isolated from real project)
# Use /tmp to ensure it's completely outside the project tree
export TEST_PROJECT_DIR="/tmp/tk-test-$$"
export TEST_COMPOSE_FILE="${TEST_PROJECT_DIR}/docker-compose.yml"

# Enable test mode for tk command
export TK_TEST_MODE="true"

#----------------------------------------------------
# TEST UTILITIES
#----------------------------------------------------

# Setup test project environment
setup_test_project() {
    # Create isolated test project directory
    rm -rf "$TEST_PROJECT_DIR"
    mkdir -p "$TEST_PROJECT_DIR"
    mkdir -p "$TEST_PROJECT_DIR/services"
    mkdir -p "$TEST_PROJECT_DIR/traefik"

    # Create minimal docker-compose.yml
    cat > "$TEST_COMPOSE_FILE" <<'EOF'
version: '3.8'

services:
  traefik:
    image: traefik:latest
    container_name: traefik-test
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
    ports:
      - "8080:8080"
      - "80:80"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - traefik

  test-service:
    image: nginx:alpine
    container_name: test-service
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.test-service.rule=Host(`test.localhost`)"
    networks:
      - traefik

networks:
  traefik:
    name: traefik-test
    driver: bridge
EOF

    # Create traefik config
    cat > "$TEST_PROJECT_DIR/traefik/traefik.yml" <<'EOF'
api:
  dashboard: true
  insecure: true

providers:
  docker:
    exposedByDefault: false
EOF
}

# Cleanup test project
cleanup_test_project() {
    if [ -d "$TEST_PROJECT_DIR" ]; then
        # Stop any running containers
        (cd "$TEST_PROJECT_DIR" && docker compose down -v 2>/dev/null) || true
        # Remove test network
        docker network rm traefik-test 2>/dev/null || true
        # Remove directory
        rm -rf "$TEST_PROJECT_DIR"
    fi
}

# Mock docker compose command for unit tests
mock_docker_compose() {
    local response="$1"
    export -f docker
    docker() {
        if [ "$1" = "compose" ]; then
            echo "$response"
            return 0
        fi
        command docker "$@"
    }
}

# Restore real docker command
restore_docker() {
    unset -f docker 2>/dev/null || true
}

# Create test service directory
create_test_service() {
    local service_name="$1"
    local service_type="${2:-python}"
    local service_dir="${TEST_PROJECT_DIR}/services/${service_name}"

    mkdir -p "$service_dir"

    if [ "$service_type" = "python" ]; then
        cat > "$service_dir/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY . .
CMD ["python", "-m", "http.server", "8000"]
EOF
        cat > "$service_dir/main.py" <<'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"healthy"}')

if __name__ == '__main__':
    HTTPServer(('', 8000), HealthHandler).serve_forever()
EOF
    elif [ "$service_type" = "node" ]; then
        cat > "$service_dir/Dockerfile" <<'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["node", "index.js"]
EOF
        cat > "$service_dir/package.json" <<'EOF'
{
  "name": "test-service",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF
        cat > "$service_dir/index.js" <<'EOF'
const express = require('express');
const app = express();
app.get('/health', (req, res) => res.json({ status: 'healthy' }));
app.listen(3000);
EOF
    fi
}

# Assert command succeeds
assert_success() {
    if [ "$status" -ne 0 ]; then
        echo "Expected success but got status: $status"
        echo "Output: $output"
        return 1
    fi
}

# Assert command fails
assert_failure() {
    if [ "$status" -eq 0 ]; then
        echo "Expected failure but command succeeded"
        echo "Output: $output"
        return 1
    fi
}

# Assert output contains string
assert_output_contains() {
    local expected="$1"
    if [[ ! "$output" =~ $expected ]]; then
        echo "Expected output to contain: $expected"
        echo "Actual output: $output"
        return 1
    fi
}

# Assert output equals string
assert_output_equals() {
    local expected="$1"
    if [ "$output" != "$expected" ]; then
        echo "Expected output: $expected"
        echo "Actual output: $output"
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "Expected file to exist: $file"
        return 1
    fi
}

# Assert file contains string
assert_file_contains() {
    local file="$1"
    local expected="$2"
    if [ ! -f "$file" ]; then
        echo "File does not exist: $file"
        return 1
    fi
    if ! grep -q "$expected" "$file"; then
        echo "Expected file $file to contain: $expected"
        return 1
    fi
}

# Skip test if Docker is not available
skip_if_no_docker() {
    if ! command -v docker &> /dev/null; then
        skip "Docker is not available"
    fi
    if ! docker info &> /dev/null; then
        skip "Docker daemon is not running"
    fi
}

# Skip test if not running in CI
skip_if_not_ci() {
    if [ -z "${CI:-}" ]; then
        skip "Only runs in CI environment"
    fi
}

# Wait for service to be healthy
wait_for_service() {
    local service_name="$1"
    local max_wait="${2:-30}"
    local count=0

    while [ $count -lt $max_wait ]; do
        if docker compose -f "$TEST_COMPOSE_FILE" ps "$service_name" 2>/dev/null | grep -q "healthy"; then
            return 0
        fi
        sleep 1
        ((count++))
    done

    echo "Service $service_name did not become healthy within ${max_wait}s"
    return 1
}

#----------------------------------------------------
# EXPORT FUNCTIONS
#----------------------------------------------------

export -f setup_test_project
export -f cleanup_test_project
export -f create_test_service
export -f mock_docker_compose
export -f restore_docker
export -f assert_success
export -f assert_failure
export -f assert_output_contains
export -f assert_output_equals
export -f assert_file_exists
export -f assert_file_contains
export -f skip_if_no_docker
export -f skip_if_not_ci
export -f wait_for_service
