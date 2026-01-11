#!/bin/bash
set -e

echo "🚀 Setting up Traefik Local Development Environment"

# Check prerequisites
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

# Create .env if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env file from .env.example..."
    cp .env.example .env
    echo "✅ .env file created"
else
    echo "⚠️  .env file already exists, skipping..."
fi

# Create certs directory
mkdir -p certs

# Install mkcert CA
echo "Installing mkcert CA..."
mkcert -install

# Generate certificates
echo "Generating SSL certificates..."
mkcert -key-file certs/key.pem -cert-file certs/cert.pem "*.localhost" localhost 127.0.0.1 ::1

echo "✅ SSL certificates generated"

# Create Docker network
echo "Creating Docker network..."
docker network create traefik 2>/dev/null || echo "⚠️  Network 'traefik' already exists"

# Start services
echo "Starting services..."
docker compose up -d

# Wait for services to be healthy
echo "Waiting for services to be ready..."
sleep 10

# Check service status
echo ""
echo "📊 Service Status:"
docker compose ps

echo ""
echo "✅ Setup complete!"
echo ""
echo "🌐 Access your services at:"
echo "   - Traefik Dashboard: https://traefik.localhost"
echo "   - Python API: https://api.localhost"
echo "   - Node Web: https://web.localhost"
echo ""
echo "📝 Useful commands:"
echo "   - View logs: docker compose logs -f"
echo "   - Stop services: docker compose down"
echo "   - Restart service: docker compose restart <service-name>"
