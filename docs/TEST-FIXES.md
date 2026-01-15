# Test Suite Fixes for Phase 1 Security Implementation

**Date**: 2026-01-14
**Issue**: GitHub Actions test failures after Phase 1 security implementation
**Status**: ✅ RESOLVED

---

## Problem Summary

After implementing Phase 1 security enhancements, the existing test suite failed because:

1. **Enhanced validation rules** were stricter than old tests expected
2. **Readonly array declaration** caused "unbound variable" errors with `set -u`
3. **Test assumptions** didn't match new security requirements

---

## Issues Fixed

### Issue 1: Invalid Service Names in Tests

**Problem**: Tests used service names that are now invalid:
- `api_v2` - Underscores no longer allowed
- `Service123` - Uppercase no longer allowed

**Root Cause**: Enhanced security validation now enforces:
- Lowercase only
- No underscores (hyphens only)
- Must start with letter
- Max 63 characters (DNS spec)
- Reserved names blocked

**Fix**: Updated test cases in `tests/unit/test_tk_validation.bats`:

```bash
# OLD (failing):
run validate_service_name "api_v2"      # Underscore
run validate_service_name "Service123"  # Uppercase

# NEW (passing):
run validate_service_name "api-v2"      # Hyphen
run validate_service_name "service123"  # Lowercase
```

**Files Modified**:
- `tests/unit/test_tk_validation.bats` (+31 lines of new test cases)

### Issue 2: Unbound Variable Error with Array

**Problem**: Error occurred when test suite loaded validation library:
```
/Users/natejswenson/localrepo/traefik/scripts/lib/tk-validation.sh: line 26: RESERVED_NAMES[@]: unbound variable
```

**Root Cause**:
- Tests use `set -euo pipefail` for strict error checking
- `set -u` treats undefined variables as errors
- Accessing `${RESERVED_NAMES[@]}` in a for loop triggered this check
- Even with array declared as `readonly`, the test environment had issues

**Attempted Fixes** (didn't work):
1. Checking array length before iteration
2. Checking if variable is set with `${RESERVED_NAMES+x}`
3. Temporarily disabling `set -u` around array access

**Final Solution**: Use local array instead of global readonly:

```bash
# OLD (failing with set -u):
readonly RESERVED_NAMES=("traefik" "mongodb" ...)
for reserved in "${RESERVED_NAMES[@]}"; do

# NEW (working):
local reserved_list=("traefik" "mongodb" ...)
for reserved in "${reserved_list[@]}"; do
```

**Why This Works**:
- Local arrays are function-scoped and don't trigger unbound variable checks
- More portable across different bash versions
- Simpler and more maintainable

**Files Modified**:
- `lib/tk-validation.sh` (simplified reserved names check)

### Issue 3: Length Limit Test Mismatch

**Problem**: Test expected max 50 characters, but security enhancement changed it to 63

**Root Cause**: DNS specification allows up to 63 characters per label

**Fix**: Updated test to match new limit:

```bash
# OLD:
@test "validate_service_name rejects names over 50 characters"

# NEW:
@test "validate_service_name rejects names over 63 characters" {
    local valid_63=$(printf 'a%.0s' {1..63})
    run validate_service_name "$valid_63"
    assert_success

    local invalid_64=$(printf 'a%.0s' {1..64})
    run validate_service_name "$invalid_64"
    assert_failure
}
```

---

## New Test Cases Added

Enhanced test coverage for new security validations:

```bash
@test "validate_service_name rejects invalid characters" {
    # Uppercase not allowed
    run validate_service_name "MyService"
    assert_failure

    # Underscores not allowed
    run validate_service_name "api_v2"
    assert_failure

    # Must start with letter
    run validate_service_name "123service"
    assert_failure
}

@test "validate_service_name rejects reserved names" {
    run validate_service_name "traefik"
    assert_failure

    run validate_service_name "mongodb"
    assert_failure

    run validate_service_name "postgres"
    assert_failure

    # ... etc
}
```

---

## Test Results

### Before Fixes:
```
not ok 25 validate_service_name accepts valid names
  RESERVED_NAMES[@]: unbound variable

not ok 28 validate_service_name rejects names over 63 characters
  RESERVED_NAMES[@]: unbound variable

Tests: 44 total, 42 passed, 2 failed
```

### After Fixes:
```
ok 25 validate_service_name accepts valid names
ok 26 validate_service_name rejects empty names
ok 27 validate_service_name rejects invalid characters
ok 28 validate_service_name rejects names over 63 characters
ok 29 validate_service_name rejects reserved names
... (all tests pass)

✓ Integration tests completed
╔════════════════════════════════════════════════════════════╗
║          All Tests Passed ✓                                ║
╚════════════════════════════════════════════════════════════╝

Tests: 44 total, 44 passed, 0 failed
```

---

## Summary of Changes

### Files Modified (2):

**1. `lib/tk-validation.sh`** (-2 lines from readonly, +6 lines for local array)
- Removed global `RESERVED_NAMES` readonly array
- Changed to local array in `validate_service_name()` function
- More compatible with `set -u` in test environments

**2. `tests/unit/test_tk_validation.bats`** (+31 lines)
- Fixed valid service name test cases (lowercase, hyphens)
- Enhanced invalid character tests (uppercase, underscores, starting with number)
- Updated length limit test (50 → 63 characters)
- Added reserved names test

---

## Lessons Learned

### 1. Test-Driven Development
- Run existing tests before making breaking changes
- Update tests alongside code changes
- Consider backward compatibility

### 2. Bash Arrays with `set -u`
- Global readonly arrays can cause issues with `set -u`
- Local function arrays are more reliable
- Simpler is often better

### 3. Security Hardening
- Enhanced validation may break existing assumptions
- Document breaking changes clearly
- Provide migration path for users

---

## Verification Steps

To verify fixes locally:

```bash
# 1. Run full test suite
./run-tests.sh

# 2. Run specific validation tests
bats tests/unit/test_tk_validation.bats

# 3. Test security features
./tests/test-security.sh

# 4. Verify service name validation
source lib/tk-common.sh
validate_service_name "my-service"  # Should succeed
validate_service_name "My_Service"  # Should fail
validate_service_name "traefik"     # Should fail (reserved)
```

---

## Next Steps

1. **Commit Changes**:
   ```bash
   git add lib/tk-validation.sh tests/unit/test_tk_validation.bats
   git commit -m "fix: update tests for enhanced security validation

   - Fix service name validation tests for new rules
   - Change reserved names to use local array (fixes set -u issue)
   - Update length limit test (50 → 63 chars)
   - Add comprehensive tests for security validation

   All tests passing (44/44)"
   ```

2. **Push to GitHub**:
   ```bash
   git push origin develop
   # GitHub Actions should now pass
   ```

3. **Verify CI/CD**:
   - Check GitHub Actions for green checkmarks
   - Security scan should complete successfully
   - All unit and integration tests should pass

---

## Related Documentation

- [Phase 1 Security Implementation](./PHASE1-SECURITY-IMPLEMENTATION.md)
- [Security Enhancements Spec](./specs/security-enhancements.md)
- [Test Suite README](../tests/README.md)

---

**Status**: ✅ All tests passing
**CI/CD**: Ready for GitHub Actions
**Next**: Commit and push changes
