#!/usr/bin/env bats
# Unit tests for lib/docker-generator.sh — default (dev) vs --harden (production) output.
# Uses glob ([[ == *..* ]]) matches, not the regex-based assert_output_contains, because
# the patterns here contain regex-special characters (*.db, ${...}).

load '../test_helper'

setup() {
    source "${SCRIPTS_DIR}/lib/docker-generator.sh"
}

teardown() {
    unset HARDEN
}

has()    { [[ "$output" == *"$1"* ]] || { echo "MISSING: $1"; echo "$output"; return 1; }; }
hasnot() { [[ "$output" != *"$1"* ]] || { echo "UNEXPECTED: $1"; echo "$output"; return 1; }; }

# --- Default mode is unchanged (backward compatibility) ----------------------

@test "default fastapi Dockerfile uses dev auto-reload and runs as root" {
    export HARDEN=false
    run generate_dockerfile python fastapi 8000 main.py
    assert_success
    has "--reload"
    hasnot "USER app"
    has "python:3.11-slim"
}

@test "default compose keeps source bind-mount and ENV=development" {
    export HARDEN=false
    run generate_compose_service notes ./../notes 8000 python false false false
    assert_success
    has "ENV=development"
    has "/app:delegated"
    hasnot "cap_drop"
    hasnot "API_TOKEN"
}

@test "default python .dockerignore does NOT exclude data" {
    export HARDEN=false
    run generate_dockerignore_python
    assert_success
    hasnot "*.db"
}

# --- Hardened mode --------------------------------------------------------------

@test "hardened fastapi Dockerfile is non-root, no reload, chowned copy" {
    export HARDEN=true
    run generate_dockerfile python fastapi 8000 main.py
    assert_success
    has "useradd --create-home --uid 1001 app"
    has "USER app"
    has "COPY --chown=app:app"
    has "HEALTHCHECK"
    hasnot "--reload"
}

@test "hardened express Dockerfile is non-root and omits dev deps" {
    export HARDEN=true
    run generate_dockerfile node express 3000 index.js
    assert_success
    has "USER app"
    has "npm ci --omit=dev"
    hasnot "npm run dev"
}

@test "hardened python .dockerignore excludes data + secrets" {
    export HARDEN=true
    run generate_dockerignore_python
    assert_success
    has "data/"
    has "*.db"
    has "*.sqlite"
    has "*.ofx"
}

@test "hardened compose has cap_drop, no-new-privileges, prod env, wired token" {
    export HARDEN=true
    run generate_compose_service my-api ./../my-api 8000 python false false false
    assert_success
    has "no-new-privileges:true"
    has "cap_drop"
    has "ENV=production"
    has 'MY_API_API_TOKEN=${MY_API_API_TOKEN}'   # name uppercased, - -> _
}

@test "hardened compose drops the source bind-mount and empty volumes key" {
    export HARDEN=true
    run generate_compose_service notes ./../notes 8000 python false false false
    assert_success
    hasnot "/app:delegated"
    hasnot "volumes:"
}

@test "hardened compose publishes no host port and mounts no docker socket" {
    export HARDEN=true
    run generate_compose_service notes ./../notes 8000 python false false false
    assert_success
    hasnot "ports:"
    hasnot "docker.sock"
}
