# Traefik Scripts - AI Agent Guide

> **Purpose**: Comprehensive guide for AI coding agents (Claude, Copilot, Cursor, etc.) working with the Traefik automation scripts and CLI toolkit.

**Last Updated**: 2026-01-14
**Project**: Traefik Scripts
**Git Branch**: develop → main workflow
**Location**: `/scripts/` (this folder is git-tracked)

---

## Table of Contents

1. [Quick Start for Agents](#quick-start-for-agents)
2. [Project Architecture](#project-architecture)
3. [Core Components](#core-components)
4. [Development Workflows](#development-workflows)
5. [Script Modification Patterns](#script-modification-patterns)
6. [Library Module System](#library-module-system)
7. [Testing & Validation](#testing--validation)
8. [Troubleshooting Patterns](#troubleshooting-patterns)
9. [Agent Decision Trees](#agent-decision-trees)
10. [Code Patterns & Examples](#code-patterns--examples)
11. [Best Practices](#best-practices)

---

## Quick Start for Agents

### 🎯 First Steps When Entering This Codebase

**Working Directory**: `/Users/natejswenson/localrepo/traefik/scripts/`
**Git Repo**: This folder (scripts/) has its own .git - it's a separate repository
**Workflow**: develop → main (use `./merge-to-main.sh` to merge)

```bash
# 1. Verify location and git status
pwd  # Should be in /traefik/scripts/
git status
git branch  # Usually on 'develop'

# 2. Understand the structure
ls -la
cat README.md  # Overview of all scripts
cat QUICKSTART.md  # Usage examples

# 3. Check the tk CLI
./tk --help
./tk status
```

### 📋 Critical Files to Read First

**Priority Order:**
1. **README.md** - Complete script reference and architecture overview
2. **QUICKSTART.md** - Common usage patterns and examples
3. **tk** - Main CLI executable (bash script)
4. **lib/tk-common.sh** - Library loader and core functions
5. **connect-service.sh** - Most complex script (service auto-detection)
6. **lib/README.md** - Library module documentation

### ⚡ Quick Reference Commands

| Task | Command |
|------|---------|
| Install CLI | `./install.sh` |
| Uninstall CLI | `./uninstall.sh` |
| Connect service | `./connect-service.sh /path/to/service` |
| Add new service | `./add-service.sh service-name 8080 python` |
| Run tests | `./run-tests.sh` |
| Clean resources | `./cleanup.sh` |
| View CLI help | `./tk --help` |
| Check git status | `git status` |
| Merge to main | `./merge-to-main.sh` |

---

## Project Architecture

### 🏗️ High-Level System Design

```
┌──────────────────────────────────────────────────────────┐
│                     User/Developer                        │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
            ┌─────────────────┐
            │   tk CLI        │ ← Main entry point
            │   (bash)        │ ← Command router
            └────────┬────────┘
                     │
         ┌───────────┼────────────┐
         │           │            │
         ▼           ▼            ▼
    ┌────────┐  ┌─────────┐  ┌──────────┐
    │connect │  │  add    │  │ status   │
    │-service│  │-service │  │ logs     │
    │  .sh   │  │  .sh    │  │ etc.     │
    └───┬────┘  └────┬────┘  └────┬─────┘
        │            │            │
        └────────────┼────────────┘
                     │
                     ▼
            ┌─────────────────┐
            │  lib/*.sh       │ ← Shared libraries
            │  - tk-common    │ ← Configuration & utils
            │  - tk-logging   │ ← Output formatting
            │  - tk-validation│ ← Input validation
            │  - tk-docker    │ ← Docker operations
            │  - service-     │ ← Service detection
            │    detector     │
            │  - docker-      │ ← Dockerfile generation
            │    generator    │
            └────────┬────────┘
                     │
                     ▼
        ┌─────────────────────────┐
        │ Docker & Traefik        │
        │ (parent directory)      │
        │ - docker-compose.yml    │
        │ - traefik/              │
        │ - services/             │
        └─────────────────────────┘
```

### 📁 Directory Structure Deep Dive

```
scripts/                              # This folder (git root)
│
├── .git/                            # Git repository (separate from parent)
├── .github/                         # GitHub Actions workflows
│   ├── workflows/
│   │   ├── merge-to-main.yml       # Auto-merge develop → main
│   │   └── test.yml                # CI tests
│   └── WORKFLOW.md                 # Workflow documentation
│
├── agents.md                        # THIS FILE - AI agent guide
├── README.md                        # User-facing documentation
├── QUICKSTART.md                    # Quick start guide
├── TEST_SUITE_SUMMARY.md           # Test suite overview
│
├── tk                               # Main CLI executable (bash)
├── install.sh                       # Install tk to PATH
├── uninstall.sh                     # Remove tk from PATH
│
├── connect-service.sh               # Auto-connect external services ⭐
├── add-service.sh                   # Add new service from scratch
├── cleanup.sh                       # Clean Docker resources
├── setup-dns.sh                     # Configure DNS for *.localhost
├── run-tests.sh                     # Execute test suite
├── merge-to-main.sh                 # Create PR and merge to main
│
├── lib/                             # Shared library modules
│   ├── README.md                    # Library documentation
│   ├── tk-common.sh                 # Main loader & utilities
│   ├── tk-logging.sh                # Logging & formatting
│   ├── tk-validation.sh             # Input validation & security
│   ├── tk-docker.sh                 # Docker operations
│   ├── service-detector.sh          # Language/framework detection
│   └── docker-generator.sh          # Dockerfile & compose generation
│
└── tests/                           # Test suite
    ├── test-*.sh                    # Individual test files
    └── fixtures/                    # Test data
```

### 🔄 Git Workflow

**Branch Strategy:**
- `develop` - Active development branch
- `main` - Production-ready code
- Feature branches - For major changes

**Merge Process:**
```bash
# After changes pass tests on develop:
./merge-to-main.sh

# This script:
# 1. Ensures you're on develop branch
# 2. Runs tests
# 3. Pushes develop to remote
# 4. Creates PR from develop to main
# 5. Waits for CI checks
# 6. Auto-merges if all checks pass
```

**Important**: All changes go through develop first, then merge to main via PR.

---

## Core Components

### 🎯 Component 1: tk CLI

**Location**: `./tk`
**Type**: Bash script (main executable)
**Purpose**: Unified command-line interface for all Traefik operations

**Architecture:**
```bash
#!/usr/bin/env bash

# 1. Load libraries
source lib/tk-common.sh

# 2. Parse arguments
command=$1
shift

# 3. Route to appropriate function/script
case "$command" in
  connect) exec ./connect-service.sh "$@" ;;
  add)     exec ./add-service.sh "$@" ;;
  status)  # Implementation ;;
  logs)    # Implementation ;;
  # ...
esac
```

**Available Commands:**
- `tk connect <path> [name]` - Connect external service
- `tk add <name> [port] [language]` - Add new service
- `tk status` - Show all service status
- `tk logs [service]` - View service logs
- `tk restart [service]` - Restart service(s)
- `tk stop [service]` - Stop service(s)
- `tk start [service]` - Start service(s)
- `tk clean` - Clean up Docker resources
- `tk help [command]` - Show help

**Flags:**
- `--dry-run` - Preview changes without executing
- `--verbose` - Enable detailed output
- `--help` - Show help

### 🎯 Component 2: connect-service.sh

**Location**: `./connect-service.sh`
**Type**: Bash script (most complex in project)
**Purpose**: Auto-detect and connect external services to Traefik

**Workflow:**
```
Input: /path/to/service [name]
│
├─ 1. Validate path exists
├─ 2. Detect language (Python/Node.js)
├─ 3. Detect framework (FastAPI/Flask/Express/etc.)
├─ 4. Find entry point (main.py, index.js, etc.)
├─ 5. Detect port (from code analysis)
├─ 6. Detect dependencies (MongoDB, Redis, etc.)
├─ 7. Generate or verify Dockerfile
├─ 8. Generate docker-compose.yml service block
├─ 9. Configure Traefik labels
├─ 10. Add to parent docker-compose.yml
├─ 11. Start service
└─ Output: Service running at https://name.localhost
```

**Key Functions (uses library modules):**
- `detect_service_type()` - Language detection
- `detect_framework()` - Framework detection
- `find_entry_point()` - Entry file detection
- `detect_port()` - Port detection from code
- `generate_dockerfile()` - Dockerfile creation
- `generate_docker_compose_block()` - Compose YAML generation

**Supported:**
- ✅ Python: FastAPI, Flask, Django
- ✅ Node.js: Express, NestJS, Next.js, Koa
- ✅ Auto-detects: MongoDB, PostgreSQL, Redis dependencies
- ✅ Generates Dockerfile if not present
- ✅ Full Traefik HTTPS routing

### 🎯 Component 3: Library Modules

**Location**: `./lib/*.sh`
**Type**: Bash libraries (sourced by scripts)
**Purpose**: Shared functionality across all scripts

#### lib/tk-common.sh
**Purpose**: Main library loader and common utilities

**Exports:**
```bash
# Configuration
load_config()           # Load .tkrc files
get_config()            # Get config value
set_config()            # Set config value

# Error handling
set -euo pipefail       # Strict mode
trap cleanup EXIT       # Cleanup on exit

# Common utilities
find_project_root()     # Locate parent traefik directory
realpath()              # Get absolute path
```

#### lib/tk-logging.sh
**Purpose**: Logging and output formatting

**Functions:**
```bash
log()                   # Generic log
log_debug()            # Debug level (if VERBOSE=true)
log_info()             # Info level
log_warn()             # Warning level
log_error()            # Error level
log_fatal()            # Fatal error (exits)

print_header()         # Print section header
print_success()        # Success message (green)
print_error()          # Error message (red)
print_status()         # Status message (blue)
spinner()              # Progress spinner
```

**Usage:**
```bash
log_info "Connecting service..."
print_success "Service connected!"
log_error "Failed to start service"
spinner "Building Docker image" "docker build ..."
```

#### lib/tk-validation.sh
**Purpose**: Input validation and security

**Functions:**
```bash
validate_service_name()    # Check service name format
validate_domain()          # Check domain format
validate_port()            # Check port number (1-65535)
validate_docker()          # Check Docker is running
validate_docker_compose()  # Check docker compose available
sanitize_env_value()       # Remove dangerous characters
validate_env_name()        # Check env var name format
validate_path()            # Check path exists and is safe
```

**Security Features:**
- Path traversal attack prevention
- Command injection prevention
- Environment variable sanitization
- Service name validation (no special chars)

#### lib/tk-docker.sh
**Purpose**: Docker and Docker Compose operations

**Functions:**
```bash
docker_compose_cmd()       # Wrapper for docker compose
service_exists()           # Check if service exists
get_service_domain()       # Get service URL
list_services()            # List all services
find_project_root()        # Find docker-compose.yml location
get_service_port()         # Get service internal port
get_service_status()       # Get service health status
```

#### lib/service-detector.sh
**Purpose**: Service language and framework detection

**Detection Logic:**
```bash
# Python detection
- Look for requirements.txt, pyproject.toml, setup.py
- Scan for: fastapi, flask, django imports
- Find entry point: main.py, app.py, wsgi.py
- Detect port from: uvicorn.run(), app.run()

# Node.js detection
- Look for package.json
- Check dependencies: express, nestjs, next, koa
- Find entry point: from "main" in package.json
- Detect port from: app.listen(), process.env.PORT
```

**Functions:**
```bash
detect_language()          # Python, Node.js, or unknown
detect_python_framework()  # FastAPI, Flask, Django, etc.
detect_node_framework()    # Express, NestJS, Next.js, etc.
find_python_entry()        # Find main.py, app.py, etc.
find_node_entry()          # Find index.js from package.json
detect_python_port()       # Parse port from code
detect_node_port()         # Parse port from code/env
detect_dependencies()      # MongoDB, Redis, PostgreSQL
```

#### lib/docker-generator.sh
**Purpose**: Generate Dockerfiles and docker-compose configurations

**Capabilities:**
```bash
generate_python_dockerfile()     # Python Dockerfile template
generate_node_dockerfile()       # Node.js Dockerfile template
generate_compose_block()         # docker-compose.yml service
generate_traefik_labels()        # Traefik routing labels
generate_health_check()          # Health check configuration
```

**Templates Include:**
- Multi-stage builds for optimization
- Non-root user execution
- Volume mounting for hot reload
- Environment variable configuration
- Health check endpoints
- Traefik label configuration

---

## Development Workflows

### 🛠️ Workflow 1: Adding a New Script Command

**When**: User asks to add new functionality to the tk CLI

**Steps:**

1. **Decide on command name**
   ```bash
   # Example: Adding "tk backup" command
   COMMAND_NAME="backup"
   ```

2. **Create standalone script (optional)**
   ```bash
   # If complex logic, create separate script
   touch backup-service.sh
   chmod +x backup-service.sh
   ```

3. **Add to tk CLI**
   ```bash
   # Edit: ./tk
   case "$command" in
     # ... existing commands ...
     backup)
       exec ./backup-service.sh "$@"
       ;;
   esac
   ```

4. **Add help text**
   ```bash
   # In show_help() function
   echo "  backup [service]    - Backup service data"
   ```

5. **Test**
   ```bash
   ./tk backup --help
   ./tk backup my-service
   ```

6. **Update documentation**
   - Add to README.md under "Available Commands"
   - Add example to QUICKSTART.md
   - Update this agents.md file

### 🛠️ Workflow 2: Modifying Library Functions

**When**: Need to fix bugs or enhance library functionality

**Steps:**

1. **Identify the library module**
   ```bash
   # Example: Fixing port validation
   FILE="lib/tk-validation.sh"
   ```

2. **Read the current implementation**
   ```bash
   cat lib/tk-validation.sh
   # Find the function: validate_port()
   ```

3. **Make changes**
   ```bash
   # Edit the function
   validate_port() {
     local port=$1
     if [[ ! "$port" =~ ^[0-9]+$ ]]; then
       log_error "Port must be numeric"
       return 1
     fi
     if [[ $port -lt 1 || $port -gt 65535 ]]; then
       log_error "Port must be between 1-65535"
       return 1
     fi
     return 0
   }
   ```

4. **Test the change**
   ```bash
   # Source the library
   source lib/tk-common.sh

   # Test the function
   validate_port 8080  # Should succeed
   validate_port 99999 # Should fail
   ```

5. **Run test suite**
   ```bash
   ./run-tests.sh
   ```

6. **Update tests if needed**
   ```bash
   # Add test case to tests/test-validation.sh
   ```

### 🛠️ Workflow 3: Adding Support for New Framework

**When**: User wants to support a new language/framework

**Example**: Adding support for Ruby on Rails

**Steps:**

1. **Update service-detector.sh**
   ```bash
   # Add Ruby detection
   detect_language() {
     # ... existing Python/Node detection ...

     # Add Ruby detection
     if [[ -f "Gemfile" ]] || [[ -f "config.ru" ]]; then
       echo "ruby"
       return 0
     fi
   }

   detect_ruby_framework() {
     if grep -q "rails" Gemfile 2>/dev/null; then
       echo "rails"
     elif grep -q "sinatra" Gemfile 2>/dev/null; then
       echo "sinatra"
     else
       echo "ruby"
     fi
   }

   detect_ruby_port() {
     # Default Rails port
     echo "3000"
   }
   ```

2. **Add Dockerfile template in docker-generator.sh**
   ```bash
   generate_ruby_dockerfile() {
     local service_name=$1
     cat > Dockerfile <<'EOF'
   FROM ruby:3.2-slim
   WORKDIR /app
   COPY Gemfile Gemfile.lock ./
   RUN bundle install
   COPY . .
   EXPOSE 3000
   CMD ["rails", "server", "-b", "0.0.0.0"]
   EOF
   }
   ```

3. **Update connect-service.sh**
   ```bash
   # Add Ruby case to language detection
   case "$language" in
     python) ... ;;
     node)   ... ;;
     ruby)
       framework=$(detect_ruby_framework)
       port=$(detect_ruby_port)
       generate_ruby_dockerfile "$service_name"
       ;;
   esac
   ```

4. **Test with real Ruby project**
   ```bash
   ./tk connect ~/projects/ruby-rails-app --dry-run
   ./tk connect ~/projects/ruby-rails-app
   ```

5. **Update documentation**
   - Add Ruby to README.md "Supported" section
   - Add Ruby example to QUICKSTART.md
   - Update this agents.md

### 🛠️ Workflow 4: Fixing a Bug

**Steps:**

1. **Reproduce the bug**
   ```bash
   # Example: Bug report says "tk connect fails with spaces in path"
   ./tk connect "/path/with spaces/service" --dry-run
   # Error: No such file or directory
   ```

2. **Identify the source**
   ```bash
   # Add debugging
   set -x  # Enable bash tracing
   ./tk connect "/path/with spaces/service" --dry-run
   ```

3. **Locate the bug**
   ```bash
   # Found: In connect-service.sh, path not quoted
   # Line 45: cd $service_path  # BUG: Should be quoted
   ```

4. **Fix the bug**
   ```bash
   # Change to: cd "$service_path"
   # Add quotes around all variable references
   ```

5. **Test the fix**
   ```bash
   ./tk connect "/path/with spaces/service" --dry-run
   # Success!
   ```

6. **Add regression test**
   ```bash
   # In tests/test-connect.sh
   test_path_with_spaces() {
     local test_path="/tmp/test service"
     mkdir -p "$test_path"
     ./connect-service.sh "$test_path" --dry-run
     assert_success
   }
   ```

7. **Run full test suite**
   ```bash
   ./run-tests.sh
   ```

8. **Commit with clear message**
   ```bash
   git add connect-service.sh tests/test-connect.sh
   git commit -m "fix: handle paths with spaces in connect-service.sh"
   ```

---

## Script Modification Patterns

### 🔧 Pattern 1: Script Structure Template

**Every standalone script should follow this structure:**

```bash
#!/usr/bin/env bash
#
# script-name.sh - Brief description
#
# Usage: ./script-name.sh [options] <arguments>
#

# ============================================================================
# Configuration
# ============================================================================

# Strict mode
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common library
source "$SCRIPT_DIR/lib/tk-common.sh"

# Default values
DEFAULT_VALUE="something"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# ============================================================================
# Functions
# ============================================================================

show_help() {
  cat <<EOF
Usage: $(basename "$0") [options] <arguments>

Description of what this script does.

Options:
  -h, --help        Show this help message
  -d, --dry-run     Preview changes without executing
  -v, --verbose     Enable verbose output

Arguments:
  arg1              Description of argument 1
  arg2              Description of argument 2 (optional)

Examples:
  $(basename "$0") value1
  $(basename "$0") value1 value2 --dry-run

EOF
}

main() {
  local arg1=${1:-}
  local arg2=${2:-}

  # Validate inputs
  if [[ -z "$arg1" ]]; then
    log_error "Missing required argument: arg1"
    show_help
    exit 1
  fi

  # Main logic
  log_info "Starting operation..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
  fi

  # ... implementation ...

  print_success "Operation completed successfully"
}

# ============================================================================
# Argument Parsing
# ============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -*)
      log_error "Unknown option: $1"
      show_help
      exit 1
      ;;
    *)
      # Positional arguments
      break
      ;;
  esac
done

# ============================================================================
# Main Execution
# ============================================================================

main "$@"
```

### 🔧 Pattern 2: Using Library Functions

**Common patterns when using library functions:**

```bash
#!/usr/bin/env bash

# Load library
source "$(dirname "$0")/lib/tk-common.sh"

# Logging
log_info "Starting process..."
log_debug "Debug info: $variable"  # Only shown if VERBOSE=true
log_warn "Warning: This is risky"
log_error "Error occurred"
log_fatal "Critical error - exiting"  # Exits with code 1

# Validation
validate_service_name "$name" || exit 1
validate_port "$port" || exit 1
validate_docker || exit 1

# Docker operations
if service_exists "$service_name"; then
  log_warn "Service already exists"
fi

domain=$(get_service_domain "$service_name")
log_info "Service will be available at: https://$domain"

# Configuration
project_root=$(find_project_root)
cd "$project_root" || exit 1

# Status output
print_header "Service Configuration"
print_status "Name: $service_name"
print_status "Port: $port"
print_status "Domain: $domain"
print_success "Configuration complete!"

# Spinner for long operations
spinner "Building Docker image" "docker build -t $service_name ."
```

### 🔧 Pattern 3: Error Handling

**Best practices for error handling:**

```bash
#!/usr/bin/env bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Trap errors
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_error "Script failed with exit code: $exit_code"
    # Cleanup temporary files
    rm -f /tmp/tempfile.$$
  fi
}
trap cleanup EXIT

# Validate before proceeding
validate_inputs() {
  if [[ ! -d "$service_path" ]]; then
    log_fatal "Service path does not exist: $service_path"
  fi

  if ! validate_service_name "$service_name"; then
    log_fatal "Invalid service name: $service_name"
  fi

  if ! validate_docker; then
    log_fatal "Docker is not running"
  fi
}

# Check command success
if ! docker build -t "$image_name" .; then
  log_fatal "Docker build failed"
fi

# Conditional execution
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "Would execute: docker compose up -d $service_name"
else
  docker compose up -d "$service_name" || log_fatal "Failed to start service"
fi
```

### 🔧 Pattern 4: Dry Run Mode

**Implementing dry run in scripts:**

```bash
#!/usr/bin/env bash

DRY_RUN="${DRY_RUN:-false}"

execute() {
  local description=$1
  shift
  local command=("$@")

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: ${command[*]}"
  else
    log_debug "Executing: ${command[*]}"
    "${command[@]}" || return 1
  fi
}

# Usage
execute "Build Docker image" docker build -t myimage .
execute "Start service" docker compose up -d myservice

# File modifications
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY RUN] Would add service to docker-compose.yml"
  cat <<EOF
---
Service block that would be added:
$(generate_service_block)
---
EOF
else
  echo "$(generate_service_block)" >> "$PROJECT_ROOT/docker-compose.yml"
fi
```

---

## Library Module System

### 📚 Module Loading Order

```bash
# 1. tk-common.sh is loaded first (entry point)
source lib/tk-common.sh

# 2. tk-common.sh loads other modules in this order:
source lib/tk-logging.sh      # Required first (logging functions)
source lib/tk-validation.sh   # Validation functions
source lib/tk-docker.sh       # Docker operations

# 3. Specialized modules loaded when needed:
source lib/service-detector.sh   # Only in connect-service.sh
source lib/docker-generator.sh   # Only in connect-service.sh
```

### 📚 Creating New Library Module

**When**: Need to add shared functionality used by multiple scripts

**Steps:**

1. **Create module file**
   ```bash
   touch lib/tk-mynewmodule.sh
   chmod +x lib/tk-mynewmodule.sh
   ```

2. **Structure the module**
   ```bash
   #!/usr/bin/env bash
   #
   # tk-mynewmodule.sh - Description of module
   #

   # Prevent double-loading
   [[ -n "${TK_MYNEWMODULE_LOADED:-}" ]] && return 0
   TK_MYNEWMODULE_LOADED=1

   # Module functions
   my_function() {
     local arg=$1
     # Implementation
   }

   another_function() {
     local arg=$1
     # Implementation
   }

   # Export functions (optional)
   export -f my_function
   export -f another_function
   ```

3. **Add to tk-common.sh**
   ```bash
   # In lib/tk-common.sh, add:
   source "$LIB_DIR/tk-mynewmodule.sh"
   ```

4. **Document in lib/README.md**
   ```markdown
   ### lib/tk-mynewmodule.sh
   Description of what this module does.

   **Functions:**
   - `my_function()` - Does something
   - `another_function()` - Does something else
   ```

5. **Test the module**
   ```bash
   # Create test file
   cat > test_module.sh <<'EOF'
   #!/usr/bin/env bash
   source lib/tk-common.sh

   my_function "test"
   another_function "test"
   EOF

   chmod +x test_module.sh
   ./test_module.sh
   ```

---

## Testing & Validation

### ✅ Test Suite Structure

**Location**: `./tests/`

```
tests/
├── test-common.sh          # Common test utilities
├── test-validation.sh      # Test validation functions
├── test-docker.sh          # Test Docker operations
├── test-connect.sh         # Test connect-service.sh
├── test-add.sh            # Test add-service.sh
└── fixtures/              # Test data
    ├── sample-python/
    ├── sample-node/
    └── sample-configs/
```

### ✅ Running Tests

```bash
# Run all tests
./run-tests.sh

# Run specific test file
./run-tests.sh tests/test-validation.sh

# Run with verbose output
VERBOSE=true ./run-tests.sh

# Run in CI mode (no colors, exit on failure)
CI=true ./run-tests.sh
```

### ✅ Writing Tests

**Pattern for test files:**

```bash
#!/usr/bin/env bash
#
# test-myfeature.sh - Tests for my feature
#

# Load test utilities
source "$(dirname "$0")/test-common.sh"

# Setup (runs before each test)
setup() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"
}

# Teardown (runs after each test)
teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# Test functions (must start with test_)
test_my_feature_works() {
  local result=$(my_function "input")
  assert_equals "expected" "$result"
}

test_my_feature_handles_errors() {
  assert_fails my_function "bad-input"
}

test_my_feature_with_options() {
  local result=$(my_function "input" --option)
  assert_contains "substring" "$result"
}

# Run tests
run_tests
```

**Assertion Functions:**

```bash
assert_equals expected actual       # Values must be equal
assert_not_equals val1 val2        # Values must differ
assert_contains substring string   # String contains substring
assert_success command             # Command exits with 0
assert_fails command              # Command exits with non-zero
assert_file_exists path           # File exists
assert_file_contains path pattern # File contains pattern
```

### ✅ Pre-Commit Validation

**Before committing:**

```bash
# 1. Run tests
./run-tests.sh

# 2. Lint shell scripts (if shellcheck installed)
shellcheck *.sh lib/*.sh

# 3. Check for common issues
grep -r "TODO\|FIXME" .

# 4. Verify git status
git status
git diff
```

---

## Troubleshooting Patterns

### 🔍 Diagnostic Workflow

```
Issue Detected
│
├─ Script fails to execute?
│  ├─ Check permissions: ls -la script.sh
│  ├─ Make executable: chmod +x script.sh
│  └─ Check shebang: head -1 script.sh
│
├─ Import/source error?
│  ├─ Verify file exists: ls -la lib/tk-common.sh
│  ├─ Check path in source statement
│  └─ Verify SCRIPT_DIR is correct
│
├─ Function not found?
│  ├─ Check library is loaded: source lib/tk-common.sh
│  ├─ Verify function exists: declare -f function_name
│  └─ Check for typos in function name
│
├─ Docker command fails?
│  ├─ Check Docker running: docker info
│  ├─ Check compose version: docker compose version
│  ├─ Verify project root: find_project_root
│  └─ Check docker-compose.yml syntax: docker compose config
│
└─ Service detection fails?
   ├─ Run in verbose mode: VERBOSE=true ./connect-service.sh path
   ├─ Check service path exists
   ├─ Verify language files present (package.json, requirements.txt)
   └─ Check detector logic in lib/service-detector.sh
```

### 🐛 Common Issues and Solutions

#### Issue 1: tk: command not found

**Symptoms:**
- After install, `tk` command doesn't work
- Shell can't find tk executable

**Diagnosis:**
```bash
# Check if alias was added
grep "alias tk=" ~/.zshrc ~/.bashrc

# Check if script exists
ls -la /path/to/traefik/scripts/tk
```

**Solutions:**

1. **Shell not reloaded**
   ```bash
   source ~/.zshrc  # or ~/.bashrc
   ```

2. **Reinstall**
   ```bash
   cd /path/to/traefik/scripts
   ./install.sh
   source ~/.zshrc
   ```

3. **Use full path temporarily**
   ```bash
   /path/to/traefik/scripts/tk --help
   ```

#### Issue 2: Permission denied

**Symptoms:**
- `bash: ./script.sh: Permission denied`
- Script won't execute

**Solutions:**

```bash
# Make executable
chmod +x script.sh
chmod +x lib/*.sh

# Or execute with bash
bash script.sh
```

#### Issue 3: Library function not found

**Symptoms:**
- `script.sh: line 45: log_info: command not found`
- Functions from lib/ not available

**Diagnosis:**
```bash
# Check if library loaded
bash -x ./script.sh  # Trace execution

# Verify source path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "$SCRIPT_DIR/lib/tk-common.sh"
ls -la "$SCRIPT_DIR/lib/tk-common.sh"
```

**Solutions:**

1. **Fix source path**
   ```bash
   # Ensure correct path
   source "$(dirname "$0")/lib/tk-common.sh"

   # Or use SCRIPT_DIR
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "$SCRIPT_DIR/lib/tk-common.sh"
   ```

2. **Check library exists**
   ```bash
   ls -la lib/tk-common.sh
   ```

#### Issue 4: Service detection fails

**Symptoms:**
- `connect-service.sh` can't detect language/framework
- Falls back to generic template

**Diagnosis:**
```bash
# Run in verbose mode
VERBOSE=true ./connect-service.sh /path/to/service --dry-run

# Check what files exist
ls -la /path/to/service/

# Test detector directly
source lib/service-detector.sh
detect_language /path/to/service
```

**Solutions:**

1. **Missing detection files**
   ```bash
   # Python needs: requirements.txt, pyproject.toml, or setup.py
   touch requirements.txt

   # Node.js needs: package.json
   npm init -y
   ```

2. **Detection logic doesn't cover framework**
   ```bash
   # Add framework detection to lib/service-detector.sh
   # See "Workflow 3: Adding Support for New Framework"
   ```

#### Issue 5: Docker Compose syntax error

**Symptoms:**
- `docker compose up` fails with YAML error
- Service block malformed

**Diagnosis:**
```bash
# Validate compose file
docker compose config

# Check specific service
docker compose config | grep -A 20 service-name
```

**Solutions:**

1. **Fix indentation**
   ```yaml
   # YAML requires exact spacing
   services:     # 0 spaces
     my-service: # 2 spaces
       build:    # 4 spaces
         context: ./services/my-service  # 6 spaces
   ```

2. **Quote special characters**
   ```yaml
   # Quote values with special chars
   environment:
     - "SPECIAL_VAR=value:with:colons"
   ```

3. **Regenerate block**
   ```bash
   # Remove service and re-add
   # Manually edit docker-compose.yml to remove service
   ./tk connect /path/to/service
   ```

---

## Agent Decision Trees

### 🌳 Decision Tree 1: User Asks to Add Feature

```
User requests new feature
│
├─ Is it a new CLI command?
│  └─ YES:
│     ├─ Simple (< 50 lines)?
│     │  └─ Add function to ./tk directly
│     └─ Complex (> 50 lines)?
│        └─ Create new script file (new-feature.sh)
│           └─ Add exec call in ./tk
│
├─ Is it a library function?
│  └─ YES:
│     ├─ Fits existing module?
│     │  └─ Add to appropriate lib/tk-*.sh
│     └─ New category?
│        └─ Create new lib/tk-newmodule.sh
│           └─ Load in lib/tk-common.sh
│
├─ Is it framework support?
│  └─ YES:
│     ├─ Update lib/service-detector.sh
│     ├─ Add detection logic
│     ├─ Add Dockerfile template in lib/docker-generator.sh
│     └─ Update connect-service.sh to handle new type
│
└─ Is it configuration option?
   └─ YES:
      ├─ Add default to lib/tk-common.sh
      ├─ Update .tkrc.example
      └─ Document in README.md
```

### 🌳 Decision Tree 2: Script Fails

```
Script execution fails
│
├─ Check error message
│  │
│  ├─ "Permission denied"
│  │  └─ chmod +x script.sh
│  │
│  ├─ "command not found" (tk)
│  │  └─ ./install.sh && source ~/.zshrc
│  │
│  ├─ "function not found"
│  │  └─ Verify library loaded: source lib/tk-common.sh
│  │
│  ├─ "Docker not running"
│  │  └─ Start Docker daemon
│  │
│  └─ Other error
│     └─ Enable debug: bash -x script.sh
│
├─ Run in dry-run mode
│  └─ ./script.sh --dry-run
│
├─ Run in verbose mode
│  └─ VERBOSE=true ./script.sh
│
└─ Check logs
   └─ Read output for clues
```

### 🌳 Decision Tree 3: When to Rebuild vs Restart

```
Need to apply changes
│
├─ What changed?
│  │
│  ├─ Script file (.sh)
│  │  └─ NO DOCKER ACTION (just re-run script)
│  │
│  ├─ Library file (lib/*.sh)
│  │  └─ NO DOCKER ACTION (just re-run script)
│  │
│  ├─ Traefik configuration (parent dir)
│  │  └─ Restart Traefik: docker compose restart traefik
│  │
│  ├─ Service code (parent services/ dir)
│  │  └─ NO DOCKER ACTION (hot reload if configured)
│  │
│  ├─ Dockerfile
│  │  └─ REBUILD: docker compose up -d --build service
│  │
│  ├─ docker-compose.yml
│  │  └─ RECREATE: docker compose up -d service
│  │
│  └─ Dependencies (requirements.txt, package.json)
│     └─ REBUILD: docker compose up -d --build service
```

---

## Code Patterns & Examples

### 🔧 Pattern 1: Complete Script Example

**Example: backup-service.sh** (hypothetical new script)

```bash
#!/usr/bin/env bash
#
# backup-service.sh - Backup service data and configuration
#
# Usage: ./backup-service.sh [options] <service-name>
#

# ============================================================================
# Configuration
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/tk-common.sh"

BACKUP_DIR="${BACKUP_DIR:-/tmp/traefik-backups}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# ============================================================================
# Functions
# ============================================================================

show_help() {
  cat <<EOF
Usage: $(basename "$0") [options] <service-name>

Backup a service's volumes, configuration, and database data.

Options:
  -h, --help          Show this help message
  -d, --dry-run       Preview what would be backed up
  -v, --verbose       Enable verbose output
  -o, --output DIR    Backup directory (default: /tmp/traefik-backups)

Arguments:
  service-name        Name of the service to backup

Examples:
  $(basename "$0") python-api
  $(basename "$0") mongodb --output /backups
  $(basename "$0") python-api --dry-run

EOF
}

backup_service() {
  local service_name=$1
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_path="$BACKUP_DIR/${service_name}_${timestamp}"

  # Validate service exists
  if ! service_exists "$service_name"; then
    log_fatal "Service does not exist: $service_name"
  fi

  log_info "Backing up service: $service_name"

  # Create backup directory
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would create: $backup_path"
  else
    mkdir -p "$backup_path"
    log_debug "Created backup directory: $backup_path"
  fi

  # Backup volumes
  log_info "Backing up volumes..."
  local volumes=$(docker inspect "$service_name" -f '{{range .Mounts}}{{.Name}} {{end}}')

  for volume in $volumes; do
    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "[DRY RUN] Would backup volume: $volume"
    else
      docker run --rm \
        -v "$volume:/data" \
        -v "$backup_path:/backup" \
        alpine tar czf "/backup/${volume}.tar.gz" -C /data .
      print_success "Backed up volume: $volume"
    fi
  done

  # Backup configuration (from docker-compose.yml)
  log_info "Backing up configuration..."
  local project_root=$(find_project_root)

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would backup docker-compose configuration"
  else
    docker compose config | \
      grep -A 50 "^  $service_name:" > "$backup_path/config.yml"
    print_success "Backed up configuration"
  fi

  # Summary
  print_header "Backup Summary"
  print_status "Service: $service_name"
  print_status "Backup location: $backup_path"
  print_status "Timestamp: $timestamp"
  print_success "Backup completed successfully!"
}

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -o|--output)
      BACKUP_DIR="$2"
      shift 2
      ;;
    -*)
      log_error "Unknown option: $1"
      show_help
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# ============================================================================
# Main Execution
# ============================================================================

SERVICE_NAME="${1:-}"

if [[ -z "$SERVICE_NAME" ]]; then
  log_error "Missing required argument: service-name"
  show_help
  exit 1
fi

validate_service_name "$SERVICE_NAME" || exit 1
validate_docker || exit 1

backup_service "$SERVICE_NAME"
```

### 🔧 Pattern 2: Service Detection Example

**Example from lib/service-detector.sh:**

```bash
detect_python_framework() {
  local service_path=$1

  # Check for FastAPI
  if grep -qr "from fastapi import\|import fastapi" "$service_path"/*.py 2>/dev/null; then
    echo "fastapi"
    return 0
  fi

  # Check for Flask
  if grep -qr "from flask import\|import flask" "$service_path"/*.py 2>/dev/null; then
    echo "flask"
    return 0
  fi

  # Check for Django
  if [[ -f "$service_path/manage.py" ]] || grep -qr "django" "$service_path"/*.py 2>/dev/null; then
    echo "django"
    return 0
  fi

  # Generic Python
  echo "python"
}

detect_python_port() {
  local service_path=$1
  local port=8000  # Default

  # Search for uvicorn.run() calls
  local uvicorn_port=$(grep -r "uvicorn.run.*port=" "$service_path"/*.py 2>/dev/null | \
    sed -n 's/.*port=\([0-9]\+\).*/\1/p' | head -1)

  if [[ -n "$uvicorn_port" ]]; then
    port=$uvicorn_port
  fi

  # Search for app.run() calls (Flask)
  local flask_port=$(grep -r "app.run.*port=" "$service_path"/*.py 2>/dev/null | \
    sed -n 's/.*port=\([0-9]\+\).*/\1/p' | head -1)

  if [[ -n "$flask_port" ]]; then
    port=$flask_port
  fi

  echo "$port"
}

find_python_entry() {
  local service_path=$1

  # Priority order for entry points
  local candidates=("main.py" "app.py" "application.py" "server.py" "wsgi.py")

  for candidate in "${candidates[@]}"; do
    if [[ -f "$service_path/$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  # Fallback: find any .py file with uvicorn or Flask
  local entry=$(find "$service_path" -maxdepth 1 -name "*.py" -exec grep -l "uvicorn\|flask\|FastAPI" {} \; 2>/dev/null | head -1)

  if [[ -n "$entry" ]]; then
    basename "$entry"
    return 0
  fi

  # Default
  echo "main.py"
}
```

### 🔧 Pattern 3: Docker Compose Generation

**Example from lib/docker-generator.sh:**

```bash
generate_compose_block() {
  local service_name=$1
  local port=$2
  local language=$3
  local has_db=${4:-false}

  cat <<EOF
  $service_name:
    build:
      context: ./services/$service_name
      dockerfile: Dockerfile
    container_name: $service_name
    restart: unless-stopped
    networks:
      - traefik
    volumes:
      - ./services/$service_name:/app:delegated
EOF

  # Add language-specific volume exclusions
  if [[ "$language" == "node" ]]; then
    cat <<EOF
      - /app/node_modules
EOF
  fi

  cat <<EOF
    environment:
      - SERVICE_NAME=$service_name
      - LOG_LEVEL=info
EOF

  # Add database connection if needed
  if [[ "$has_db" == "true" ]]; then
    cat <<EOF
      - MONGODB_URI=mongodb://admin:changeme@mongodb:27017/
      - MONGODB_DATABASE=appdb
EOF
  fi

  # Traefik labels
  cat <<EOF
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.$service_name.rule=Host(\\\`$service_name.localhost\\\`)"
      - "traefik.http.routers.$service_name.entrypoints=websecure"
      - "traefik.http.routers.$service_name.tls=true"
      - "traefik.http.services.$service_name.loadbalancer.server.port=$port"
      - "traefik.docker.network=traefik"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$port/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s
    depends_on:
      traefik:
        condition: service_healthy
EOF

  # Add MongoDB dependency if needed
  if [[ "$has_db" == "true" ]]; then
    cat <<EOF
      mongodb:
        condition: service_healthy
EOF
  fi
}
```

---

## Best Practices

### ✅ Always Do:

1. **Read existing code first**: Before modifying, understand current implementation
2. **Use library functions**: Don't reinvent wheel, use functions from lib/
3. **Validate inputs**: Always validate user input with validation functions
4. **Enable strict mode**: Always use `set -euo pipefail`
5. **Quote variables**: Always quote: `"$variable"` not `$variable`
6. **Add help text**: Every script needs `--help` flag with examples
7. **Support dry-run**: Add `--dry-run` for preview mode
8. **Log operations**: Use log_info, log_warn, log_error appropriately
9. **Test changes**: Run `./run-tests.sh` before committing
10. **Update documentation**: Update README.md, QUICKSTART.md, and this file

### ❌ Never Do:

1. **Don't skip validation**: Always validate paths, names, ports
2. **Don't use `cd` without checking**: Always `cd "$dir" || exit 1`
3. **Don't ignore errors**: Use `set -e` or explicit error checking
4. **Don't hardcode paths**: Use `find_project_root()` or relative paths
5. **Don't commit to main directly**: Always use develop branch first
6. **Don't skip tests**: Always run test suite before merging
7. **Don't use `rm -rf` without validation**: Validate paths first
8. **Don't expose secrets**: No API keys, passwords in code
9. **Don't break backward compatibility**: Maintain existing CLI interface
10. **Don't assume Docker is running**: Always call `validate_docker()`

### 🎯 Script Writing Guidelines:

1. **Structure**: Follow the script template pattern
2. **Naming**: Use kebab-case for files: `my-script.sh`
3. **Functions**: Use snake_case for functions: `my_function()`
4. **Variables**: Use UPPER_CASE for constants, lower_case for local vars
5. **Comments**: Add comments for complex logic, not obvious code
6. **Exit codes**: 0 = success, 1 = error, 2 = usage error
7. **Dependencies**: Document any external command dependencies
8. **Portability**: Test on both macOS and Linux if possible

### 🔒 Security Guidelines:

1. **Path traversal**: Validate paths don't contain `../`
2. **Command injection**: Never use `eval` with user input
3. **Quote everything**: Prevent word splitting attacks
4. **Sanitize env vars**: Use `sanitize_env_value()`
5. **Validate service names**: No special characters or spaces
6. **Check file permissions**: Don't expose secrets in files
7. **Use absolute paths**: Prefer absolute over relative paths

---

## Appendix

### 📚 Related Documentation

**In this repository:**
- [README.md](./README.md) - Complete script reference
- [QUICKSTART.md](./QUICKSTART.md) - Quick start guide
- [lib/README.md](./lib/README.md) - Library module documentation
- [TEST_SUITE_SUMMARY.md](./TEST_SUITE_SUMMARY.md) - Test suite overview
- [.github/WORKFLOW.md](./.github/WORKFLOW.md) - Git workflow guide

**Parent directory** (not git-tracked):
- `../README.md` - Traefik project overview
- `../QUICKSTART.md` - Traefik setup guide
- `../docker-compose.yml` - Service orchestration
- `../docs/` - Additional documentation

### 🔗 External Resources

- **Bash Guide**: https://mywiki.wooledge.org/BashGuide
- **ShellCheck**: https://www.shellcheck.net/
- **Traefik Docs**: https://doc.traefik.io/traefik/
- **Docker Compose**: https://docs.docker.com/compose/

### 📖 Glossary

- **tk**: Traefik CLI - main command-line tool
- **Service**: Docker container running application code
- **Traefik**: Reverse proxy and load balancer
- **Label**: Docker metadata used for Traefik routing
- **Dry run**: Preview mode that shows what would happen
- **Library module**: Shared bash functions in lib/
- **Project root**: Parent directory containing docker-compose.yml
- **Service detector**: Auto-detection of language/framework
- **Docker generator**: Creates Dockerfiles and compose blocks

---

## Agent Workflow Summary

### When User Asks You To:

1. **Add new CLI command**
   - Check if simple (add to `./tk`) or complex (new script file)
   - Follow script template pattern
   - Update help text
   - Test with `./tk command --help`
   - Update README.md

2. **Fix a bug**
   - Reproduce the issue
   - Add debug output if needed
   - Fix the bug
   - Add regression test
   - Run test suite
   - Commit with clear message

3. **Add framework support**
   - Update `lib/service-detector.sh` (detection logic)
   - Update `lib/docker-generator.sh` (Dockerfile template)
   - Update `connect-service.sh` (add case for new language)
   - Test with real project
   - Update documentation

4. **Modify library function**
   - Read current implementation
   - Make minimal changes
   - Test function in isolation
   - Run full test suite
   - Check for uses in other scripts

5. **Debug an issue**
   - Run with `VERBOSE=true`
   - Use `bash -x` for tracing
   - Check logs with `log_debug`
   - Verify assumptions with validation functions
   - Test fix with `--dry-run` first

---

**Document Version**: 1.0
**Last Updated**: 2026-01-14
**Maintained By**: Development Team
**For Issues**: Create issue in repository
**Git Branch**: develop

