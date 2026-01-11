# Traefik CLI (tk) - Documentation

A unified, maintainable CLI tool for managing Traefik services. Built following KISS, YAGNI, and DRY principles.

## Features

✅ **Add Services** - Automatically detect and configure services for Traefik
✅ **Remove Services** - Clean removal of services from docker-compose.yml
✅ **Start/Stop/Restart** - Manage all or specific services
✅ **View Logs** - Tail logs for debugging
✅ **List Services** - See all configured services
✅ **Status** - Check service health and URLs
✅ **Setup/Cleanup** - Initialize or clean up Traefik environment

## Quick Start

### Installation

```bash
# From the scripts directory
./install.sh

# Reload your shell
source ~/.zshrc  # or source ~/.bashrc
```

### Basic Usage

```bash
# Show help
tk help

# List all services
tk list

# Check service status
tk status

# Start all services
tk start

# Start specific service
tk start python-api

# View logs
tk logs python-api

# Add a new service
tk add /path/to/my-api

# Remove a service
tk remove my-api
```

## Commands Reference

### Service Management

#### `tk add <path> [name] [options]`
Add a service to Traefik. Automatically detects language, framework, port, and dependencies.

**Examples:**
```bash
# Auto-detect and add
tk add /path/to/my-api

# Add with custom name
tk add /path/to/backend api-v2

# Override detected port
tk add /path/to/service --port 9000

# Dry run (preview without changes)
tk add /path/to/service --dry-run
```

**Options:**
- `--port PORT` - Override detected port
- `--domain DOMAIN` - Custom domain (default: service-name.localhost)
- `--no-docker` - Skip Dockerfile generation
- `--dry-run` - Show what would be done without making changes

#### `tk remove <name>`
Remove a service from Traefik and docker-compose.yml.

**Examples:**
```bash
tk remove my-api
tk rm old-service  # 'rm' is an alias
```

**Note:** This only removes the service from docker-compose.yml. The service directory is not deleted.

### Container Operations

#### `tk start [name]`
Start all services or a specific service.

**Examples:**
```bash
tk start              # Start all services
tk start python-api   # Start specific service
tk up                 # 'up' is an alias
```

#### `tk stop [name]`
Stop all services or a specific service.

**Examples:**
```bash
tk stop              # Stop all services
tk stop python-api   # Stop specific service
tk down              # 'down' is an alias
```

#### `tk restart [name]`
Restart all services or a specific service.

**Examples:**
```bash
tk restart           # Restart all services
tk restart traefik   # Restart specific service
```

#### `tk logs [name]`
View logs for all or specific service (follows by default).

**Examples:**
```bash
tk logs              # All service logs
tk logs python-api   # Specific service logs
```

### Information

#### `tk list`
List all services defined in docker-compose.yml.

**Aliases:** `ls`

**Example:**
```bash
tk list
# Output:
# Services in docker-compose.yml:
#   • traefik
#   • python-api
#   • node-web
#   • mongodb
```

#### `tk status`
Show service status and accessible URLs.

**Aliases:** `ps`

**Example:**
```bash
tk status
# Shows:
# - Container status (docker compose ps)
# - Service URLs with https://
```

### Setup & Maintenance

#### `tk setup`
Initial Traefik environment setup.

Performs:
- Prerequisites check (Docker, mkcert)
- SSL certificate generation
- Network creation
- Environment file setup
- Service startup

**Example:**
```bash
tk setup
```

#### `tk cleanup`
Clean up Traefik environment.

Removes:
- All containers and volumes
- Docker network
- Optionally: SSL certificates and .env file

**Aliases:** `clean`

**Example:**
```bash
tk cleanup
```

#### `tk help`
Show help message with all commands.

**Aliases:** `--help`, `-h`

#### `tk version`
Show CLI version.

**Aliases:** `--version`, `-v`

## Architecture

The CLI is built with modularity and maintainability in mind:

```
scripts/
├── tk                      # Main CLI entry point
├── install.sh             # Installation script
├── uninstall.sh           # Uninstallation script
├── connect-service.sh     # Service auto-detection & connection
├── setup.sh               # Initial setup
├── cleanup.sh             # Environment cleanup
└── lib/                   # Shared library functions
    ├── service-detector.sh   # Language/framework detection
    └── docker-generator.sh   # Dockerfile/compose generation
```

### Design Principles

**KISS (Keep It Simple, Stupid)**
- Simple subcommand structure
- Clear, descriptive command names
- Minimal complexity in each function

**YAGNI (You Aren't Gonna Need It)**
- Only implements required features
- No over-engineering or speculative features
- Focused on the core use cases

**DRY (Don't Repeat Yourself)**
- Reuses existing scripts (connect-service.sh, setup.sh, cleanup.sh)
- Shared library functions in lib/
- Single source of truth for service detection and generation

## Supported Services

The CLI automatically detects and configures:

**Languages:**
- Python (FastAPI, Flask, Django)
- Node.js (Express, NestJS, Next.js, Koa)

**Databases:**
- MongoDB (auto-detected, auto-configured)
- PostgreSQL (auto-detected, auto-configured)
- Redis (auto-detected, auto-configured)

## Configuration

Services are configured with:
- ✅ Traefik routing labels
- ✅ HTTPS/TLS enabled
- ✅ Health checks
- ✅ Hot reload for development
- ✅ Proper networking
- ✅ Database connection environment variables

## Troubleshooting

### Service not found
```bash
# Verify service exists in docker-compose.yml
tk list

# Check if container is running
tk status
```

### Logs not showing
```bash
# Make sure service is running
tk start <service-name>

# Then view logs
tk logs <service-name>
```

### Cannot remove service
```bash
# Make sure service is stopped first
tk stop <service-name>

# Then remove
tk remove <service-name>

# Check backup file if needed
ls -la ../docker-compose.yml.backup
```

## Uninstallation

```bash
# From the scripts directory
./uninstall.sh

# Reload your shell
source ~/.zshrc  # or source ~/.bashrc
```

## Examples

### Complete Workflow

```bash
# 1. Initial setup
tk setup

# 2. Check what's running
tk status

# 3. Add a new service
tk add ~/projects/my-api

# 4. Check logs to verify it started
tk logs my-api

# 5. List all services
tk list

# 6. Stop a service for debugging
tk stop my-api

# 7. Restart after fixes
tk restart my-api

# 8. Remove when done
tk remove my-api
```

### Quick Operations

```bash
# Restart everything
tk restart

# Check if services are healthy
tk status

# Follow logs for debugging
tk logs

# Add multiple services
tk add ~/projects/api-v1 backend
tk add ~/projects/frontend web
tk add ~/projects/worker processor

# View all configured services
tk list
```

## Integration with IDE

The CLI works seamlessly from any directory:

```bash
# From anywhere on your system
tk status

# Add services from anywhere
tk add /Users/you/projects/service1
tk add /Users/you/work/service2
```

## Performance

- Fast subcommand routing
- Minimal overhead
- Direct docker compose integration
- No unnecessary dependencies

## Security

- Read-only Docker socket mount
- No-new-privileges security option
- Self-signed certificates for local development only
- Environment variable based configuration

## License

Part of the Traefik Local Development Environment project.

## Contributing

When adding new commands:
1. Add command function: `cmd_<name>()`
2. Add to main() case statement
3. Update help message
4. Document in this file
5. Test thoroughly

## Version History

### v1.0.0 (2026-01-10)
- Initial release
- Core commands: add, remove, start, stop, restart, logs, list, status
- Setup and cleanup commands
- Auto-service detection
- Installation script
