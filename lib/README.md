# TK CLI Library (test)

Modular Bash libraries for the Traefik CLI (tk) tool.

## Structure

```
lib/
├── tk-common.sh        Main library that sources all modules
├── tk-logging.sh       Logging and output formatting
├── tk-validation.sh    Input validation and security checks
├── tk-docker.sh        Docker operations and wrappers
├── service-detector.sh Service language/framework detection
└── docker-generator.sh Dockerfile and compose generation
```

## Module Overview

### tk-common.sh
Main entry point that loads all other modules. Sources libraries in dependency order.

**Functions:**
- Configuration loading (`.tkrc` files)
- Error handling setup
- Utility functions (confirm, dry-run)

### tk-logging.sh
**Functions:**
- `log()`, `log_debug()`, `log_info()`, `log_warn()`, `log_error()`, `log_fatal()`
- `print_header()`, `print_success()`, `print_error()`, `print_status()`
- `spinner()` - Progress indicator

### tk-validation.sh
**Functions:**
- `validate_service_name()`, `validate_domain()`, `validate_port()`
- `validate_docker()`, `validate_docker_compose()`
- `sanitize_env_value()`, `validate_env_name()`

### tk-docker.sh
**Functions:**
- `docker_compose_cmd()` - Docker Compose wrapper
- `service_exists()`, `get_service_domain()`, `list_services()`
- `find_project_root()` - Locate traefik project root

### service-detector.sh
Auto-detection of service language, framework, and configuration.

### docker-generator.sh
Generate Dockerfiles and docker-compose configurations.

## Usage

In your script:

```bash
#!/bin/bash
source "$(dirname "$0")/lib/tk-common.sh"

# All functions from all modules are now available
log_info "Starting script"
validate_service_name "my-service"
docker_compose_cmd up -d
```

## Adding New Functions

1. Choose appropriate module based on function purpose
2. Add function to module file
3. Export function at bottom of file
4. Document function with comments
5. Test in isolation before integration

## Refactoring Notes

This library was refactored from a single 1180-line file into focused modules for better maintainability and organization.
