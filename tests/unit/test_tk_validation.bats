#!/usr/bin/env bats
# Unit tests for tk-validation.sh

load '../test_helper'

setup() {
    source "${SCRIPTS_DIR}/lib/tk-logging.sh"
    source "${SCRIPTS_DIR}/lib/tk-validation.sh"
}

@test "validate_service_name accepts valid names" {
    run validate_service_name "my-service"
    assert_success

    run validate_service_name "api-v2"
    assert_success

    run validate_service_name "service123"
    assert_success

    run validate_service_name "a"
    assert_success
}

@test "validate_service_name rejects empty names" {
    run validate_service_name ""
    assert_failure
}

@test "validate_service_name rejects invalid characters" {
    run validate_service_name "service@name"
    assert_failure

    run validate_service_name "service name"
    assert_failure

    run validate_service_name "service.name"
    assert_failure

    # Uppercase not allowed
    run validate_service_name "MyService"
    assert_failure

    run validate_service_name "Service123"
    assert_failure

    # Underscores not allowed
    run validate_service_name "api_v2"
    assert_failure

    run validate_service_name "my_service"
    assert_failure

    # Must start with letter
    run validate_service_name "123service"
    assert_failure

    run validate_service_name "-myservice"
    assert_failure
}

@test "validate_service_name rejects names over 63 characters" {
    # Max is 63 characters per DNS spec
    local valid_63=$(printf 'a%.0s' {1..63})
    run validate_service_name "$valid_63"
    assert_success

    # 64 characters should fail
    local invalid_64=$(printf 'a%.0s' {1..64})
    run validate_service_name "$invalid_64"
    assert_failure
}

@test "validate_service_name rejects reserved names" {
    run validate_service_name "traefik"
    assert_failure

    run validate_service_name "mongodb"
    assert_failure

    run validate_service_name "postgres"
    assert_failure

    run validate_service_name "redis"
    assert_failure

    run validate_service_name "localhost"
    assert_failure

    run validate_service_name "docker"
    assert_failure
}

@test "validate_domain accepts valid domains" {
    run validate_domain "example.localhost"
    assert_success

    run validate_domain "api.example.com"
    assert_success

    run validate_domain "service.home.local"
    assert_success
}

@test "validate_domain rejects empty domains" {
    run validate_domain ""
    assert_failure
}

@test "validate_domain rejects invalid formats" {
    run validate_domain "invalid..domain"
    assert_failure

    run validate_domain ".invalid"
    assert_failure

    run validate_domain "invalid domain"
    assert_failure
}

@test "validate_port accepts valid ports" {
    run validate_port "80"
    assert_success

    run validate_port "8080"
    assert_success

    run validate_port "65535"
    assert_success
}

@test "validate_port rejects invalid ports" {
    run validate_port "0"
    assert_failure

    run validate_port "65536"
    assert_failure

    run validate_port "-1"
    assert_failure

    run validate_port "abc"
    assert_failure
}

@test "validate_port warns for privileged ports" {
    run validate_port "80"
    assert_success
    assert_output_contains "privileged"
}

@test "validate_path accepts existing files" {
    touch /tmp/test-file.txt
    run validate_path "/tmp/test-file.txt" "file"
    assert_success
    rm /tmp/test-file.txt
}

@test "validate_path accepts existing directories" {
    mkdir -p /tmp/test-dir
    run validate_path "/tmp/test-dir" "dir"
    assert_success
    rmdir /tmp/test-dir
}

@test "validate_path rejects non-existent paths" {
    run validate_path "/non/existent/path"
    assert_failure
}

@test "validate_path rejects path traversal attempts" {
    run validate_path "../../../etc/passwd"
    assert_failure
}

@test "validate_docker succeeds when Docker is available" {
    skip_if_no_docker
    run validate_docker
    assert_success
}

@test "validate_docker_compose succeeds when Docker Compose is available" {
    skip_if_no_docker
    run validate_docker_compose
    assert_success
}

@test "sanitize_env_value removes dangerous characters" {
    run sanitize_env_value "value;rm -rf /"
    assert_success
    [[ ! "$output" =~ ";" ]]

    run sanitize_env_value "value|command"
    [[ ! "$output" =~ "|" ]]

    run sanitize_env_value "value\`command\`"
    [[ ! "$output" =~ "\`" ]]
}

@test "validate_env_name accepts valid environment variable names" {
    run validate_env_name "MY_VAR"
    assert_success

    run validate_env_name "SERVICE_PORT"
    assert_success

    run validate_env_name "_PRIVATE_VAR"
    assert_success
}

@test "validate_env_name rejects invalid names" {
    run validate_env_name "123VAR"
    assert_failure

    run validate_env_name "my-var"
    assert_failure

    run validate_env_name "my.var"
    assert_failure
}
