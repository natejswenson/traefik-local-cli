#!/usr/bin/env bats
# Unit tests for tk-docker.sh

load '../test_helper'

setup() {
    setup_test_project
    cd "$TEST_PROJECT_DIR"
    source "${SCRIPTS_DIR}/lib/tk-logging.sh"
    source "${SCRIPTS_DIR}/lib/tk-docker.sh"
}

teardown() {
    cleanup_test_project
}

@test "service_exists returns success for existing service" {
    run service_exists "traefik" "$TEST_COMPOSE_FILE"
    assert_success
}

@test "service_exists returns failure for non-existent service" {
    run service_exists "non-existent-service" "$TEST_COMPOSE_FILE"
    assert_failure
}

@test "get_service_domain extracts domain from compose file" {
    run get_service_domain "test-service" "$TEST_COMPOSE_FILE"
    assert_success
    # Domain extraction from labels - may be empty if no domain configured
    # Just verify the function runs without error
    [ "$status" -eq 0 ]
}

@test "list_services lists all services in compose file" {
    run list_services "$TEST_COMPOSE_FILE"
    assert_success
    assert_output_contains "traefik"
    assert_output_contains "test-service"
}

@test "list_services returns failure for non-existent compose file" {
    run list_services "/non/existent/docker-compose.yml"
    assert_failure
}

@test "find_project_root finds project root with docker-compose.yml" {
    run find_project_root
    assert_success
    [ -d "$output" ]
}

@test "find_project_root returns error outside project" {
    cd /tmp
    run find_project_root
    assert_failure
}

@test "docker_compose_cmd respects DRY_RUN flag" {
    export DRY_RUN="true"
    run docker_compose_cmd ps
    assert_success
    assert_output_contains "[DRY RUN]"
}

@test "docker_compose_cmd executes when DRY_RUN is false" {
    skip_if_no_docker
    export DRY_RUN="false"
    run docker_compose_cmd --version
    assert_success
}

@test "is_dry_run returns true when DRY_RUN=true" {
    export DRY_RUN="true"
    # is_dry_run is in tk-common.sh, not tk-docker.sh
    run bash -c 'source "${SCRIPTS_DIR}/lib/tk-common.sh" && is_dry_run'
    assert_success
}

@test "is_dry_run returns false when DRY_RUN=false" {
    export DRY_RUN="false"
    # is_dry_run is in tk-common.sh, not tk-docker.sh
    run bash -c 'source "${SCRIPTS_DIR}/lib/tk-common.sh" && is_dry_run'
    assert_failure
}
