#!/usr/bin/env bats
# Integration tests for setup.sh (restored per the tk skill design, docs/plans/2026-07-01-tk-cli-skill-design.md)
#
# Runs setup.sh against an isolated scratch project so it never touches the
# real stack's docker-compose.yml/.env/certs. mkcert is stubbed out (via a
# fake binary prepended to PATH) so the test never triggers a real system
# keychain-trust dialog and never mutates the real mkcert CA store.

load '../test_helper'

SETUP_TEST_DIR="/tmp/tk-setup-test-$$"

setup() {
    skip_if_no_docker

    rm -rf "$SETUP_TEST_DIR"
    mkdir -p "$SETUP_TEST_DIR/bin"

    # Stub mkcert: never touches the real CA store, never pops a GUI dialog.
    cat > "$SETUP_TEST_DIR/bin/mkcert" <<'EOF'
#!/bin/bash
keyfile=""
certfile=""
while [ $# -gt 0 ]; do
    case "$1" in
        -install)
            echo "mock mkcert: CA already installed"
            exit 0
            ;;
        -CAROOT)
            echo "/tmp/mock-caroot"
            exit 0
            ;;
        -key-file)
            keyfile="$2"
            shift 2
            ;;
        -cert-file)
            certfile="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
if [ -n "$keyfile" ] && [ -n "$certfile" ]; then
    mkdir -p "$(dirname "$keyfile")" "$(dirname "$certfile")"
    echo "mock-key" > "$keyfile"
    echo "mock-cert" > "$certfile"
    echo "mock mkcert: certificate generated"
fi
EOF
    chmod +x "$SETUP_TEST_DIR/bin/mkcert"
    export PATH="$SETUP_TEST_DIR/bin:$PATH"

    # Minimal scratch docker-compose.yml. No host `ports:` bindings, so this
    # never conflicts with a real stack's traefik already bound to 80/443;
    # attaching to the shared external `traefik` network is harmless.
    cat > "$SETUP_TEST_DIR/docker-compose.yml" <<'EOF'
services:
  tk-setup-test-svc:
    image: nginx:alpine
    container_name: tk-setup-test-svc
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.tk-setup-test-svc.rule=Host(`tk-setup-test.internal`)"
      - "traefik.http.routers.tk-setup-test-svc.entrypoints=websecure"
      - "traefik.http.routers.tk-setup-test-svc.tls=true"
      - "traefik.http.services.tk-setup-test-svc.loadbalancer.server.port=80"
    networks:
      - traefik

networks:
  traefik:
    external: true
EOF

    cat > "$SETUP_TEST_DIR/.env.example" <<'EOF'
EXAMPLE_VAR=example-value
EOF

    cd "$SETUP_TEST_DIR"
}

teardown() {
    # Never remove the shared external `traefik` network here — it's the
    # real stack's network, not something this test owns.
    (cd "$SETUP_TEST_DIR" && docker compose down -v 2>/dev/null) || true
    rm -rf "$SETUP_TEST_DIR"
}

@test "setup.sh exists and is executable" {
    assert_file_exists "${SCRIPTS_DIR}/setup.sh"
    [ -x "${SCRIPTS_DIR}/setup.sh" ]
}

@test "setup.sh creates .env, generates certs, brings up the stack, and prints derived URLs" {
    run "${SCRIPTS_DIR}/setup.sh"
    assert_success

    assert_file_exists "$SETUP_TEST_DIR/.env"
    assert_file_contains "$SETUP_TEST_DIR/.env" "EXAMPLE_VAR"

    assert_file_exists "$SETUP_TEST_DIR/certs/key.pem"
    assert_file_exists "$SETUP_TEST_DIR/certs/cert.pem"

    # URL derived from the resolved compose config, not a hardcoded/synthesized name.
    assert_output_contains "tk-setup-test.internal"
}

@test "setup.sh does not overwrite an existing .env" {
    echo "SENTINEL=do-not-clobber" > "$SETUP_TEST_DIR/.env"

    run "${SCRIPTS_DIR}/setup.sh"
    assert_success

    assert_file_contains "$SETUP_TEST_DIR/.env" "SENTINEL=do-not-clobber"
}

@test "running setup.sh twice in a row exits 0 both times (idempotent network guard)" {
    run "${SCRIPTS_DIR}/setup.sh"
    assert_success

    run "${SCRIPTS_DIR}/setup.sh"
    assert_success
}
