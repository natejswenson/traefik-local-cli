#!/bin/bash
# Inspect or repair this Mac's existing dnsmasq integration. No new LAN policy.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:---check}"
case "$mode" in
    --help|-h)
        echo "Usage: setup-dns.sh [--check|--apply]"
        echo "Default: read-only checks. --apply repairs local resolvers and restarts configured dnsmasq."
        exit 0 ;;
    --check|--apply) ;;
    *) echo "Unknown option: $mode" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo "Expected one option" >&2; exit 2; }
[ "$(uname -s)" = Darwin ] || { echo "This helper is for macOS resolvers." >&2; exit 1; }
command -v brew >/dev/null || { echo "Homebrew is required for this dnsmasq setup." >&2; exit 1; }
command -v dig >/dev/null || { echo "dig is required to verify the DNS server." >&2; exit 1; }
brew_bin=$(command -v brew)
dns_config="$(brew --prefix)/etc/dnsmasq.conf"
# Reuse the existing address configuration rather than guessing a LAN address.
if ! grep -Eq '^address=/\.?internal/' "$dns_config" ||
   ! grep -Eq '^address=/\.?home\.local/' "$dns_config"; then
    echo "Configure address=/internal/IP and address=/home.local/IP in $dns_config first." >&2
    exit 1
fi

if [ "$mode" = --apply ]; then
    # Never hang a Codex subprocess waiting for a password it cannot supply.
    if [ -t 0 ]; then
        sudo -v
    elif ! sudo -n true 2>/dev/null; then
        echo "Administrator authentication required. Run this in a local Terminal:" >&2
        echo "  $SCRIPT_DIR/setup-dns.sh --apply" >&2
        exit 1
    fi
    restart_dns=false
    # dnsmasq >= 2.86 forwards non-A queries upstream unless these private
    # zones are explicitly local. Failed AAAA lookups stall macOS clients.
    backed_up=false
    for suffix in internal home.local; do
        if ! grep -Fxq "local=/$suffix/" "$dns_config" && ! grep -Fxq "server=/$suffix/" "$dns_config"; then
            if [ "$backed_up" = false ]; then
                sudo cp "$dns_config" "$dns_config.tk-backup"
                backed_up=true
            fi
            printf '\nlocal=/%s/\n' "$suffix" | sudo tee -a "$dns_config" >/dev/null
            restart_dns=true
        fi
    done
    sudo mkdir -p /etc/resolver
    for suffix in internal home.local; do
        resolver="/etc/resolver/$suffix"
        if ! grep -Eq '^nameserver[[:space:]]+127\.0\.0\.1[[:space:]]*$' "$resolver" 2>/dev/null; then
            if [ -f "$resolver" ]; then
                sudo cp "$resolver" "$resolver.tk-backup"
            fi
            printf 'nameserver 127.0.0.1\n' | sudo tee "$resolver" >/dev/null
        fi
    done
    # A launchd-managed dnsmasq can be healthy even when user-level brew
    # services reports "none". Do not replace/restart a responding server.
    for suffix in internal home.local; do
        answer=$(dig +time=2 +tries=1 +short @127.0.0.1 "traefik.$suffix" A 2>/dev/null) || answer=""
        [[ "$answer" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || restart_dns=true
    done
    if [ "$restart_dns" = true ]; then
        sudo "$(brew --prefix)/opt/dnsmasq/sbin/dnsmasq" --test --conf-file="$dns_config"
        sudo "$brew_bin" services restart dnsmasq
    fi
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
fi

failed=0
for suffix in internal home.local; do
    if grep -Eq '^nameserver[[:space:]]+127\.0\.0\.1[[:space:]]*$' "/etc/resolver/$suffix" 2>/dev/null; then
        echo "OK resolver: $suffix"
    else
        echo "FAIL resolver: /etc/resolver/$suffix is missing or does not use 127.0.0.1"
        failed=1
    fi
    # launchd may report "started" before dnsmasq accepts its first query.
    # Retry only after applying a repair; read-only checks remain immediate.
    for query_attempt in 1 2 3; do
        answer=$(dig +time=2 +tries=1 +short @127.0.0.1 "traefik.$suffix" A 2>/dev/null) || answer=""
        [[ "$answer" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
        [ "$mode" = --check ] && break
        [ "$query_attempt" -eq 3 ] || sleep 1
    done
    if [[ "$answer" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "OK dnsmasq answer: traefik.$suffix -> $answer"
    else
        echo "FAIL dnsmasq: no local A answer for traefik.$suffix"
        failed=1
    fi
    response=$(dig +time=2 +tries=1 +noall +comments @127.0.0.1 "traefik.$suffix" AAAA 2>/dev/null) || response=""
    if [[ "$response" == *"status: NOERROR"* ]]; then
        echo "OK dnsmasq AAAA: $suffix returns a valid answer (possibly empty)"
    else
        echo "FAIL dnsmasq AAAA: $suffix must be local; configure local=/$suffix/"
        failed=1
    fi
done
[ "$failed" -eq 0 ] || exit 1
# Use the system resolver and verified TLS, not nslookup or curl -k.
exec "$SCRIPT_DIR/tk" doctor --probe
