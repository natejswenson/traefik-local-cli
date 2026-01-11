# Traefik Scripts Test Suite

Comprehensive integration and unit test suite for the Traefik CLI (tk) with 95%+ code coverage.

## 📁 Structure

```
tests/
├── README.md              This file
├── test_helper.bash       Common test utilities and assertions
├── setup_suite.bash       Suite-level setup (runs once before all tests)
├── teardown_suite.bash    Suite-level teardown (runs once after all tests)
│
├── integration/           Integration tests for tk commands
│   ├── test_tk_help.bats
│   ├── test_tk_version.bats
│   ├── test_tk_list.bats
│   └── test_tk_status.bats
│
├── unit/                  Unit tests for library modules
│   ├── test_tk_logging.bats
│   ├── test_tk_validation.bats
│   └── test_tk_docker.bats
│
├── fixtures/              Test fixtures and mock data
└── coverage/              Coverage reports (generated)
```

## 🚀 Quick Start

### Prerequisites

**macOS:**
```bash
brew install bats-core
brew install kcov  # For coverage
```

**Ubuntu/Debian:**
```bash
sudo apt-get install bats
sudo apt-get install kcov  # For coverage
```

**npm (any platform):**
```bash
npm install -g bats
```

### Running Tests

```bash
# Run all tests
./run-tests.sh

# Run only unit tests
./run-tests.sh --unit

# Run only integration tests
./run-tests.sh --integration

# Run tests with coverage report
./run-tests.sh --coverage

# Verbose output
./run-tests.sh --verbose

# Get help
./run-tests.sh --help
```

## 📊 Coverage

The test suite targets **95% code coverage** minimum.

### View Coverage Report

```bash
# Generate coverage
./run-tests.sh --coverage

# Open HTML report
open tests/coverage/merged/index.html
```

### Coverage Breakdown

- **Unit Tests**: Test individual library functions in isolation
- **Integration Tests**: Test tk commands end-to-end
- **Combined Coverage**: Merged report showing overall coverage

## ✅ Test Categories

### Integration Tests

Test the complete tk CLI commands from end-to-end:

- **test_tk_help.bats** - Help and usage information
- **test_tk_version.bats** - Version display
- **test_tk_list.bats** - Service listing
- **test_tk_status.bats** - Service status checking

### Unit Tests

Test individual library modules:

- **test_tk_logging.bats** - Logging functions (log_info, log_error, etc.)
- **test_tk_validation.bats** - Input validation (service names, domains, ports)
- **test_tk_docker.bats** - Docker operations (compose commands, service checks)

## 🔧 Writing Tests

### Test File Template

```bash
#!/usr/bin/env bats
# Test description

load '../test_helper'

setup() {
    # Runs before each test
    source "${SCRIPTS_DIR}/lib/tk-common.sh"
}

teardown() {
    # Runs after each test
    cleanup_test_project
}

@test "description of what is being tested" {
    run command_to_test

    # Assertions
    assert_success
    assert_output_contains "expected output"
}
```

### Available Assertions

```bash
# Status assertions
assert_success              # Command exit code is 0
assert_failure              # Command exit code is non-zero

# Output assertions
assert_output_contains "text"   # Output contains text
assert_output_equals "text"     # Output exactly equals text

# File assertions
assert_file_exists "/path"      # File exists
assert_file_contains "/path" "text"  # File contains text

# Skip conditions
skip_if_no_docker          # Skip if Docker unavailable
skip_if_not_ci             # Skip outside CI environment
```

### Test Helpers

```bash
# Environment setup
setup_test_project()       # Create isolated test environment
cleanup_test_project()     # Clean up test environment
create_test_service(name, type)  # Create test service

# Docker mocking
mock_docker_compose(response)    # Mock docker compose output
restore_docker()                 # Restore real docker command

# Wait utilities
wait_for_service(name, timeout)  # Wait for service health
```

## 🎯 Best Practices

### 1. **Isolation**
Each test should be independent and not rely on other tests:

```bash
setup() {
    setup_test_project  # Fresh environment
}

teardown() {
    cleanup_test_project  # Clean up
}
```

### 2. **Descriptive Names**
Use clear, descriptive test names:

```bash
# Good
@test "validate_port rejects ports above 65535"

# Bad
@test "test port validation"
```

### 3. **Fast Tests**
Keep tests fast by mocking when possible:

```bash
# Mock instead of real Docker commands in unit tests
mock_docker_compose "traefik running"
```

### 4. **Comprehensive Coverage**
Test happy path, edge cases, and error conditions:

```bash
@test "accepts valid input"
@test "rejects empty input"
@test "rejects invalid characters"
@test "handles special cases"
```

### 5. **Clear Failures**
Provide helpful failure messages:

```bash
assert_output_contains "expected text" || {
    echo "Expected: expected text"
    echo "Actual: $output"
    return 1
}
```

## 🔄 CI/CD Integration

### GitHub Actions

Tests run automatically on:
- **Push** to main, develop, or feature branches
- **Pull requests** to main or develop
- **Manual trigger** via workflow_dispatch

### Workflow Steps

1. **Checkout** - Get latest code
2. **Setup** - Install dependencies (bats, kcov, docker)
3. **Unit Tests** - Run all unit tests
4. **Integration Tests** - Run all integration tests
5. **Coverage** - Generate coverage report
6. **Lint** - Run ShellCheck on all scripts
7. **Security** - Scan for security issues
8. **Report** - Upload artifacts and comment on PR

### Coverage Threshold

Tests **fail** if coverage is below **95%**.

## 📝 Test Maintenance

### Adding New Tests

1. **Create test file** in appropriate directory:
   ```bash
   touch tests/integration/test_new_feature.bats
   ```

2. **Write tests** following the template

3. **Run tests** to verify:
   ```bash
   ./run-tests.sh --verbose
   ```

4. **Check coverage**:
   ```bash
   ./run-tests.sh --coverage
   ```

### Updating Tests

When modifying scripts:
1. Update corresponding tests
2. Run test suite to verify
3. Ensure coverage remains above 95%

### Debugging Failing Tests

```bash
# Verbose output
./run-tests.sh --verbose

# Run specific test file
bats tests/unit/test_tk_logging.bats

# Run with debug output
bats --trace tests/unit/test_tk_logging.bats

# Check test logs
cat /tmp/test-tk.log
```

## 🐛 Common Issues

### bats: command not found

```bash
# Install bats-core
brew install bats-core  # macOS
sudo apt-get install bats  # Ubuntu
```

### Docker not available in tests

```bash
# Ensure Docker is running
docker info

# Tests automatically skip if Docker unavailable
skip_if_no_docker
```

### Coverage below threshold

```bash
# Find uncovered lines
./run-tests.sh --coverage
open tests/coverage/merged/index.html

# Add tests for uncovered code
```

### Tests fail in CI but pass locally

```bash
# Run in Docker to match CI environment
docker run -it --rm -v $(pwd):/workspace ubuntu:latest bash
cd /workspace/scripts
apt-get update && apt-get install -y bats
./run-tests.sh
```

## 📚 Resources

- [Bats Documentation](https://bats-core.readthedocs.io/)
- [kcov Documentation](https://github.com/SimonKagstrom/kcov)
- [ShellCheck](https://www.shellcheck.net/)
- [GitHub Actions](https://docs.github.com/en/actions)

## 🤝 Contributing

When contributing tests:

1. ✅ All tests must pass
2. ✅ Coverage must be ≥95%
3. ✅ ShellCheck must pass (no warnings)
4. ✅ Tests must be fast (<5s per test)
5. ✅ Tests must be independent
6. ✅ Use descriptive test names
7. ✅ Add comments for complex logic

## 📊 Test Statistics

Run this to see test statistics:

```bash
# Count tests
find tests -name "*.bats" -exec grep -c "^@test" {} + | awk '{s+=$1} END {print "Total tests:", s}'

# List all test files
find tests -name "*.bats" -type f

# Check test coverage
./run-tests.sh --coverage | grep "Coverage:"
```

## 🎉 Success Criteria

A successful test suite has:

- ✅ All tests passing
- ✅ ≥95% code coverage
- ✅ No ShellCheck warnings
- ✅ No security vulnerabilities
- ✅ Fast execution (<2 minutes total)
- ✅ Clear, maintainable tests
- ✅ Comprehensive documentation

---

**Questions?** Check the main [scripts README](../README.md) or open an issue.
