# Test Suite Quick Start

Get the test suite running in under 5 minutes.

## ⚡ Installation

### macOS

```bash
# Install bats-core
brew install bats-core

# Install kcov for coverage (optional but recommended)
brew install kcov
```

### Ubuntu/Debian

```bash
# Update package list
sudo apt-get update

# Install bats
sudo apt-get install -y bats

# Install kcov for coverage (optional but recommended)
sudo apt-get install -y kcov

# Install bc for coverage calculations
sudo apt-get install -y bc
```

### Verify Installation

```bash
bats --version
# Should output: Bats 1.x.x

kcov --version  # Optional
# Should output: kcov vX.X
```

## 🚀 Running Tests

### Basic Commands

```bash
# Navigate to scripts directory
cd scripts

# Run all tests
./run-tests.sh

# Run with verbose output
./run-tests.sh --verbose

# Get help
./run-tests.sh --help
```

### Test Categories

```bash
# Unit tests only (fast, ~10 seconds)
./run-tests.sh --unit

# Integration tests only (slower, ~30 seconds)
./run-tests.sh --integration

# All tests with coverage report
./run-tests.sh --coverage
```

## 📊 Coverage Report

```bash
# Generate coverage
./run-tests.sh --coverage

# Output shows:
# ✓ Coverage report generated
# Coverage: XX.X%
# Report: tests/coverage/merged/index.html

# Open HTML report in browser
open tests/coverage/merged/index.html  # macOS
xdg-open tests/coverage/merged/index.html  # Linux
```

## ✅ Success Criteria

Tests pass when:
- ✅ All tests execute successfully
- ✅ Coverage is ≥95%
- ✅ No errors or failures

## 🐛 Troubleshooting

### "bats: command not found"

```bash
# Install bats first (see Installation section)
brew install bats-core  # macOS
sudo apt-get install bats  # Ubuntu
```

### Tests fail locally

```bash
# Run with verbose output to see details
./run-tests.sh --verbose

# Check Docker is running (for integration tests)
docker info

# Check individual test file
bats tests/unit/test_tk_logging.bats
```

### Coverage below 95%

```bash
# View which lines are not covered
./run-tests.sh --coverage
open tests/coverage/merged/index.html

# Look for red/yellow highlighted lines
# Add tests to cover those lines
```

## 📝 Writing Your First Test

```bash
# Create new test file
touch tests/unit/test_my_feature.bats

# Add test content
cat > tests/unit/test_my_feature.bats <<'EOF'
#!/usr/bin/env bats

load '../test_helper'

@test "my feature works" {
    run echo "hello"
    assert_success
    assert_output_contains "hello"
}
EOF

# Run your test
bats tests/unit/test_my_feature.bats
```

## 🎯 Common Test Patterns

### Testing a Function

```bash
@test "function returns success" {
    source "${SCRIPTS_DIR}/lib/tk-common.sh"

    run my_function "argument"

    assert_success
    assert_output_contains "expected output"
}
```

### Testing with Setup/Teardown

```bash
setup() {
    # Runs before each test
    export TEST_VAR="value"
}

teardown() {
    # Runs after each test
    unset TEST_VAR
}

@test "uses TEST_VAR" {
    [ "$TEST_VAR" = "value" ]
}
```

### Testing File Operations

```bash
@test "creates file" {
    run my_script create-file /tmp/test.txt

    assert_success
    assert_file_exists "/tmp/test.txt"
    assert_file_contains "/tmp/test.txt" "content"

    rm /tmp/test.txt
}
```

## 🚀 Next Steps

1. **Read full documentation**: [README.md](./README.md)
2. **Explore test files**: Check `tests/unit/` and `tests/integration/`
3. **Run tests locally**: `./run-tests.sh --verbose`
4. **View coverage**: `./run-tests.sh --coverage`
5. **Write more tests**: Add to existing test files or create new ones

## 📚 Helpful Commands

```bash
# Count total tests
find tests -name "*.bats" -exec grep -c "^@test" {} + | awk '{s+=$1} END {print "Total:", s}'

# List all test files
find tests -name "*.bats"

# Run specific test file
bats tests/unit/test_tk_logging.bats

# Run specific test by name
bats -f "log_info" tests/unit/test_tk_logging.bats

# Debug mode (shows commands)
bats --trace tests/unit/test_tk_logging.bats
```

## ✨ Tips

1. **Start with unit tests** - They're faster and easier to debug
2. **Use --verbose** - See detailed output when tests fail
3. **Test one thing** - Each test should verify one specific behavior
4. **Keep tests fast** - Mock external dependencies
5. **Run often** - Run tests after every change

---

**Ready to run tests?**

```bash
cd scripts
./run-tests.sh
```

🎉 **You're all set!**
