#!/bin/bash
# Refresh the existing local CA's certificate, including concrete routed names.
# This does not install a CA or restart services. Run setup.sh for initial trust.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${TRAEFIK_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
cd "$PROJECT_ROOT"
command -v mkcert >/dev/null || { echo "mkcert is required" >&2; exit 1; }

# SecureTransport clients can reject a wildcard directly beneath a private TLD.
# Keep wildcard compatibility and include every current literal Host name.
inventory=$(python3 "$SCRIPT_DIR/lib/tk-inspect.py" --project-directory "$PROJECT_ROOT" list --json)
hosts=$(python3 -c 'import json,sys; from urllib.parse import urlsplit
print("\n".join(sorted({urlsplit(url).hostname for row in json.load(sys.stdin)["services"] for url in row["urls"]})))' <<< "$inventory")
domains=("*.internal" "*.home.local" internal home.local localhost 127.0.0.1 ::1)
while IFS= read -r host; do
    [ -z "$host" ] || domains+=("$host")
done <<< "$hosts"

mkdir -p certs
staging=$(mktemp -d "$PROJECT_ROOT/certs/.renew.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkcert -key-file "$staging/key.pem" -cert-file "$staging/cert.pem" "${domains[@]}"
chmod 600 "$staging/key.pem"
chmod 644 "$staging/cert.pem"
# Preserve the prior pair for rollback without copying the private CA key.
if [ -f certs/key.pem ] && [ -f certs/cert.pem ]; then
    cp certs/key.pem certs/key.pem.previous
    chmod 600 certs/key.pem.previous
    cp certs/cert.pem certs/cert.pem.previous
fi
mv "$staging/key.pem" certs/key.pem
mv "$staging/cert.pem" certs/cert.pem
echo "Certificate refreshed. Reload Traefik to use it: docker compose restart traefik"
