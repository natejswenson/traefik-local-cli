#!/usr/bin/env bats
# Integration tests for connect-service.sh's "service already exists" branch —
# the rebuild path the tk skill's Add-handling decision relies on (see
# docs/plans/2026-07-01-tk-cli-skill-design.md, decision 10), which previously
# had zero test coverage anywhere in this suite.
#
# TK_TEST_MODE makes connect-service.sh treat $PWD as PROJECT_ROOT instead of
# the real outer repo — without it, this test would mutate the real
# docker-compose.yml and could rebuild/restart real running services.
# --domain localhost is used so the /etc/hosts branch is a guaranteed no-op
# (127.0.0.1 localhost always already exists) and never needs sudo.

load '../test_helper'

setup() {
    skip_if_no_docker
    setup_test_project
    cd "$TEST_PROJECT_DIR"
    export TK_TEST_MODE="true"
}

teardown() {
    cleanup_test_project
}

@test "connect-service.sh skips re-adding a service that already exists" {
    create_test_service "rebuild-source" "python"

    run "${SCRIPTS_DIR}/connect-service.sh" "${TEST_PROJECT_DIR}/services/rebuild-source" "test-service" --domain localhost

    assert_success
    assert_output_contains "already exists"
    assert_output_contains "Skipping addition to avoid duplicates"
}

@test "connect-service.sh's skip branch does not duplicate the existing compose entry" {
    create_test_service "rebuild-source" "python"

    run "${SCRIPTS_DIR}/connect-service.sh" "${TEST_PROJECT_DIR}/services/rebuild-source" "test-service" --domain localhost
    assert_success

    local occurrences
    occurrences=$(grep -c "^  test-service:" "$TEST_COMPOSE_FILE")
    [ "$occurrences" -eq 1 ]
}

@test "connect-service.sh's skip branch still builds/starts the existing service" {
    create_test_service "rebuild-source" "python"

    run "${SCRIPTS_DIR}/connect-service.sh" "${TEST_PROJECT_DIR}/services/rebuild-source" "test-service" --domain localhost
    assert_success
    assert_output_contains "Service built successfully"
    assert_output_contains "Service started"
}
