#!/bin/bash
# Setup Suite - Runs once before all tests

# Source test helper
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.bash"

# Setup suite
setup_suite() {
    echo "=== Test Suite Setup ===" >&3

    # Ensure coverage directory exists
    mkdir -p "$COVERAGE_DIR"

    # Clean up any leftover test containers/networks
    docker compose -f "$TEST_COMPOSE_FILE" down -v 2>/dev/null || true
    docker network rm traefik-test 2>/dev/null || true

    # Create test project directory
    setup_test_project

    echo "Test environment initialized" >&3
}
