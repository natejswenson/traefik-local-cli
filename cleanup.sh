#!/bin/bash
set -e

echo "🧹 Cleaning up Traefik development environment"

# Stop and remove containers
echo "Stopping containers..."
docker compose down -v

# Remove network
echo "Removing Docker network..."
docker network rm traefik 2>/dev/null || echo "Network already removed"

# Optional: Remove certificates (ask user)
read -p "Remove SSL certificates? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf certs/
    echo "✅ Certificates removed"
fi

# Optional: Remove .env (ask user)
read -p "Remove .env file? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f .env
    echo "✅ .env file removed"
fi

echo "✅ Cleanup complete"
