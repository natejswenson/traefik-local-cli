# Traefik Scripts - Quick Start Guide

## Agent inspection and diagnostics

`tk list --json` reports resolved routes; `tk status --json` adds container health.
`tk doctor --probe --json` verifies readiness and HTTPS. Use
`tk doctor --memory-hub /path/to/local-memory --json` for optional live hub readiness.
`tk logs SERVICE --tail 100` returns a bounded snapshot; pass `--follow` to stream.
Inspection is read-only, does not source `.tkrc`, redacts Compose errors and has
bounded command timeouts. Export `COMPOSE_FILE` or `DOCKER_COMPOSE_FILE` when needed.
`status` exit 0 means inspection succeeded; `doctor` exits 1 on failed checks.

`refresh-certs.sh` preserves wildcard names and adds concrete routed hosts for
macOS TLS clients. Reload Traefik afterward. `setup-dns.sh --check` inspects DNS;
`--apply` repairs macOS resolver files with administrator authentication.
The parent stack provides Codex's `.agents/skills/traefik` and `AGENTS.md`.
Run `./run-tests.sh` for Python regression tests plus the existing Bats suites.

## Agent service operations

Use exact Compose service names, available from `tk list --json`:

```bash
tk inspect my-api --json                     # build context, dependencies and URLs
tk rebuild my-api --dry-run --json           # preview scope; no daemon changes
tk rebuild my-api --json                     # build, recreate and wait for readiness
tk wait my-api --timeout 30 --json            # read-only, bounded readiness check
tk doctor my-api --probe --json              # verify the affected HTTPS routes
tk start --all --json                        # explicitly start the whole configuration
```

`start`, `stop`, `restart`, `rebuild`, `inspect` and `wait` require a service or
`--all`; missing/extra targets are errors. Lifecycle commands support `--dry-run`
and return structured errors with `--json`. Start/rebuild exclude dependencies
and verify them before applying; `--with-deps` explicitly permits dependency startup.
Restart does not install a rebuilt image. Operations wait for running/healthy
containers (stopped for `stop`); configured replica counts must be met. Use doctor
for separate DNS/TLS verification. Timeouts default to 120 seconds, rebuild 600.
Exit codes: 0 success, 1 runtime failure, 2 usage, 3 readiness deadline.

A preview returns `state: planned` and `changed: false`. After successful Compose
execution, `changed: true` means the action was accepted. On a failed/timed-out
action, `changed: null` means partial effects are possible: inspect status before
retrying. No automatic action retry or rollback occurs. Structured lifecycle
commands, like inspection, do not execute `.tkrc`; use exported Compose settings.

## Scoped removal

`tk remove SERVICE --json` previews by default. Add `--apply` for an authorized
removal of only that service's containers and Compose block. Other containers,
volumes and app source remain; data stored only inside the removed container is
lost. The CLI validates the candidate configuration, blocks referenced services,
and saves a mode-600 source backup in ignored `.tk/backups/`. It does not use sudo
or change DNS/hosts. Multi-file/override configurations require explicit manual edits.
On partial failure, inspect `state`, `config_changed`, `error` and `backup` before retrying.

Structured lifecycle/removal mutations hold a per-checkout lock. Concurrent writes
return `operation_in_progress`; read-only commands and previews remain available.
The lock is released automatically on process exit. Raw Docker and older onboarding
scripts do not participate. Never delete an active lock file to bypass another command.

Optional live test: `python3 tests/smoke_agent_operations.py` from this scripts
checkout. It uses cached `traefik:3.6.5` and a unique disposable Docker project,
verifies the neighboring service and retained volume, then cleans its fixture only.



Get up and running with Traefik automation scripts in under 2 minutes.

## ⚡ Installation (30 seconds)

```bash
# Navigate to scripts directory
cd /path/to/traefik/scripts

# Run installation
./install.sh

# Reload your shell
source ~/.zshrc  # or source ~/.bashrc for bash users
```

## ✅ Verify Installation

```bash
# Check if tk is available
tk --help

# Should show available commands
```

## 🏁 One-Time Stack Setup

Before connecting any services, bring the stack itself up:

```bash
tk setup
```

This generates the local SSL certificates, creates the `traefik` Docker network, and starts the
compose stack — safe to re-run any time (every step is idempotent).

## 🚀 Common Tasks

### 1. Connect an External Service

The easiest way to add any service to Traefik:

```bash
# Auto-detect and connect a service
tk connect /path/to/your/service

# Example: Connect a FastAPI project
tk connect ~/projects/my-fastapi-api

# Example: Connect an Express project
tk connect ~/projects/my-express-app

# Example: With custom name
tk connect ~/projects/backend api-v2
```

**What happens:**
1. ✅ Detects language and framework
2. ✅ Finds port and entry point
3. ✅ Generates Dockerfile (if needed)
4. ✅ Adds to docker-compose.yml
5. ✅ Configures Traefik routing
6. ✅ Starts service with HTTPS

**Access your service:**
- URL: `https://your-service.localhost`
- Dashboard: `https://traefik.localhost`

### 2. View Service Status

```bash
# Show all services
tk status

# Output shows:
# ● traefik        healthy     https://traefik.localhost
# ● python-api     healthy     https://api.localhost
# ● node-web       healthy     https://web.localhost
```

### 3. View Logs

```bash
# All services
tk logs

# Specific service
tk logs python-api

# Follow logs (real-time)
tk logs -f python-api
```

### 4. Restart a Service

```bash
# Restart specific service
tk restart python-api

# Restart all services
tk restart --all
```

### 5. Add a New Service from Scratch

```bash
# Create a new Python service
tk add my-service 8080 python

# Create a new Node.js service
tk add my-web 3000 node
```

## 🎯 Quick Examples

### Example 1: Connect FastAPI Project

```bash
# You have a FastAPI project at ~/projects/user-api
cd /path/to/traefik/scripts

# Connect it
tk connect ~/projects/user-api

# Access it
open https://user-api.localhost
```

### Example 2: Connect Express Project with Custom Name

```bash
# You have an Express project at ~/dev/frontend
tk connect ~/dev/frontend web-app

# Access it
open https://web-app.localhost
```

### Example 3: Preview Before Connecting (Dry Run)

```bash
# See what would happen without making changes
tk connect ~/projects/my-service --dry-run

# Review the output, then run for real
tk connect ~/projects/my-service
```

### Example 3b: Connect a Service With Production Hardening

```bash
# Non-root container, data/secrets kept out of the image, no source mount,
# a wired API token. Use this for anything holding real data on a shared LAN.
tk connect ~/projects/my-api --harden

# tk prints a token to add to .env and reminds you that YOUR APP must enforce
# it on /api (tk wires the token but can't add auth middleware for you).
```

### Example 4: Monitor All Services

```bash
# Terminal 1: View all logs
tk logs -f

# Terminal 2: Check status periodically
watch -n 2 tk status
```

## 🛠️ Advanced Usage

### Using Script Files Directly

If you haven't installed the CLI:

```bash
# Connect service
./connect-service.sh /path/to/service

# Add new service
./add-service.sh service-name 8080 python

# Cleanup
./cleanup.sh
```

### Configuration

Create `.tkrc` in project root for custom settings:

```bash
# .tkrc
DEFAULT_DOMAIN_SUFFIX="internal"
AUTO_UPDATE_HOSTS="true"
DEFAULT_SERVICE_PORT="8000"
DOCKER_NETWORK="traefik"
```

### Environment Variables

Override settings temporarily:

```bash
# Dry run mode
DRY_RUN=true tk connect ~/projects/service

# Verbose output
VERBOSE=true tk connect ~/projects/service

# Custom domain suffix
DEFAULT_DOMAIN_SUFFIX="dev.local" tk connect ~/projects/service
```

## 📋 Workflow Examples

### Daily Development Workflow

```bash
# Morning: Start everything
tk start --all

# Check what's running
tk status

# Work on python-api, monitor logs
tk logs -f python-api

# Apply changes baked into the image
tk rebuild python-api --json

# Evening: Stop everything
tk stop --all
```

### Adding Multiple Services

```bash
# Connect existing projects
tk connect ~/projects/auth-service auth
tk connect ~/projects/user-service users
tk connect ~/projects/order-service orders

# Verify all running
tk status

# View all logs together
tk logs
```

### Testing a New Service

```bash
# Connect in dry-run mode first
tk connect ~/projects/new-service --dry-run

# Review the changes it would make
# If good, run for real
tk connect ~/projects/new-service

# Monitor startup
tk logs -f new-service

# Test the endpoint
curl -k https://new-service.localhost/health

# If issues, check logs
tk logs new-service
```

## 🔍 Troubleshooting

### tk: command not found

```bash
# Reinstall
cd /path/to/traefik/scripts
./install.sh

# Reload shell
source ~/.zshrc
```

### Service won't start

```bash
# Check logs
tk logs service-name

# Verify Docker is running
docker info

# Check docker-compose syntax
docker compose config
```

### Can't access https://service.localhost

```bash
# 1. Verify service is running
tk status

# 2. Check Traefik dashboard
open https://traefik.localhost

# 3. Check service logs
tk logs service-name

# 4. Verify port is correct
docker compose ps service-name
```

### Port already in use

```bash
# Find what's using the port
lsof -i :8080

# Change the port when connecting
tk connect ~/projects/service --port 8081
```

## 🎓 Next Steps

### Learn More

- [README.md](./README.md) - Complete script reference
- [lib/README.md](./lib/README.md) - Library documentation
- `tk help` - CLI help
- `tk help <command>` - Command-specific help

### Explore Features

```bash
# See all available commands
tk --help

# Get help on specific command
tk help connect
tk help add
tk help logs

# Try different options
tk connect ~/projects/service --verbose
tk connect ~/projects/service --dry-run
```

### Customize

1. Create `.tkrc` for project settings
2. Create `~/.tkrc` for user settings
3. Use environment variables for one-off changes

## 💡 Pro Tips

1. **Use tab completion** - The CLI supports tab completion for commands
2. **Dry run first** - Always use `--dry-run` when testing
3. **Monitor logs** - Keep logs open in a separate terminal
4. **Check status often** - Use `tk status` to verify health
5. **Use custom names** - Give services meaningful names when connecting

## 📚 Additional Resources

- Traefik Documentation: https://doc.traefik.io/traefik/
- Docker Compose: https://docs.docker.com/compose/
- Project issues: Check the main README for support info

---

**Ready to get started?**

```bash
# Install the CLI
./install.sh && source ~/.zshrc

# Connect your first service
tk connect /path/to/your/service

# Check it's running
tk status

# Access it
open https://your-service.localhost
```

🎉 **You're all set!**
