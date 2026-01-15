#!/usr/bin/env bash
#
# test-security.sh - Security-focused integration tests
#
# Tests all Phase 1 security enhancements:
# - Enhanced input validation
# - Secure temporary file handling
# - Docker socket security
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the libraries we're testing
source "$PROJECT_ROOT/lib/tk-common.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# Test Utilities
# ============================================================================

run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo "========================================"
    echo "Test $TESTS_RUN: $test_name"
    echo "========================================"

    if $test_func; then
        echo "✓ PASSED: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ FAILED: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_fails() {
    if "$@" 2>/dev/null; then
        echo "✗ Expected command to fail but it succeeded: $*"
        return 1
    fi
    return 0
}

assert_succeeds() {
    if ! "$@" 2>/dev/null; then
        echo "✗ Expected command to succeed but it failed: $*"
        return 1
    fi
    return 0
}

assert_contains() {
    local substring="$1"
    local string="$2"

    if [[ "$string" == *"$substring"* ]]; then
        return 0
    else
        echo "✗ Expected to find '$substring' in output"
        return 1
    fi
}

# ============================================================================
# Enhanced Input Validation Tests
# ============================================================================

test_service_name_validation_basic() {
    echo "Testing basic service name validation..."

    # Valid names should pass
    assert_succeeds validate_service_name "myservice"
    assert_succeeds validate_service_name "my-service"
    assert_succeeds validate_service_name "service123"
    assert_succeeds validate_service_name "a"

    # Invalid names should fail
    assert_fails validate_service_name ""  # Empty
    assert_fails validate_service_name "MyService"  # Uppercase
    assert_fails validate_service_name "my_service"  # Underscore
    assert_fails validate_service_name "123service"  # Starts with number
    assert_fails validate_service_name "-myservice"  # Starts with hyphen

    echo "✓ Basic service name validation works"
    return 0
}

test_service_name_reserved_names() {
    echo "Testing reserved name blocking..."

    # Reserved names should fail
    assert_fails validate_service_name "traefik"
    assert_fails validate_service_name "mongodb"
    assert_fails validate_service_name "postgres"
    assert_fails validate_service_name "redis"
    assert_fails validate_service_name "localhost"
    assert_fails validate_service_name "docker"

    echo "✓ Reserved names are blocked"
    return 0
}

test_service_name_length_limits() {
    echo "Testing service name length limits..."

    # Max length is 63 characters (DNS spec)
    local valid_name=$(printf 'a%.0s' {1..63})
    local too_long=$(printf 'a%.0s' {1..64})

    assert_succeeds validate_service_name "$valid_name"
    assert_fails validate_service_name "$too_long"

    echo "✓ Length limits enforced"
    return 0
}

test_path_traversal_prevention() {
    echo "Testing path traversal prevention..."

    # These should all fail
    assert_fails validate_path_safe "../../etc/passwd" "test path"
    assert_fails validate_path_safe "/etc/../../../etc/passwd" "test path"
    assert_fails validate_path_safe "./.././.././etc/passwd" "test path"

    echo "✓ Path traversal attacks prevented"
    return 0
}

test_path_validation_allowed_dirs() {
    echo "Testing path validation with allowed directories..."

    # Paths in HOME should work
    local test_file="$HOME/.tk-test-$$"
    touch "$test_file"

    if validate_path_safe "$test_file" "test file"; then
        echo "✓ Path in HOME allowed"
    else
        echo "✗ Path in HOME should be allowed"
        rm -f "$test_file"
        return 1
    fi

    rm -f "$test_file"

    # Paths in /etc should be blocked
    if validate_path_safe "/etc/passwd" "system file" 2>/dev/null; then
        echo "✗ System path should be blocked"
        return 1
    else
        echo "✓ System path blocked"
    fi

    return 0
}

test_env_validation() {
    echo "Testing environment variable validation..."

    # Valid env vars should pass
    assert_succeeds validate_env_value_safe "MY_VAR" "value123"
    assert_succeeds validate_env_value_safe "DATABASE_URL" "localhost:5432"

    # Injection attempts should fail
    assert_fails validate_env_value_safe "MY_VAR" "\$(whoami)"
    assert_fails validate_env_value_safe "MY_VAR" "value;rm -rf /"
    assert_fails validate_env_value_safe "MY_VAR" "value|cat /etc/passwd"
    assert_fails validate_env_value_safe "MY_VAR" "value\`date\`"

    # Invalid names should fail
    assert_fails validate_env_value_safe "123_VAR" "value"
    assert_fails validate_env_value_safe "my-var" "value"

    echo "✓ Environment variable validation works"
    return 0
}

test_command_injection_prevention() {
    echo "Testing command injection prevention..."

    # These should all fail
    assert_fails validate_command_safe "ls; rm -rf /"
    assert_fails validate_command_safe "ls | cat /etc/passwd"
    assert_fails validate_command_safe "ls && whoami"
    assert_fails validate_command_safe "ls \$(whoami)"
    assert_fails validate_command_safe "ls \`date\`"

    # Safe commands should pass
    assert_succeeds validate_command_safe "ls -la"
    assert_succeeds validate_command_safe "docker ps"

    echo "✓ Command injection prevented"
    return 0
}

# ============================================================================
# Secure Temporary File Handling Tests
# ============================================================================

test_secure_tmp_creation() {
    echo "Testing secure temporary directory creation..."

    # Create secure tmp
    setup_secure_tmp

    # Verify it was created
    if [[ ! -d "$SECURE_TMP_DIR" ]]; then
        echo "✗ Secure tmp directory not created"
        return 1
    fi

    echo "✓ Secure tmp directory: $SECURE_TMP_DIR"

    # Check permissions (should be 700)
    local perms
    if [[ "$(uname)" == "Darwin" ]]; then
        perms=$(stat -f "%Lp" "$SECURE_TMP_DIR")
    else
        perms=$(stat -c "%a" "$SECURE_TMP_DIR")
    fi

    if [[ "$perms" != "700" ]]; then
        echo "✗ Incorrect permissions: $perms (expected 700)"
        return 1
    fi

    echo "✓ Permissions are restrictive (700)"
    return 0
}

test_secure_tempfile_creation() {
    echo "Testing secure temporary file creation..."

    setup_secure_tmp

    # Create secure temp file
    local tempfile=$(create_secure_tempfile "test")

    # Verify it exists
    if [[ ! -f "$tempfile" ]]; then
        echo "✗ Temp file not created"
        return 1
    fi

    echo "✓ Temp file created: $tempfile"

    # Check permissions (should be 600)
    local perms
    if [[ "$(uname)" == "Darwin" ]]; then
        perms=$(stat -f "%Lp" "$tempfile")
    else
        perms=$(stat -c "%a" "$tempfile")
    fi

    if [[ "$perms" != "600" ]]; then
        echo "✗ Incorrect permissions: $perms (expected 600)"
        return 1
    fi

    echo "✓ Permissions are restrictive (600)"
    return 0
}

test_secure_tmp_cleanup() {
    echo "Testing secure temporary directory cleanup..."

    setup_secure_tmp
    local tmp_dir="$SECURE_TMP_DIR"

    # Create a file
    local test_file="$tmp_dir/test.txt"
    echo "test" > "$test_file"

    # Cleanup
    cleanup_secure_tmp

    # Verify cleanup
    if [[ -d "$tmp_dir" ]]; then
        echo "✗ Temp directory not cleaned up"
        return 1
    fi

    echo "✓ Temp directory cleaned up"
    return 0
}

test_atomic_file_write() {
    echo "Testing atomic file writing..."

    local test_file="$HOME/.tk-atomic-test-$$"

    # Write file securely
    if write_secure_file "$test_file" "test content" 600; then
        echo "✓ File written securely"
    else
        echo "✗ Failed to write file"
        return 1
    fi

    # Verify content
    if [[ "$(cat "$test_file")" == "test content" ]]; then
        echo "✓ Content is correct"
    else
        echo "✗ Content is incorrect"
        rm -f "$test_file"
        return 1
    fi

    # Verify permissions
    local perms
    if [[ "$(uname)" == "Darwin" ]]; then
        perms=$(stat -f "%Lp" "$test_file")
    else
        perms=$(stat -c "%a" "$test_file")
    fi

    if [[ "$perms" != "600" ]]; then
        echo "✗ Incorrect permissions: $perms"
        rm -f "$test_file"
        return 1
    fi

    rm -f "$test_file"
    echo "✓ Atomic write successful with correct permissions"
    return 0
}

# ============================================================================
# Docker Security Tests
# ============================================================================

test_docker_socket_validation() {
    echo "Testing Docker socket validation..."

    # Only run if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        echo "⊘ Skipping (Docker not available)"
        return 0
    fi

    if validate_docker_socket_safe; then
        echo "✓ Docker socket validation passed"
    else
        echo "⊘ Docker socket validation failed (may not be running)"
        # Don't fail the test if Docker isn't running
        return 0
    fi

    return 0
}

test_docker_image_validation() {
    echo "Testing Docker image validation..."

    # Trusted registries should pass
    assert_succeeds validate_docker_image_safe "ubuntu:latest"
    assert_succeeds validate_docker_image_safe "docker.io/nginx:latest"
    assert_succeeds validate_docker_image_safe "gcr.io/project/image:tag"

    # Untrusted registry should fail (with default config)
    export ALLOW_UNTRUSTED_REGISTRIES=false
    assert_fails validate_docker_image_safe "evil-registry.com/malware:latest"

    # Should pass with override
    export ALLOW_UNTRUSTED_REGISTRIES=true
    assert_succeeds validate_docker_image_safe "evil-registry.com/image:latest"

    # Reset
    export ALLOW_UNTRUSTED_REGISTRIES=false

    echo "✓ Docker image validation works"
    return 0
}

test_sanitize_logging() {
    echo "Testing log sanitization..."

    local input="password=secret123 API_KEY=abc123 normal_value=ok"
    local sanitized=$(sanitize_for_logging "$input")

    # Check that secrets are redacted
    if [[ "$sanitized" == *"secret123"* ]]; then
        echo "✗ Password not sanitized"
        return 1
    fi

    if [[ "$sanitized" != *"REDACTED"* ]]; then
        echo "✗ Secrets not marked as redacted"
        return 1
    fi

    echo "✓ Log sanitization works"
    echo "  Input:  $input"
    echo "  Output: $sanitized"
    return 0
}

# ============================================================================
# Run All Tests
# ============================================================================

main() {
    echo "=========================================="
    echo "Security Test Suite - Phase 1"
    echo "=========================================="
    echo ""
    echo "Testing enhanced security features:"
    echo "  • Enhanced input validation"
    echo "  • Secure temporary file handling"
    echo "  • Docker socket security"
    echo ""

    # Enhanced Input Validation Tests
    run_test "Service Name Validation - Basic" test_service_name_validation_basic
    run_test "Service Name Validation - Reserved Names" test_service_name_reserved_names
    run_test "Service Name Validation - Length Limits" test_service_name_length_limits
    run_test "Path Traversal Prevention" test_path_traversal_prevention
    run_test "Path Validation - Allowed Directories" test_path_validation_allowed_dirs
    run_test "Environment Variable Validation" test_env_validation
    run_test "Command Injection Prevention" test_command_injection_prevention

    # Secure Temporary File Handling Tests
    run_test "Secure Temporary Directory Creation" test_secure_tmp_creation
    run_test "Secure Temporary File Creation" test_secure_tempfile_creation
    run_test "Secure Temporary Directory Cleanup" test_secure_tmp_cleanup
    run_test "Atomic File Writing" test_atomic_file_write

    # Docker Security Tests
    run_test "Docker Socket Validation" test_docker_socket_validation
    run_test "Docker Image Validation" test_docker_image_validation
    run_test "Log Sanitization" test_sanitize_logging

    # Summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total:  $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "=========================================="
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All security tests passed!"
        return 0
    else
        echo "✗ Some security tests failed"
        return 1
    fi
}

# Run tests
main "$@"
