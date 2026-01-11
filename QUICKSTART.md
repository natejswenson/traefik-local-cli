# Traefik CLI (tk) - Quick Start Guide

Get up and running with the Traefik CLI in under 2 minutes.

## Installation

```bash
# Navigate to scripts directory
cd /path/to/traefik/scripts

# Run installation
./install.sh

# Reload your shell
source ~/.zshrc  # or source ~/.bashrc for bash users
```

## Verify Installation

```bash
# Check version
tk version

# Show help
tk help

# List current services
tk list
```

## Common Tasks

### 1. Start Traefik Environment

```bash
tk start
```

### 2. Check Service Status

```bash
tk status
```

### 3. Add a New Service

```bash
# From anywhere on your machine
tk add /path/to/your/service

# With custom name
tk add /path/to/your/service my-api

# Dry run first
tk add /path/to/your/service --dry-run
```

### 4. View Logs

```bash
# All services
tk logs

# Specific service
tk logs python-api
```

### 5. Remove a Service

```bash
tk remove service-name
```

### 6. Stop Everything

```bash
tk stop
```

## Daily Workflow

```bash
# Morning: Start your environment
tk start

# Add a service you're working on
tk add ~/projects/my-new-api

# Check it's running
tk status

# Debug with logs
tk logs my-new-api

# Evening: Stop everything
tk stop
```

## Cheat Sheet

| Command | Description |
|---------|-------------|
| `tk add <path>` | Add service |
| `tk remove <name>` | Remove service |
| `tk start` | Start all services |
| `tk start <name>` | Start specific service |
| `tk stop` | Stop all services |
| `tk stop <name>` | Stop specific service |
| `tk restart` | Restart all services |
| `tk logs` | View all logs |
| `tk logs <name>` | View specific logs |
| `tk list` | List services |
| `tk status` | Show status & URLs |
| `tk help` | Show help |

## Aliases

Short versions of commands:
- `tk rm` = `tk remove`
- `tk up` = `tk start`
- `tk down` = `tk stop`
- `tk ls` = `tk list`
- `tk ps` = `tk status`
- `tk clean` = `tk cleanup`

## URLs

After starting services, access them at:
- Traefik Dashboard: https://traefik.localhost
- Your services: https://service-name.localhost

## Need Help?

```bash
tk help
```

Or check the full documentation:
```bash
cat CLI.md
```

## Uninstall

```bash
./uninstall.sh
```

## Tips

1. **Use tab completion** - Your shell should complete service names
2. **Run from anywhere** - Once installed, `tk` works from any directory
3. **Check status often** - `tk status` shows URLs and health
4. **Dry run first** - Use `--dry-run` when adding services to preview changes
5. **Keep logs running** - `tk logs <service>` is great for debugging

## What's Next?

- Read [CLI.md](CLI.md) for complete documentation
- Check project [README.md](../README.md) for Traefik setup details
- Explore [CLAUDE.md](../CLAUDE.md) for project guidelines
