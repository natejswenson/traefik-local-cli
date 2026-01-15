#!/usr/bin/env bash
#
# tk-security.sh - Security functions for Traefik CLI
#
# Provides:
# - Secure temporary file handling
# - Docker socket security validation
# - Docker image and compose security checks
# - Command safety validation
#

# Prevent double-loading
[[ -n "${TK_SECURITY_LOADED:-}" ]] && return 0
TK_SECURITY_LOADED=1

# ============================================================================
# Secure Temporary File Handling
# ============================================================================

# Secure temporary directory
SECURE_TMP_DIR=""

setup_secure_tmp() {
  # Create secure temporary directory
  SECURE_TMP_DIR=$(mktemp -d -t tk.XXXXXXXXXX) || {
    log_fatal "Failed to create secure temporary directory"
  }

  # Set restrictive permissions (owner only)
  chmod 700 "$SECURE_TMP_DIR" || {
    log_fatal "Failed to set permissions on temporary directory"
  }

  log_debug "Created secure temporary directory: $SECURE_TMP_DIR"

  # Register cleanup
  trap cleanup_secure_tmp EXIT INT TERM
}

cleanup_secure_tmp() {
  if [[ -n "$SECURE_TMP_DIR" ]] && [[ -d "$SECURE_TMP_DIR" ]]; then
    log_debug "Cleaning up temporary directory: $SECURE_TMP_DIR"

    # Securely wipe sensitive files before removal if shred is available
    if command -v shred >/dev/null 2>&1; then
      find "$SECURE_TMP_DIR" -type f -exec shred -u {} \; 2>/dev/null || true
    fi

    # Remove directory
    rm -rf "$SECURE_TMP_DIR" 2>/dev/null || true
  fi
}

create_secure_tempfile() {
  local prefix=${1:-"tk"}

  if [[ -z "$SECURE_TMP_DIR" ]]; then
    setup_secure_tmp
  fi

  local tempfile=$(mktemp "$SECURE_TMP_DIR/${prefix}.XXXXXXXXXX") || {
    log_fatal "Failed to create secure temporary file"
  }

  # Set restrictive permissions
  chmod 600 "$tempfile"

  echo "$tempfile"
}

write_secure_file() {
  local filepath=$1
  local content=$2
  local permissions=${3:-600}

  # Validate path is safe
  validate_path_safe "$filepath" "output file" || return 1

  # Write atomically using temporary file
  local tempfile=$(create_secure_tempfile "write")

  echo "$content" > "$tempfile" || {
    log_error "Failed to write to temporary file"
    return 1
  }

  # Set permissions before moving
  chmod "$permissions" "$tempfile" || {
    log_error "Failed to set permissions"
    return 1
  }

  # Atomic move
  mv "$tempfile" "$filepath" || {
    log_error "Failed to move file to destination"
    return 1
  }

  log_debug "Securely wrote file: $filepath"
  return 0
}

# ============================================================================
# Docker Security Functions
# ============================================================================

validate_docker_socket_safe() {
  local docker_socket="/var/run/docker.sock"

  # Check if Docker socket exists
  if [[ ! -S "$docker_socket" ]]; then
    log_error "Docker socket not found at $docker_socket"
    return 1
  fi

  # Check if we can access it
  if [[ ! -r "$docker_socket" ]] || [[ ! -w "$docker_socket" ]]; then
    log_error "Cannot access Docker socket (insufficient permissions)"
    log_info "You may need to add your user to the docker group: sudo usermod -aG docker \$USER"
    return 1
  fi

  # Check socket permissions (should not be world-writable)
  local perms
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    perms=$(stat -f "%Lp" "$docker_socket" 2>/dev/null)
  else
    # Linux
    perms=$(stat -c "%a" "$docker_socket" 2>/dev/null)
  fi

  if [[ "$perms" =~ [2367]$ ]]; then
    log_warn "Docker socket has overly permissive permissions: $perms"
    log_warn "This is a security risk. Recommended: 660"
  fi

  return 0
}

validate_docker_image_safe() {
  local image=$1

  # Block pulling from untrusted registries by default
  local trusted_registries=("docker.io" "gcr.io" "ghcr.io" "")
  local image_registry=""

  # Extract registry from image name
  if [[ "$image" == *"/"* ]]; then
    image_registry=$(echo "$image" | cut -d'/' -f1)
  fi

  # If image has no registry prefix, it's from Docker Hub (trusted)
  if [[ -z "$image_registry" ]] || [[ "$image" != *"."* ]]; then
    return 0
  fi

  local registry_trusted=false
  for registry in "${trusted_registries[@]}"; do
    if [[ "$image_registry" == "$registry" ]] || [[ -z "$registry" ]]; then
      registry_trusted=true
      break
    fi
  done

  if [[ "$registry_trusted" == "false" ]]; then
    log_warn "Using image from untrusted registry: $image_registry"
    if [[ "${ALLOW_UNTRUSTED_REGISTRIES:-false}" != "true" ]]; then
      log_error "Untrusted registry blocked. Set ALLOW_UNTRUSTED_REGISTRIES=true to override"
      return 1
    fi
  fi

  return 0
}

validate_docker_compose_safe() {
  local compose_file=$1

  if [[ ! -f "$compose_file" ]]; then
    log_error "Docker Compose file not found: $compose_file"
    return 1
  fi

  # Check for dangerous Docker Compose configurations
  local dangerous_patterns=(
    "privileged.*true"
    "cap_add.*SYS_ADMIN"
    "cap_add.*NET_ADMIN"
    "network_mode.*host"
    "pid.*host"
    "ipc.*host"
  )

  local issues_found=false

  for pattern in "${dangerous_patterns[@]}"; do
    if grep -Eq "$pattern" "$compose_file" 2>/dev/null; then
      log_warn "Potentially dangerous configuration detected: $pattern"
      issues_found=true
    fi
  done

  # Check for Docker socket mounting (high risk)
  if grep -q "/var/run/docker.sock" "$compose_file" 2>/dev/null; then
    log_warn "Docker socket mounted in container - HIGH SECURITY RISK"
    issues_found=true
  fi

  if [[ "$issues_found" == "true" ]]; then
    log_warn "Review the compose file for security implications"

    if [[ "${STRICT_DOCKER_SECURITY:-true}" == "true" ]]; then
      log_error "Dangerous configurations blocked by STRICT_DOCKER_SECURITY=true"
      log_info "Set STRICT_DOCKER_SECURITY=false to override (not recommended)"
      return 1
    fi
  fi

  return 0
}

# Wrapper for docker commands with validation
docker_exec_safe() {
  local operation=$1
  shift
  local command=("$@")

  # Validate Docker is accessible
  validate_docker_socket_safe || return 1

  # Validate command doesn't contain injection attempts
  validate_command_safe "${command[*]}" || return 1

  log_debug "Executing Docker command: $operation"

  # Execute with error handling
  if ! "${command[@]}"; then
    log_error "Docker command failed: $operation"
    return 1
  fi

  return 0
}

# ============================================================================
# Command Safety Validation
# ============================================================================

# Blocked dangerous commands
readonly BLOCKED_COMMANDS=(
  'rm -rf /'
  'dd if='
  'mkfs'
  ':(){:|:&};:'
  'chmod 777'
  'chmod -R 777'
)

validate_command_safe() {
  local command=$1

  # Check for dangerous commands
  for blocked_cmd in "${BLOCKED_COMMANDS[@]}"; do
    if [[ "$command" == *"$blocked_cmd"* ]]; then
      log_fatal "Blocked dangerous command detected: $blocked_cmd"
    fi
  done

  # Check for command chaining attempts
  if [[ "$command" =~ (\||;|\&|\$\(|\`|\\n|\\r) ]]; then
    log_error "Command chaining detected and blocked"
    return 1
  fi

  return 0
}

# Sanitize output for logging (remove secrets)
sanitize_for_logging() {
  local input=$1

  # Remove or mask sensitive patterns
  local sanitized="$input"

  # Mask passwords and tokens
  sanitized=$(echo "$sanitized" | sed -E 's/(password|passwd|pwd|token|secret|key|api[_-]?key)=[^ ]*/\1=***REDACTED***/gi')

  # Mask environment variables that might contain secrets
  sanitized=$(echo "$sanitized" | sed -E 's/(MONGO|POSTGRES|REDIS|DATABASE|DB|API|AUTH)_[A-Z_]*=([^ ]+)/\1_***=***REDACTED***/g')

  # Limit length for logging
  if [[ ${#sanitized} -gt 1000 ]]; then
    sanitized="${sanitized:0:1000}... (truncated)"
  fi

  echo "$sanitized"
}

# Export functions
export -f setup_secure_tmp
export -f cleanup_secure_tmp
export -f create_secure_tempfile
export -f write_secure_file
export -f validate_docker_socket_safe
export -f validate_docker_image_safe
export -f validate_docker_compose_safe
export -f docker_exec_safe
export -f validate_command_safe
export -f sanitize_for_logging
