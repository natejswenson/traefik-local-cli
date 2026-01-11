#!/usr/bin/env bats
# Integration tests for tk list command

load '../test_helper'

setup() {
    setup_test_project
    cd "$TEST_PROJECT_DIR"
}

teardown() {
    cleanup_test_project
}

@test "tk list shows services from docker-compose.yml" {
    run "${SCRIPTS_DIR}/tk" list
    assert_success
    assert_output_contains "traefik"
    assert_output_contains "test-service"
}

@test "tk list works from project root" {
    cd "$TEST_PROJECT_DIR"
    run "${SCRIPTS_DIR}/tk" list
    assert_success
}

@test "tk list shows header" {
    run "${SCRIPTS_DIR}/tk" list
    assert_success
    assert_output_contains "Services"
}

@test "tk list fails when no docker-compose.yml exists" {
    # Create a completely empty directory with no docker-compose.yml
    # Must have a traefik/ dir or tk won't recognize it as project root
    local empty_dir="/tmp/tk-test-empty-$$"
    mkdir -p "$empty_dir"

    # Don't create traefik/ - this makes find_project_root fail
    cd "$empty_dir"
    run "${SCRIPTS_DIR}/tk" list

    # Clean up
    cd /tmp
    rm -rf "$empty_dir"

    # Should fail since no docker-compose.yml exists
    assert_failure
}

@test "tk list displays all services" {
    # Add another service to compose file (before networks section)
    # Need to insert before the networks: line
    local temp_file="${TEST_COMPOSE_FILE}.tmp"

    # Split at networks section, add service, rejoin
    sed '/^networks:/,$d' "$TEST_COMPOSE_FILE" > "$temp_file"
    cat >> "$temp_file" <<'EOF'
  another-service:
    image: nginx:alpine
    container_name: another-service
    labels:
      - "traefik.enable=true"
    networks:
      - traefik

EOF
    sed -n '/^networks:/,$p' "$TEST_COMPOSE_FILE" >> "$temp_file"
    mv "$temp_file" "$TEST_COMPOSE_FILE"

    # Verify file was modified
    grep -q "another-service" "$TEST_COMPOSE_FILE" || {
        echo "Failed to add another-service to compose file" >&2
        cat "$TEST_COMPOSE_FILE" >&2
        return 1
    }

    run "${SCRIPTS_DIR}/tk" list
    assert_success
    assert_output_contains "traefik"
    assert_output_contains "test-service"
    assert_output_contains "another-service"
}
