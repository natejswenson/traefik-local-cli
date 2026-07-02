#!/bin/bash
#==============================================================================
# Traefik Setup Script
#==============================================================================
# Purpose: Initial setup of the Traefik local development environment
# Usage:   ./setup.sh  (run from the project root, or via `tk setup`)
#
# This script will:
#   - Verify docker and mkcert are installed
#   - Create .env from .env.example if missing
#   - Generate a *.internal / *.home.local wildcard certificate
#   - Create the external `traefik` Docker network (idempotent)
#   - Bring up the compose stack
#   - Print the resolved URL for every currently-configured service
#
# Safe to run more than once — every step is idempotent.
#==============================================================================

set -euo pipefail

echo "🚀 Setting up Traefik Local Development Environment"

# 1. Prerequisites
echo "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v mkcert &> /dev/null; then
    echo "❌ mkcert is not installed. Please install mkcert first."
    echo "   macOS: brew install mkcert"
    echo "   Linux: https://github.com/FiloSottile/mkcert#installation"
    exit 1
fi

echo "✅ Prerequisites installed"

# 2. .env from .env.example if missing
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        echo "Creating .env file from .env.example..."
        cp .env.example .env
        echo "✅ .env file created"
    else
        echo "⚠️  .env.example not found, skipping .env creation"
    fi
else
    echo "⚠️  .env file already exists, skipping..."
fi

# 3. Certs directory + mkcert CA
mkdir -p certs

echo "Installing mkcert CA (this may prompt for a system keychain-trust approval)..."
mkcert -install

# 4. Wildcard certificate for *.internal (current) and *.home.local (legacy alias)
echo "Generating SSL certificates..."
mkcert -key-file certs/key.pem -cert-file certs/cert.pem \
    "*.internal" "*.home.local" internal home.local localhost 127.0.0.1 ::1

echo "✅ SSL certificates generated"

# 5. Docker network (idempotent — a second run must not fail here)
echo "Creating Docker network..."
docker network create traefik 2>/dev/null || echo "⚠️  Network 'traefik' already exists"

# 6. Bring up the stack
echo "Starting services..."
docker compose up -d

echo "Waiting for services to be ready..."
sleep 10

echo ""
echo "📊 Service Status:"
docker compose ps

# 7. Print URLs for every currently-configured service (not a hardcoded list) —
# derive them from the resolved compose config, the same technique `tk status`/
# `tk list` use, so this list never drifts as services are added/removed.
echo ""
echo "✅ Setup complete!"
echo ""
echo "🌐 Access your services at:"
docker compose config --format json 2>/dev/null | python3 -c '
import json, re, sys

data = json.load(sys.stdin)
services = data.get("services", {})

for name, svc in sorted(services.items()):
    labels = svc.get("labels", {})
    if isinstance(labels, list):
        labels = dict(item.split("=", 1) for item in labels if "=" in item)

    if str(labels.get("traefik.enable", "")).lower() == "false":
        continue

    rule = None
    for key, value in labels.items():
        if key.startswith("traefik.http.routers.") and key.endswith(".rule"):
            rule = value
            break
    if not rule:
        continue

    hosts = re.findall(r"Host\(`([^`]+)`\)", rule)
    if not hosts:
        continue

    internal_hosts = [h for h in hosts if h.endswith(".internal")]
    primary = internal_hosts[0] if internal_hosts else hosts[0]
    print(f"   - {name}: https://{primary}")
'

echo ""
echo "📝 Useful commands:"
echo "   - View logs: docker compose logs -f"
echo "   - Stop services: docker compose down"
echo "   - Restart service: docker compose restart <service-name>"
