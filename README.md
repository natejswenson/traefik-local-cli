# Traefik Scripts

Automation scripts for managing your Traefik development environment.

## Quick Start

### Connect External Service (NEW! ⭐)

The easiest way to add any service to Traefik:

```bash
./connect-service.sh /path/to/your/service
```

That's it! Auto-detects everything and connects your service.

**Or use Claude Code:**
```
/connect
```

See [../QUICKSTART.md](../QUICKSTART.md) and [../docs/guides/service-auto-connect.md](../docs/guides/service-auto-connect.md) for details.

## Scripts

### connect-service.sh ⭐ NEW
**Auto-connect services from local repositories**

Automatically detects language, framework, port, dependencies and configures Traefik routing.

```bash
# Basic usage
./connect-service.sh /path/to/service

# With options
./connect-service.sh /path/to/service [name] [--port 9000] [--dry-run]

# Help
./connect-service.sh --help
```

**Features:**
- Auto-detects Python (FastAPI/Flask/Django) and Node.js (Express/NestJS/Next.js)
- Generates Dockerfile if needed
- Configures dependencies (MongoDB, PostgreSQL, Redis)
- Adds to docker-compose.yml
- Starts service with Traefik routing
- Dry run mode for safety

**Supported:**
- ✅ Python: FastAPI, Flask, Django
- ✅ Node.js: Express, NestJS, Next.js, Koa
- ✅ Auto-detects MongoDB, PostgreSQL, Redis
- ✅ Generates or uses existing Dockerfile
- ✅ Cross-platform (macOS/Linux)

### setup.sh
**Initial environment setup**

```bash
./setup.sh
```

Sets up:
- Traefik network
- SSL certificates
- Environment variables
- Directory structure

### add-service.sh
**Manual service creation**

```bash
./add-service.sh <service-name> [port] [language]
```

Creates a new service from scratch with templates.

**Note:** For existing services, use `connect-service.sh` instead.

### cleanup.sh
**Clean up resources**

```bash
./cleanup.sh
```

Removes:
- Docker containers
- Networks
- Volumes
- Build cache

### test.sh
**Test all services**

```bash
./test.sh
```

Checks:
- Service health endpoints
- Traefik routing
- SSL certificates
- Dependencies

## Library Functions

### lib/service-detector.sh
**Service auto-detection library**

Functions:
- `detect_language()` - Detect Python, Node.js, Go, Rust
- `detect_python_service()` - Identify FastAPI, Flask, Django
- `detect_node_service()` - Identify Express, NestJS, Next.js
- `extract_port_python()` - Find Python service port
- `extract_port_node()` - Find Node.js service port
- `find_python_entrypoint()` - Locate main.py, app.py, etc.
- `find_node_entrypoint()` - Locate index.js, app.js, etc.
- `detect_mongodb_dependency()` - Check for MongoDB usage
- `detect_postgres_dependency()` - Check for PostgreSQL usage
- `detect_redis_dependency()` - Check for Redis usage
- `generate_service_metadata()` - Generate complete metadata JSON

### lib/docker-generator.sh
**Docker configuration generator**

Functions:
- `generate_dockerfile()` - Create framework-specific Dockerfile
- `generate_dockerfile_fastapi()` - FastAPI Dockerfile
- `generate_dockerfile_flask()` - Flask Dockerfile
- `generate_dockerfile_django()` - Django Dockerfile
- `generate_dockerfile_express()` - Express Dockerfile
- `generate_dockerfile_nestjs()` - NestJS Dockerfile
- `generate_dockerfile_nextjs()` - Next.js Dockerfile
- `generate_dockerignore_python()` - Python .dockerignore
- `generate_dockerignore_node()` - Node.js .dockerignore
- `generate_compose_service()` - docker-compose service definition

## Usage Examples

### Example 1: Connect FastAPI Service

```bash
# You have a FastAPI project at ~/projects/todo-api
./connect-service.sh ~/projects/todo-api

# Output:
# 🔍 Analyzing service...
#   Language: python
#   Framework: fastapi
#   Port: 8000
# 🐳 Generating Dockerfile...
# 📦 Adding to docker-compose.yml...
# 🚀 Starting service...
# ✅ SUCCESS!
# 🌐 https://todo-api.localhost
```

### Example 2: Connect Express Service

```bash
./connect-service.sh ~/projects/user-service users-api
# Now at: https://users-api.localhost
```

### Example 3: Dry Run First

```bash
# Preview what will happen
./connect-service.sh ~/projects/analytics --dry-run

# Review output, then connect for real
./connect-service.sh ~/projects/analytics
```

### Example 4: Override Port

```bash
./connect-service.sh ~/projects/metrics --port 9090
```

### Example 5: Using in Other Scripts

```bash
#!/bin/bash
source ./lib/service-detector.sh
source ./lib/docker-generator.sh

# Detect service metadata
metadata=$(generate_service_metadata "/path/to/service" "my-service")
echo "$metadata"

# Generate Dockerfile
dockerfile=$(generate_dockerfile "python" "fastapi" "8000" "main.py")
echo "$dockerfile" > /path/to/service/Dockerfile
```

## Claude Code Integration

All scripts work seamlessly with Claude Code:

```
User: /connect
Claude: Guides through service connection

User: connect my FastAPI service at ~/projects/api
Claude: Runs ./connect-service.sh ~/projects/api

User: show me the logs
Claude: Runs docker compose logs -f api
```

## Requirements

- Docker & Docker Compose
- Bash 4.0+
- Python 3 (for path resolution)
- curl (for health checks)

**macOS users:** All scripts are BSD-compatible.

## Troubleshooting

### Script Permission Denied

```bash
chmod +x *.sh
chmod +x lib/*.sh
```

### Service Won't Connect

1. Check logs: `docker compose logs -f service-name`
2. Verify service has `/health` endpoint
3. Try dry run: `./connect-service.sh /path --dry-run`
4. Check Traefik dashboard: `https://traefik.localhost`

### Port Already in Use

```bash
# Override with different port
./connect-service.sh /path/to/service --port 9000
```

### Language Not Detected

Ensure your service has:
- Python: `requirements.txt` or `.py` files
- Node.js: `package.json` or `.js` files

## Contributing

Want to add support for more languages/frameworks?

1. Add detection to `lib/service-detector.sh`
2. Add Dockerfile generator to `lib/docker-generator.sh`
3. Test with real services
4. Submit PR!

## See Also

- [QUICKSTART.md](../QUICKSTART.md) - Quick reference
- [Service Auto-Connect Guide](../docs/guides/service-auto-connect.md) - Complete documentation
- [CLAUDE.md](../CLAUDE.md) - Project guide for AI assistants

---

**Need help?** Ask Claude with `/connect` or check the [documentation](../docs/guides/service-auto-connect.md).
