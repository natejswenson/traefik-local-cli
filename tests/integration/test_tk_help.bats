#!/usr/bin/env bats
# Integration tests for tk --help and tk help commands

load '../test_helper'

setup() {
    source "${SCRIPTS_DIR}/lib/tk-common.sh"
}

@test "tk --help displays help message" {
    run "${SCRIPTS_DIR}/tk" --help
    assert_success
    assert_output_contains "Traefik CLI"
    assert_output_contains "Usage:"
    assert_output_contains "Commands:"
}

@test "tk help displays help message" {
    run "${SCRIPTS_DIR}/tk" help
    assert_success
    assert_output_contains "Traefik CLI"
    assert_output_contains "Commands:"
}

@test "tk --help shows all commands" {
    run "${SCRIPTS_DIR}/tk" --help
    assert_success
    assert_output_contains "add"
    assert_output_contains "remove"
    assert_output_contains "start"
    assert_output_contains "stop"
    assert_output_contains "restart"
    assert_output_contains "logs"
    assert_output_contains "list"
    assert_output_contains "status"
    assert_output_contains "cleanup"
}

@test "tk --help shows examples" {
    run "${SCRIPTS_DIR}/tk" --help
    assert_success
    assert_output_contains "Examples:"
}

@test "tk help shows version information" {
    run "${SCRIPTS_DIR}/tk" --help
    assert_success
    assert_output_contains "v2.0.0"
}

@test "tk with no arguments shows help" {
    run "${SCRIPTS_DIR}/tk"
    assert_output_contains "Usage:"
}

@test "tk with invalid command shows error and help" {
    run "${SCRIPTS_DIR}/tk" invalid-command
    assert_failure
    assert_output_contains "Unknown command"
}
