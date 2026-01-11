#!/bin/bash
set -e

echo "🧪 Testing Traefik Setup"

# Test 1: Traefik is running
echo "Test 1: Checking if Traefik is running..."
if docker compose ps traefik | grep -q "Up"; then
    echo "✅ Traefik is running"
else
    echo "❌ Traefik is not running"
    exit 1
fi

# Test 2: Services are healthy
echo "Test 2: Checking service health..."
for service in traefik python-api node-web; do
    if docker compose ps $service | grep -q "healthy\|Up"; then
        echo "✅ $service is healthy"
    else
        echo "❌ $service is not healthy"
        exit 1
    fi
done

# Test 3: HTTPS endpoints respond
echo "Test 3: Testing HTTPS endpoints..."
endpoints=(
    "https://traefik.localhost/api/overview"
    "https://api.localhost/health"
    "https://web.localhost/health"
)

for endpoint in "${endpoints[@]}"; do
    if curl -k -s -f -o /dev/null "$endpoint"; then
        echo "✅ $endpoint is accessible"
    else
        echo "❌ $endpoint is not accessible"
        exit 1
    fi
done

# Test 4: HTTP redirects to HTTPS
echo "Test 4: Testing HTTP to HTTPS redirect..."
if curl -s -o /dev/null -w "%{http_code}" http://api.localhost | grep -q "30"; then
    echo "✅ HTTP redirects to HTTPS"
else
    echo "❌ HTTP does not redirect to HTTPS"
    exit 1
fi

echo ""
echo "✅ All tests passed!"
