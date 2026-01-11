# Testing Implementation Notes

## Test Isolation

### Problem
The `tk` command normally operates on the project containing the scripts directory:
```bash
# tk always goes to parent of scripts/
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"
```

This causes issues in tests because:
1. Tests create isolated docker-compose.yml in `/tmp/tk-test-$$`
2. But tk command would find the real project's docker-compose.yml
3. Tests would run against your actual project instead of test fixtures

### Solution: TK_TEST_MODE

We added `TK_TEST_MODE` environment variable:

```bash
# In tk command
if [ "${TK_TEST_MODE:-}" = "true" ]; then
    PROJECT_ROOT="$PWD"  # Use current directory
else
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"  # Use parent
fi
```

When `TK_TEST_MODE=true`:
- tk uses current working directory as PROJECT_ROOT
- tk does NOT `cd` to parent directory
- Tests can control which docker-compose.yml is used

### Test Environment Setup

```bash
# test_helper.bash sets these automatically
export TEST_PROJECT_DIR="/tmp/tk-test-$$"      # Isolated directory
export TEST_COMPOSE_FILE="${TEST_PROJECT_DIR}/docker-compose.yml"
export TK_TEST_MODE="true"                      # Enable test mode
```

### Integration Test Pattern

```bash
setup() {
    setup_test_project   # Creates isolated env in /tmp
    cd "$TEST_PROJECT_DIR"  # Enter test environment
}

@test "tk list works" {
    # TK_TEST_MODE=true means tk uses $PWD (TEST_PROJECT_DIR)
    # Not the real project directory
    run "${SCRIPTS_DIR}/tk" list
    assert_success
}

teardown() {
    cleanup_test_project  # Removes /tmp/tk-test-$$
}
```

## Local vs CI Testing

### Local Testing
- Real project exists at `/Users/you/project/`
- Tests run at `/Users/you/project/scripts/tests/`
- Without isolation, tk would find real docker-compose.yml
- With `TK_TEST_MODE`, tk uses `/tmp/tk-test-$$/`

### CI Testing (GitHub Actions)
- Project checked out to `/home/runner/work/repo/repo/`
- No parent docker-compose.yml issues (clean environment)
- `TK_TEST_MODE` ensures consistent behavior
- Tests run in `/tmp/tk-test-<pid>/` (isolated)

### Why /tmp?

Originally used `tests/test_project/` but this caused issues:
```
scripts/
  tests/
    test_project/          # Still inside project!
      docker-compose.yml   # tk would find parent instead
```

Using `/tmp/tk-test-$$`:
```
/tmp/
  tk-test-12345/           # Completely outside project
    docker-compose.yml     # tk finds this when TK_TEST_MODE=true
```

## Common Issues

### Tests use local environment

**Symptom:**
```
Expected: test-service
Actual:   python-api, node-web, mongodb
```

**Cause:** `TK_TEST_MODE` not set or tk not respecting it

**Fix:**
```bash
export TK_TEST_MODE="true"
./run-tests.sh --integration
```

### Tests fail in CI but pass locally

**Symptom:** Tests pass on your machine, fail in GitHub Actions

**Possible causes:**
1. Docker not available in CI
2. Permission issues with /tmp
3. Missing dependencies (bats, kcov)

**Fix:** Check GHA workflow has all dependencies

### Cleanup doesn't work

**Symptom:** `/tmp/tk-test-*` directories left behind

**Cause:** Tests exited before teardown

**Fix:**
```bash
# Manual cleanup
rm -rf /tmp/tk-test-*

# Automated cleanup in teardown_suite.bash
```

## Environment Variables

### TK_TEST_MODE
- **Purpose:** Enable test mode for tk command
- **Value:** `"true"` or unset
- **Set by:** test_helper.bash automatically
- **Used by:** tk command to determine PROJECT_ROOT

### TEST_PROJECT_DIR
- **Purpose:** Isolated test environment location
- **Value:** `/tmp/tk-test-$$` (unique per process)
- **Set by:** test_helper.bash
- **Used by:** All integration tests

### TEST_COMPOSE_FILE
- **Purpose:** Path to test docker-compose.yml
- **Value:** `${TEST_PROJECT_DIR}/docker-compose.yml`
- **Set by:** test_helper.bash
- **Used by:** Integration tests

## Best Practices

1. **Always use setup/teardown**
   ```bash
   setup() {
       setup_test_project
       cd "$TEST_PROJECT_DIR"
   }

   teardown() {
       cleanup_test_project
   }
   ```

2. **Don't modify real project**
   - Tests should never touch files outside /tmp
   - Use TEST_PROJECT_DIR for all file operations

3. **Check TK_TEST_MODE is set**
   ```bash
   # In test file
   @test "verify test mode" {
       [ "$TK_TEST_MODE" = "true" ]
   }
   ```

4. **Use unique names**
   - `/tmp/tk-test-$$` uses process ID
   - Prevents conflicts between parallel test runs

## Debugging

### Check test isolation

```bash
# Run single test with debug
bats --trace tests/integration/test_tk_list.bats

# Check which compose file is used
TK_TEST_MODE=true ./tk list
```

### Verify test environment

```bash
# In test
@test "debug test environment" {
    echo "PWD: $PWD" >&3
    echo "TEST_PROJECT_DIR: $TEST_PROJECT_DIR" >&3
    echo "TK_TEST_MODE: $TK_TEST_MODE" >&3
    ls -la "$TEST_PROJECT_DIR" >&3
}
```

### Manual test run

```bash
# Setup environment like tests do
export TK_TEST_MODE="true"
export TEST_PROJECT_DIR="/tmp/tk-test-$$"
mkdir -p "$TEST_PROJECT_DIR"

# Create test compose file
cat > "$TEST_PROJECT_DIR/docker-compose.yml" <<EOF
services:
  test: {}
EOF

# Run command
cd "$TEST_PROJECT_DIR"
../path/to/tk list

# Cleanup
rm -rf "$TEST_PROJECT_DIR"
```

## Future Improvements

1. **Mock Docker completely**
   - Avoid needing real Docker for unit tests
   - Faster test execution

2. **Parallel test execution**
   - bats supports `--jobs` flag
   - Requires better isolation

3. **Test fixtures**
   - Pre-built compose files for common scenarios
   - Reduce test setup time

4. **Coverage by function**
   - Per-function coverage reports
   - Identify untested functions easily
