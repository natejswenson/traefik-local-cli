#!/bin/bash
#==============================================================================
# DNS Setup Script for *.home.local domains
#==============================================================================
# This script configures dnsmasq and macOS resolver to resolve all
# *.home.local domains to your local machine (192.168.1.29)
#
# What this script does:
# 1. Creates macOS resolver configuration for home.local domain
# 2. Ensures dnsmasq service is running
# 3. Flushes DNS cache to apply changes
#
# Prerequisites:
# - dnsmasq already installed via Homebrew
# - dnsmasq.conf already configured with: address=/.home.local/192.168.1.29
#----------------------------------------------------

set -e  # Exit on any error

echo "🔧 Configuring DNS resolution for *.home.local domains..."
echo ""

# Check if dnsmasq is installed
if ! brew list dnsmasq &>/dev/null; then
    echo "❌ Error: dnsmasq is not installed"
    echo "Install it with: brew install dnsmasq"
    exit 1
fi

echo "✓ dnsmasq is installed"

# Create resolver directory
echo "Creating /etc/resolver directory..."
sudo mkdir -p /etc/resolver

# Configure macOS to use dnsmasq for .home.local domains
echo "Configuring macOS resolver for home.local domain..."
echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/home.local > /dev/null

# Start/restart dnsmasq
echo "Starting dnsmasq service..."
sudo brew services restart dnsmasq

# Wait a moment for service to start
sleep 2

# Flush DNS cache
echo "Flushing DNS cache..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "✅ DNS configuration complete!"
echo ""
echo "Testing DNS resolution..."
echo "------------------------"

# Test DNS resolution
echo "Testing api.home.local:"
nslookup api.home.local | grep "Address:" | tail -1

echo ""
echo "Testing web.home.local:"
nslookup web.home.local | grep -A 1 "Name:" | tail -1

echo ""
echo "Your *.home.local domains should now resolve to 192.168.1.29"
echo "Traefik is listening on ports 80 and 443 on that IP"
