# Claude Code Instructions

**Project**: Traefik Scripts - Automation CLI and Library
**Working Directory**: `/scripts/` (git-tracked repository)
**Branch Workflow**: `develop` → `main` (use `./merge-to-main.sh` to merge)

---

## Primary Reference

**READ FIRST**: [agents.md](./agents.md) - Comprehensive guide for AI agents working with this codebase.

The `agents.md` file contains:
- Project architecture and component overview
- Development workflows and patterns
- Library module system documentation
- Code examples and best practices
- Troubleshooting guides and decision trees

**Always consult agents.md before making changes.**

---

## Critical Requirements

### 1. Testing is Mandatory ✅

**Before completing ANY task that modifies code:**

```bash
# Run the test suite
./run-tests.sh

# All tests MUST pass before task completion
# Exit code must be 0
```

**If tests fail:**
- Fix the code to make tests pass, OR
- Update tests if they're incorrect, OR
- Add new tests for new functionality

**Never mark a task as complete with failing tests.**

### 2. Documentation is Mandatory 📝

**When making changes, update documentation:**

| Change Type | Documentation Required |
|-------------|----------------------|
| New CLI command | Update README.md, QUICKSTART.md, agents.md |
| New script file | Update README.md, add usage in QUICKSTART.md |
| New library function | Update lib/README.md, agents.md |
| New framework support | Update README.md "Supported" section, agents.md |
| Bug fix | Update agents.md troubleshooting section if notable |
| Configuration option | Update README.md, .tkrc.example |

**Specifically for agents.md:**
- Add new patterns to "Code Patterns & Examples"
- Add new workflows to "Development Workflows"
- Update decision trees if logic changes
- Add troubleshooting entries for new issues discovered

### 3. Code Standards 🔧

**Always follow these patterns:**

```bash
# Strict mode (every script)
set -euo pipefail

# Load libraries
source "$(dirname "$0")/lib/tk-common.sh"

# Quote all variables
echo "$variable"  # ✅ Correct
echo $variable    # ❌ Wrong

# Validate inputs
validate_service_name "$name" || exit 1
validate_docker || exit 1

# Use library functions
log_info "Message"      # ✅ Use library
echo "Message"          # ❌ Don't use raw echo

# Support dry-run
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY RUN] Would execute: command"
else
  command
fi
```

---

## Workflow Summary

### Standard Development Process

```bash
# 1. Make changes to scripts or library
vim script.sh

# 2. Test changes
./run-tests.sh

# 3. Verify in verbose mode (if needed)
VERBOSE=true ./script.sh --dry-run

# 4. Update documentation
# - Update agents.md with new patterns/workflows
# - Update README.md with new commands
# - Update QUICKSTART.md with examples

# 5. Check git status
git status

# 6. Commit (Claude should not auto-commit without user request)
git add script.sh tests/test-script.sh agents.md README.md
git commit -m "feat: add new feature with tests and docs"

# 7. Merge to main (when ready)
./merge-to-main.sh
```

### Git Branch Strategy

- **develop** - Active development (work here)
- **main** - Production-ready code
- **Feature branches** - Major changes (if needed)

**Always work on develop branch first.**

---

## Task Completion Checklist

Before reporting a task as complete, verify:

- [ ] **Code changes work** - Tested manually if applicable
- [ ] **Tests pass** - `./run-tests.sh` exits with 0
- [ ] **Tests added** - New functionality has test coverage
- [ ] **Documentation updated**:
  - [ ] agents.md (if adding patterns, workflows, or troubleshooting)
  - [ ] README.md (if adding commands or changing API)
  - [ ] QUICKSTART.md (if adding user-facing features)
  - [ ] lib/README.md (if modifying library functions)
- [ ] **Help text added** - `--help` flag works for new commands
- [ ] **Dry-run supported** - `--dry-run` flag works (if applicable)
- [ ] **Error handling** - Validates inputs, handles errors gracefully
- [ ] **Security checked** - No command injection, path traversal, etc.
- [ ] **Follows patterns** - Consistent with existing code style

---

## Quick Reference

### Common Commands
```bash
./tk --help              # Show CLI help
./run-tests.sh           # Run test suite
./install.sh             # Install tk CLI
./merge-to-main.sh       # Merge develop to main
```

### Important Files
```bash
agents.md                # This is your primary guide
README.md                # User-facing documentation
QUICKSTART.md            # Quick start examples
tk                       # Main CLI executable
lib/tk-common.sh         # Library loader
lib/tk-logging.sh        # Logging functions
lib/tk-validation.sh     # Input validation
```

### When Adding Features
1. Read agents.md section on the feature type
2. Follow the decision tree for that feature
3. Use code patterns from agents.md
4. Write tests
5. Run test suite
6. Update all relevant documentation

### When Fixing Bugs
1. Reproduce the issue
2. Add test case that fails
3. Fix the bug
4. Verify test now passes
5. Run full test suite
6. Update agents.md troubleshooting section

---

## Examples

### Example 1: Adding New CLI Command

```bash
# 1. Add command to ./tk
case "$command" in
  mycommand)
    exec ./my-command.sh "$@"
    ;;
esac

# 2. Create script (if complex)
# Follow pattern in agents.md "Pattern 1: Complete Script Example"

# 3. Add tests
# tests/test-mycommand.sh

# 4. Run tests
./run-tests.sh

# 5. Update docs
# - README.md: Add to command list
# - QUICKSTART.md: Add usage example
# - agents.md: Add to "Core Components" and "Code Patterns"
```

### Example 2: Adding Library Function

```bash
# 1. Add function to appropriate lib/tk-*.sh file
my_new_function() {
  local arg=$1
  validate_input "$arg" || return 1
  # Implementation
}

# 2. Export function
export -f my_new_function

# 3. Add test
# tests/test-validation.sh or similar

# 4. Run tests
./run-tests.sh

# 5. Update docs
# - lib/README.md: Document the function
# - agents.md: Add to "Library Module System" section
```

### Example 3: Adding Framework Support

```bash
# 1. Update lib/service-detector.sh
detect_ruby_framework() { ... }

# 2. Update lib/docker-generator.sh
generate_ruby_dockerfile() { ... }

# 3. Update connect-service.sh
case "$language" in
  ruby) ... ;;
esac

# 4. Test with real Ruby project
./tk connect ~/ruby-project --dry-run
./tk connect ~/ruby-project

# 5. Run tests
./run-tests.sh

# 6. Update docs
# - README.md: Add Ruby to "Supported" section
# - QUICKSTART.md: Add Ruby example
# - agents.md: Update "Workflow 3: Adding Support for New Framework"
```

---

## Anti-Patterns (DON'T DO THIS)

❌ **Don't skip tests** - "I'll add tests later" → NO, add tests NOW
❌ **Don't skip documentation** - Code without docs is incomplete
❌ **Don't commit to main** - Always use develop branch first
❌ **Don't ignore failing tests** - Fix them before continuing
❌ **Don't use `eval`** - Security risk with user input
❌ **Don't hardcode paths** - Use `find_project_root()` or relative paths
❌ **Don't skip validation** - Always validate user input
❌ **Don't break backward compatibility** - Maintain existing CLI interface
❌ **Don't assume Docker is running** - Always `validate_docker()`
❌ **Don't use unquoted variables** - Always `"$variable"`

---

## Final Note

**The agents.md file is your primary resource.** When in doubt:

1. Check agents.md for patterns and examples
2. Look at existing code for similar functionality
3. Ask clarifying questions if requirements are unclear
4. Always test and document your changes

**Quality over speed.** It's better to take time to do it right than to rush and break things.

---

**Remember**: Every task must end with ✅ passing tests and 📝 updated documentation.
