#!/bin/bash
#==============================================================================
# DNS Setup Script for macOS
#==============================================================================
# Purpose: Configure local DNS resolution for *.internal domains
# Usage:   ./setup-dns.sh
#
# Requirements:
#   - macOS operating system
#   - dnsmasq installed (brew install dnsmasq)
#   - sudo privileges
#
# This script will:
#   - Create macOS resolver configuration for .internal
#   - Configure nameserver to use localhost
#   - Restart dnsmasq service
#   - Flush DNS cache
#   - Verify DNS resolution
#
# Note: This is macOS-specific. For other systems, configure DNS differently.
#==============================================================================

set -e

echo "🔧 Fixing DNS resolution for *.internal domains"
echo "=================================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Step 1: Creating macOS resolver configuration${NC}"
sudo mkdir -p /etc/resolver
echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/internal
echo -e "${GREEN}✓ Resolver configuration created${NC}"
echo ""

echo -e "${YELLOW}Step 2: Restarting dnsmasq service${NC}"
sudo brew services restart dnsmasq
sleep 2
echo -e "${GREEN}✓ dnsmasq restarted${NC}"
echo ""

echo -e "${YELLOW}Step 3: Flushing DNS cache${NC}"
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo -e "${GREEN}✓ DNS cache flushed${NC}"
echo ""

echo "=================================================="
echo "✅ DNS configuration complete!"
echo ""
echo "Testing DNS resolution..."
echo ""

# Test DNS resolution
echo "Testing api.internal:"
nslookup api.internal | grep -A 1 "Name:" || echo "DNS lookup failed"
echo ""

echo "Testing services (use -k to skip cert verification for self-signed certs):"
echo ""

# Test each service
declare -a services=(
    "https://traefik.internal"
    "https://api.internal/health"
    "https://web.internal/health"
    "https://ralph-test.internal/health"
    "https://salon.internal"
)

for url in "${services[@]}"; do
    echo -n "Testing ${url}... "
    if curl -s -k -o /dev/null -w "%{http_code}" --connect-timeout 3 "$url" | grep -q "^[23]"; then
        echo -e "${GREEN}✓ OK${NC}"
    else
        echo -e "⚠️  Check logs: docker compose logs"
    fi
done

echo ""
echo "=================================================="
echo "Your services should now be accessible at:"
echo "  - Traefik Dashboard: https://traefik.internal"
echo "  - Python API: https://api.internal"
echo "  - Python API Docs: https://api.internal/docs"
echo "  - Node Web: https://web.internal"
echo "  - Ralph Test: https://ralph-test.internal"
echo "  - Salon: https://salon.internal"
echo ""
echo "Note: Your browser may warn about self-signed certificates."
echo "This is normal for local development. Click 'Advanced' and proceed."
