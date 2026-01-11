#!/usr/bin/env bats
# Unit tests for tk-logging.sh

load '../test_helper'

setup() {
    source "${SCRIPTS_DIR}/lib/tk-logging.sh"
    export LOG_LEVEL="DEBUG"
    export LOG_FILE="/tmp/test-tk.log"
    rm -f "$LOG_FILE"
}

teardown() {
    rm -f "$LOG_FILE"
}

@test "log_info logs INFO level messages" {
    run log_info "Test info message"
    assert_success
    assert_output_contains "[INFO]"
    assert_output_contains "Test info message"
}

@test "log_error logs ERROR level messages" {
    run log_error "Test error message"
    assert_success
    assert_output_contains "[ERROR]"
    assert_output_contains "Test error message"
}

@test "log_warn logs WARN level messages" {
    run log_warn "Test warning message"
    assert_success
    assert_output_contains "[WARN]"
    assert_output_contains "Test warning message"
}

@test "log_debug logs DEBUG level messages when LOG_LEVEL=DEBUG" {
    export LOG_LEVEL="DEBUG"
    run log_debug "Test debug message"
    assert_success
    assert_output_contains "[DEBUG]"
    assert_output_contains "Test debug message"
}

@test "log_debug does not output when LOG_LEVEL=INFO" {
    export LOG_LEVEL="INFO"
    run log_debug "Test debug message"
    [ -z "$output" ]
}

@test "log writes to log file" {
    log_info "Test log file"
    assert_file_exists "$LOG_FILE"
    assert_file_contains "$LOG_FILE" "Test log file"
}

@test "get_log_level_value returns correct numeric values" {
    run get_log_level_value "DEBUG"
    [ "$output" = "0" ]

    run get_log_level_value "INFO"
    [ "$output" = "1" ]

    run get_log_level_value "WARN"
    [ "$output" = "2" ]

    run get_log_level_value "ERROR"
    [ "$output" = "3" ]

    run get_log_level_value "FATAL"
    [ "$output" = "4" ]
}

@test "print_success displays success message" {
    run print_success "Operation completed"
    assert_success
    assert_output_contains "Operation completed"
}

@test "print_error displays error message" {
    run print_error "Operation failed"
    assert_success
    assert_output_contains "Operation failed"
}

@test "print_header displays formatted header" {
    run print_header "Test Header"
    assert_success
    assert_output_contains "Test Header"
}

@test "print_status displays service status" {
    run print_status "test-service" "running" "healthy"
    assert_success
    assert_output_contains "test-service"
    assert_output_contains "running"
}

@test "log functions handle special characters" {
    # Escape the $ to avoid variable expansion
    run log_info 'Message with $special @chars #test'
    assert_success
    assert_output_contains "Message with"
    assert_output_contains '@chars'
}

@test "log functions handle multiline messages" {
    run log_info "Line 1
Line 2"
    assert_success
    assert_output_contains "Line 1"
}
