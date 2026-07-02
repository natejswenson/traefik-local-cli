#!/usr/bin/env bats
# Unit tests for tk-docker.sh

load '../test_helper'

setup() {
    setup_test_project
    cd "$TEST_PROJECT_DIR"
    source "${SCRIPTS_DIR}/lib/tk-logging.sh"
    source "${SCRIPTS_DIR}/lib/tk-docker.sh"
}

teardown() {
    cleanup_test_project
}

@test "service_exists returns success for existing service" {
    run service_exists "traefik" "$TEST_COMPOSE_FILE"
    assert_success
}

@test "service_exists returns failure for non-existent service" {
    run service_exists "non-existent-service" "$TEST_COMPOSE_FILE"
    assert_failure
}

@test "get_service_domain extracts the exact domain from a single Host() clause" {
    skip_if_no_docker
    run get_service_domain "test-service" "$TEST_COMPOSE_FILE"
    assert_success
    assert_output_equals "test.localhost"
}

@test "get_service_domain prefers the .internal host when a rule has two OR'd Host() clauses" {
    skip_if_no_docker
    cat > "$TEST_COMPOSE_FILE" <<'EOF'
version: '3.8'

services:
  dual-domain-service:
    image: nginx:alpine
    container_name: dual-domain-service
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dual-domain-service.rule=Host(`dual.internal`) || Host(`dual.home.local`)"
    networks:
      - traefik

networks:
  traefik:
    name: traefik-test
    driver: bridge
EOF
    run get_service_domain "dual-domain-service" "$TEST_COMPOSE_FILE"
    assert_success
    assert_output_equals "dual.internal"
}

@test "get_service_domain returns empty for a service with no router rule" {
    skip_if_no_docker
    cat > "$TEST_COMPOSE_FILE" <<'EOF'
version: '3.8'

services:
  no-router-service:
    image: mongo:7
    container_name: no-router-service
    labels:
      - "traefik.enable=false"
    networks:
      - traefik

networks:
  traefik:
    name: traefik-test
    driver: bridge
EOF
    run get_service_domain "no-router-service" "$TEST_COMPOSE_FILE"
    assert_success
    assert_output_equals ""
}

@test "list_all_service_hosts derives every Host() clause, including secondary aliases" {
    skip_if_no_docker
    cat > "$TEST_COMPOSE_FILE" <<'EOF'
version: '3.8'

services:
  dual-domain-service:
    image: nginx:alpine
    container_name: dual-domain-service
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dual-domain-service.rule=Host(`dual.internal`) || Host(`dual.home.local`)"
    networks:
      - traefik

networks:
  traefik:
    name: traefik-test
    driver: bridge
EOF
    run list_all_service_hosts "$TEST_COMPOSE_FILE"
    assert_success
    assert_output_contains "dual.internal"
    assert_output_contains "dual.home.local"
}

@test "list_all_service_hosts never leaks a commented-out template host" {
    skip_if_no_docker
    cat > "$TEST_COMPOSE_FILE" <<'EOF'
version: '3.8'

services:
  real-service:
    image: nginx:alpine
    container_name: real-service
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.real-service.rule=Host(`real.internal`)"
    networks:
      - traefik

networks:
  traefik:
    name: traefik-test
    driver: bridge

#----------------------------------------------------
# TEMPLATE - ADD NEW SERVICE
#----------------------------------------------------
#  service-name:
#    labels:
#      traefik.http.routers.service-name.rule: Host(`service-name.home.local`)
EOF
    run list_all_service_hosts "$TEST_COMPOSE_FILE"
    assert_success
    assert_output_contains "real.internal"
    [[ ! "$output" =~ "service-name.home.local" ]]
}

@test "list_services lists all services in compose file" {
    run list_services "$TEST_COMPOSE_FILE"
    assert_success
    assert_output_contains "traefik"
    assert_output_contains "test-service"
}

@test "list_services returns failure for non-existent compose file" {
    run list_services "/non/existent/docker-compose.yml"
    assert_failure
}

@test "find_project_root finds project root with docker-compose.yml" {
    run find_project_root
    assert_success
    [ -d "$output" ]
}

@test "find_project_root returns error outside project" {
    cd /tmp
    run find_project_root
    assert_failure
}

@test "docker_compose_cmd respects DRY_RUN flag" {
    export DRY_RUN="true"
    run docker_compose_cmd ps
    assert_success
    assert_output_contains "[DRY RUN]"
}

@test "docker_compose_cmd executes when DRY_RUN is false" {
    skip_if_no_docker
    export DRY_RUN="false"
    run docker_compose_cmd --version
    assert_success
}

@test "is_dry_run returns true when DRY_RUN=true" {
    export DRY_RUN="true"
    # is_dry_run is in tk-common.sh, not tk-docker.sh
    run bash -c 'source "${SCRIPTS_DIR}/lib/tk-common.sh" && is_dry_run'
    assert_success
}

@test "is_dry_run returns false when DRY_RUN=false" {
    export DRY_RUN="false"
    # is_dry_run is in tk-common.sh, not tk-docker.sh
    run bash -c 'source "${SCRIPTS_DIR}/lib/tk-common.sh" && is_dry_run'
    assert_failure
}
