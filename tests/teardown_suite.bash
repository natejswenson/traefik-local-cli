#!/bin/bash
# Teardown Suite - Runs once after all tests

# Source test helper
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.bash"

# Teardown suite
teardown_suite() {
    echo "=== Test Suite Teardown ===" >&3

    # Cleanup test environment
    cleanup_test_project

    # Remove test containers and networks
    docker network rm traefik-test 2>/dev/null || true

    # Clean up any leftover test directories in /tmp
    rm -rf /tmp/tk-test-* 2>/dev/null || true
    rm -rf /tmp/tk-test-empty-* 2>/dev/null || true

    # Display coverage summary if available
    if [ -f "$COVERAGE_DIR/coverage-summary.txt" ]; then
        echo "" >&3
        echo "=== Coverage Summary ===" >&3
        cat "$COVERAGE_DIR/coverage-summary.txt" >&3
    fi

    echo "Test environment cleaned up" >&3
}
