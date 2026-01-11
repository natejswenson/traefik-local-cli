#!/usr/bin/env bats
# Integration tests for tk version command

load '../test_helper'

@test "tk version displays version number" {
    run "${SCRIPTS_DIR}/tk" version
    assert_success
    assert_output_contains "2.0.0"
}

@test "tk --version displays version number" {
    run "${SCRIPTS_DIR}/tk" --version
    assert_success
    assert_output_contains "2.0.0"
}

@test "tk -v displays version number" {
    run "${SCRIPTS_DIR}/tk" -v
    assert_success
    assert_output_contains "2.0.0"
}

@test "tk version output is clean" {
    run "${SCRIPTS_DIR}/tk" version
    assert_success
    # Version should be in the output
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}
