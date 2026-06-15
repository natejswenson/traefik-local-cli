# Traefik Scripts

Automation scripts and CLI for managing Traefik-based local development environments.

> **🔄 CI/CD Workflow:** This project uses a `develop → main` workflow. All changes are tested on the `develop` branch. When tests pass, use `./merge-to-main.sh` to create a PR and merge to `main`. See [.github/WORKFLOW.md](.github/WORKFLOW.md) for details.

## 📁 Contents

```
scripts/
├── tk                      Main CLI executable (Traefik CLI)
├── install.sh             Install tk CLI to PATH
├── uninstall.sh           Remove tk CLI from PATH
├── connect-service.sh     Auto-connect external services
├── add-service.sh         Add new service to project
├── cleanup.sh             Clean up Docker resources
├── setup-dns.sh           Configure local DNS settings
└── lib/                   Shared library modules
    ├── tk-common.sh         Main library loader
    ├── tk-logging.sh        Logging & output formatting
    ├── tk-validation.sh     Input validation & security
    ├── tk-docker.sh         Docker operations
    ├── service-detector.sh  Service detection logic
    └── docker-generator.sh  Dockerfile generation
```

## 🚀 Quick Start

### Install the CLI

```bash
# From the scripts directory
./install.sh

# Reload your shell
source ~/.zshrc  # or source ~/.bashrc
```

### Use the CLI

```bash
# Check available commands
tk --help

# Connect an external service
tk connect /path/to/your/service

# View service status
tk status

# View logs
tk logs [service-name]
```

See [QUICKSTART.md](./QUICKSTART.md) for detailed usage examples.

## 📜 Script Reference

### 🔧 Installation & Setup

#### `install.sh`
Installs the `tk` CLI to your shell PATH by adding an alias to `~/.zshrc` or `~/.bashrc`.

**Usage:**
```bash
./install.sh
```

**What it does:**
- Makes `tk` executable
- Adds alias to shell configuration
- Creates backup of shell config
- Provides instructions for reload

#### `uninstall.sh`
Removes the `tk` CLI from your shell PATH.

**Usage:**
```bash
./uninstall.sh
```

### 🔌 Service Management

#### `connect-service.sh` ⭐
Auto-connects external services from local repositories to Traefik.

**Features:**
- Auto-detects language (Python, Node.js)
- Auto-detects framework (FastAPI, Flask, Express, etc.)
- Finds port and entry point automatically
- Generates Dockerfile if needed
- Configures Traefik routing
- Starts service with HTTPS

**Usage:**
```bash
# Basic usage
./connect-service.sh /path/to/service

# With custom name
./connect-service.sh /path/to/service custom-name

# Dry run (preview only)
./connect-service.sh /path/to/service --dry-run

# Override detected port
./connect-service.sh /path/to/service --port 9000
```

**Supported:**
- ✅ Python: FastAPI, Flask, Django
- ✅ Node.js: Express, NestJS, Next.js, Koa
- ✅ Static/nginx: Static sites with nginx configuration
- ✅ Auto-detects: MongoDB, PostgreSQL, Redis

#### `add-service.sh`
Adds a new service to the project from scratch.

**Usage:**
```bash
./add-service.sh <service-name> [port] [language]
```

**Example:**
```bash
./add-service.sh my-api 8080 python
```

### 🧹 Utilities

#### `cleanup.sh`
Cleans up Docker resources (containers, volumes, networks).

**Usage:**
```bash
./cleanup.sh
```

**Warning:** This removes all Docker resources. Use with caution.

#### `setup-dns.sh`
Configures local DNS settings for `*.localhost` domains.

**Usage:**
```bash
./setup-dns.sh
```

### 🛠️ Main CLI: `tk`

The unified Traefik CLI provides all functionality in one command.

**Available Commands:**
- `tk connect <path>` - Connect external service
- `tk add <name>` - Add new service
- `tk status` - Show service status
- `tk logs [service]` - View logs
- `tk restart [service]` - Restart service(s)
- `tk stop [service]` - Stop service(s)
- `tk start [service]` - Start service(s)
- `tk clean` - Clean up resources
- `tk help` - Show help

**Options:**
- `--harden`, `--prod` - Emit production-hardened artifacts (see below)
- `--dry-run` - Preview changes without executing
- `--verbose` - Enable verbose output
- `--help` - Show help for command

### 🔒 Hardened mode (`tk connect --harden`)

By default `tk connect` generates **development** artifacts — root container, source
bind-mounted for hot-reload, auto-reload server, and (critically) the whole repo is sent to
the build context so a local `data/` or `*.db` can end up in the image. Fine for a scratch
app on a trusted box; **not** fine for anything holding real data on a shared LAN.

`tk connect <path> --harden` swaps in a production posture:

| Area | Hardened output |
|------|-----------------|
| Container | non-root `uid 1001`, `cap_drop: ALL`, `no-new-privileges`, production CMD (no `--reload`) |
| Image | `.dockerignore` excludes `data/`, `*.db`, `*.sqlite`, `*.ofx/qfx/qbo`, `*.pem`, `*.key`, `.env.*` |
| Compose | `ENV=production`, **no source bind-mount** (code lives in the image), a wired `<SERVICE>_API_TOKEN` |
| Token | a token is generated and printed for you to add to `.env` |

> ⚠️ **tk wires the token but cannot enforce it.** A bash generator can't add auth middleware
> to your app. In `--harden` mode your app MUST itself: (1) reject `/api/*` without
> `Authorization: Bearer $<SERVICE>_API_TOKEN`, (2) refuse to bind `0.0.0.0` without a ≥32-char
> token, and (3) expose an unauthenticated `GET /health`. Without (1) the service is reachable
> by every device on the LAN with no auth.
>
> Hardened mode drops the source bind-mount, so **persistent data needs a manual data-only
> volume** (e.g. `- ${HOME}/app/data:/data`).

### 🤖 Claude Code skill: `traefik-onboard`

This repo ships a [Claude Code](https://claude.com/claude-code) skill at
`.claude/skills/traefik-onboard/` that drives the *whole* hardened onboarding as a deterministic
procedure with pass/fail gates — and adds the app-side controls `--harden` can't generate (the
bearer-token gate, the non-loopback bind-refusal, and Claude-Agent-SDK isolation).

- **In this repo:** Claude Code auto-discovers it when you work inside the clone.
- **Everywhere else:** symlink it into your personal skills dir:
  `ln -s "$PWD/.claude/skills/traefik-onboard" ~/.claude/skills/traefik-onboard`
- **Configure** (`.claude/skills/traefik-onboard/SKILL.md` → *Configure*): defaults assume
  `~/localrepo/traefik`; override `TRAEFIK_DIR` / `STACK_DNS_IP` via your stack's gitignored `.env`.

Then just tell Claude *"add my X app to traefik"*.

## 📚 Library Modules

### `lib/tk-common.sh`
Main library entry point that loads all modules.

**Exports:**
- Configuration loading (`.tkrc` files)
- Error handling setup
- Common utilities

### `lib/tk-logging.sh`
Logging and output formatting functions.

**Functions:**
- `log()`, `log_debug()`, `log_info()`, `log_warn()`, `log_error()`, `log_fatal()`
- `print_header()`, `print_success()`, `print_error()`, `print_status()`
- `spinner()` - Progress indicator

### `lib/tk-validation.sh`
Input validation and security checking.

**Functions:**
- `validate_service_name()`, `validate_domain()`, `validate_port()`
- `validate_docker()`, `validate_docker_compose()`
- `sanitize_env_value()`, `validate_env_name()`

### `lib/tk-docker.sh`
Docker and Docker Compose operations.

**Functions:**
- `docker_compose_cmd()` - Wrapper for docker compose
- `service_exists()`, `get_service_domain()`, `list_services()`
- `find_project_root()` - Locate project root

### `lib/service-detector.sh`
Service language and framework detection.

**Capabilities:**
- Detects Python (FastAPI, Flask, Django)
- Detects Node.js (Express, NestJS, Next.js)
- Detects Static sites (nginx, generic HTML)
- Finds entry points and ports
- Identifies dependencies

### `lib/docker-generator.sh`
Generates Dockerfiles and docker-compose configurations.

**Features:**
- Language-specific Dockerfile templates (Python, Node.js, nginx)
- Docker Compose service blocks
- Traefik label generation
- Health check configuration

## ⚙️ Configuration

### Project Config (`.tkrc`)
Create a `.tkrc` file in your project root for custom configuration:

```bash
# Domain suffix for services
DEFAULT_DOMAIN_SUFFIX="internal"

# Auto-update /etc/hosts
AUTO_UPDATE_HOSTS="true"

# Confirm destructive operations
CONFIRM_DESTRUCTIVE="true"

# Docker network name
DOCKER_NETWORK="traefik"

# Default service port
DEFAULT_SERVICE_PORT="8000"
```

### User Config (`~/.tkrc`)
Create a global config in your home directory for user-wide settings.

## 🔒 Security Notes

- Scripts validate all inputs before execution
- Docker security best practices enforced
- Privileged mode and host network warnings
- Environment variable sanitization
- Path traversal attack prevention

## 🐛 Troubleshooting

### tk command not found
```bash
# Reload your shell
source ~/.zshrc  # or source ~/.bashrc

# Or reinstall
./install.sh
```

### Permission denied
```bash
# Make scripts executable
chmod +x *.sh tk
chmod +x lib/*.sh
```

### Docker errors
```bash
# Verify Docker is running
docker info

# Verify Docker Compose is available
docker compose version
```

## 📖 Documentation

- [QUICKSTART.md](./QUICKSTART.md) - Quick start guide
- [lib/README.md](./lib/README.md) - Library module documentation
- [../docs/tk-cli/](../docs/tk-cli/) - Extended documentation

## 🤝 Contributing

When adding new scripts or functions:

1. Follow existing naming conventions
2. Add comprehensive help text
3. Validate all inputs
4. Use library functions from `lib/`
5. Document in this README
6. Test in dry-run mode first

## 📝 License

Part of the Traefik local development environment.
