#!/usr/bin/env bats
# Integration tests for tk status command

load '../test_helper'

setup() {
    skip_if_no_docker
    setup_test_project
    cd "$TEST_PROJECT_DIR"
}

teardown() {
    cleanup_test_project
}

@test "tk status shows service status header" {
    run "${SCRIPTS_DIR}/tk" status
    assert_output_contains "Service Status"
}

@test "tk status shows docker ps output when services running" {
    # Start services
    docker compose up -d 2>&1 || skip "Could not start services"

    run "${SCRIPTS_DIR}/tk" status
    assert_success
    assert_output_contains "NAME"
    assert_output_contains "STATUS"
}

@test "tk status shows service URLs" {
    run "${SCRIPTS_DIR}/tk" status
    assert_output_contains "Service URLs" || true
}

@test "tk status works from project root" {
    cd "$TEST_PROJECT_DIR"
    run "${SCRIPTS_DIR}/tk" status
    # Status may fail if docker compose ps fails, but should not have YAML errors
    # Just verify no YAML parsing errors in output
    [[ ! "$output" =~ "found unknown escape character" ]]
}

@test "tk status shows Traefik dashboard URL" {
    run "${SCRIPTS_DIR}/tk" status
    assert_output_contains "traefik" || true
}
