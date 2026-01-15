# Security Enhancements Specification

**Document Version**: 1.0
**Created**: 2026-01-14
**Status**: Draft
**Priority**: High
**Implementation Target**: Phase 1 (Critical) - Immediate, Phase 2 (Important) - Next Sprint, Phase 3 (Nice-to-Have) - Future

---

## Executive Summary

This specification outlines comprehensive security enhancements for two critical areas:

1. **Traefik tk CLI Tool** - Hardening the command-line interface against attacks and misuse
2. **GitHub Deployment Process** - Securing the CI/CD pipeline and repository

**Goals:**
- Prevent command injection, path traversal, and privilege escalation attacks
- Implement defense-in-depth security controls
- Ensure compliance with security best practices
- Maintain usability while improving security posture
- Enable security auditing and monitoring

---

## Table of Contents

1. [Traefik tk CLI Tool Security](#traefik-tk-cli-tool-security)
2. [GitHub Deployment Process Security](#github-deployment-process-security)
3. [Implementation Phases](#implementation-phases)
4. [Testing Requirements](#testing-requirements)
5. [Acceptance Criteria](#acceptance-criteria)
6. [Security Metrics](#security-metrics)

---

## Traefik tk CLI Tool Security

### Overview

The tk CLI tool currently has basic input validation but needs enhanced security controls to prevent attacks and ensure safe operation in multi-user and automated environments.

### Threat Model

**Threat Actors:**
- Malicious users with local access
- Compromised automated scripts
- Accidental misuse by legitimate users
- Malware executing on the system

**Attack Vectors:**
- Command injection via unsanitized inputs
- Path traversal to access/modify unauthorized files
- Docker socket abuse for privilege escalation
- Environment variable poisoning
- Temporary file race conditions
- Log injection for log tampering

### Security Enhancements

---

#### SEC-CLI-001: Enhanced Input Validation

**Priority**: Phase 1 (Critical)
**Estimated Effort**: 4 hours
**Risk Mitigated**: Command Injection, Path Traversal

**Current State:**
```bash
# lib/tk-validation.sh - Basic validation
validate_service_name() {
  local name=$1
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid service name"
    return 1
  fi
}
```

**Enhanced Implementation:**

```bash
# lib/tk-validation.sh - Enhanced validation

# Constants for validation
readonly VALID_SERVICE_NAME_REGEX='^[a-z][a-z0-9-]{0,62}$'
readonly VALID_PORT_REGEX='^[0-9]+$'
readonly VALID_DOMAIN_REGEX='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$'
readonly MAX_PATH_LENGTH=4096
readonly BLOCKED_COMMANDS=('rm -rf /' 'dd if=' 'mkfs' ':(){:|:&};:')

validate_service_name() {
  local name=$1

  # Check for empty
  if [[ -z "$name" ]]; then
    log_error "Service name cannot be empty"
    return 1
  fi

  # Check length
  if [[ ${#name} -gt 63 ]]; then
    log_error "Service name too long (max 63 characters)"
    return 1
  fi

  # Check format (must start with letter, lowercase only)
  if [[ ! "$name" =~ $VALID_SERVICE_NAME_REGEX ]]; then
    log_error "Invalid service name format. Must start with lowercase letter, contain only lowercase letters, numbers, and hyphens"
    return 1
  fi

  # Check for reserved names
  local reserved_names=("traefik" "mongodb" "postgres" "redis" "localhost" "docker" "host")
  for reserved in "${reserved_names[@]}"; do
    if [[ "$name" == "$reserved" ]]; then
      log_error "Service name '$name' is reserved"
      return 1
    fi
  done

  return 0
}

validate_path_safe() {
  local path=$1
  local context=${2:-"path"}

  # Check for empty
  if [[ -z "$path" ]]; then
    log_error "$context cannot be empty"
    return 1
  fi

  # Check length
  if [[ ${#path} -gt $MAX_PATH_LENGTH ]]; then
    log_error "$context exceeds maximum length"
    return 1
  fi

  # Get canonical path
  local canonical_path
  if ! canonical_path=$(realpath -e "$path" 2>/dev/null); then
    # Path doesn't exist yet, check parent
    local parent=$(dirname "$path")
    if [[ -d "$parent" ]]; then
      canonical_path=$(realpath -e "$parent")/$(basename "$path")
    else
      log_error "$context does not exist and parent directory is invalid"
      return 1
    fi
  fi

  # Block path traversal attempts
  if [[ "$canonical_path" =~ \.\. ]]; then
    log_error "Path traversal detected in $context"
    return 1
  fi

  # Ensure path is within allowed directories
  local allowed_dirs=(
    "$HOME"
    "/tmp"
    "/var/tmp"
    "$(find_project_root)"
  )

  local path_allowed=false
  for allowed_dir in "${allowed_dirs[@]}"; do
    if [[ "$canonical_path" == "$allowed_dir"* ]]; then
      path_allowed=true
      break
    fi
  done

  if [[ "$path_allowed" == "false" ]]; then
    log_error "$context is outside allowed directories"
    log_debug "Allowed directories: ${allowed_dirs[*]}"
    return 1
  fi

  # Block sensitive system paths
  local blocked_paths=("/etc" "/usr" "/bin" "/sbin" "/boot" "/sys" "/proc" "/root")
  for blocked in "${blocked_paths[@]}"; do
    if [[ "$canonical_path" == "$blocked"* ]]; then
      log_error "$context points to protected system directory: $blocked"
      return 1
    fi
  done

  log_debug "Path validation passed: $canonical_path"
  return 0
}

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

sanitize_for_logging() {
  local input=$1

  # Remove or mask sensitive patterns
  local sanitized="$input"

  # Mask passwords
  sanitized=$(echo "$sanitized" | sed -E 's/(password|passwd|pwd|token|secret|key)=[^ ]*/\1=***REDACTED***/gi')

  # Mask environment variables that might contain secrets
  sanitized=$(echo "$sanitized" | sed -E 's/(MONGO|POSTGRES|REDIS|DATABASE|DB)_[A-Z_]*=([^ ]+)/\1_***=***REDACTED***/g')

  # Limit length for logging
  if [[ ${#sanitized} -gt 1000 ]]; then
    sanitized="${sanitized:0:1000}... (truncated)"
  fi

  echo "$sanitized"
}

validate_env_value_safe() {
  local name=$1
  local value=$2

  # Validate environment variable name
  if [[ ! "$name" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
    log_error "Invalid environment variable name: $name"
    return 1
  fi

  # Check for injection attempts in value
  if [[ "$value" =~ (\$\{|\$\(|;|\||&|>|<|\`) ]]; then
    log_error "Potential injection detected in environment variable value"
    return 1
  fi

  # Limit value length
  if [[ ${#value} -gt 4096 ]]; then
    log_error "Environment variable value too long"
    return 1
  fi

  return 0
}
```

**Files to Modify:**
- `lib/tk-validation.sh` - Add enhanced validation functions
- `connect-service.sh` - Use enhanced validation for all inputs
- `add-service.sh` - Use enhanced validation for all inputs
- `tk` - Use enhanced validation for all CLI arguments

**Tests Required:**
- `tests/test-validation-security.sh` - Test all validation functions
- Test path traversal attempts (../, ../../, etc.)
- Test command injection attempts
- Test environment variable injection
- Test reserved name blocking
- Test length limits

---

#### SEC-CLI-002: Secure Temporary File Handling

**Priority**: Phase 1 (Critical)
**Estimated Effort**: 2 hours
**Risk Mitigated**: Race Conditions, Information Disclosure

**Current State:**
- Ad-hoc temporary file creation
- No secure cleanup on exit
- Predictable file names

**Enhanced Implementation:**

```bash
# lib/tk-security.sh - New module for security functions

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

    # Securely wipe sensitive files before removal
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
```

**Files to Modify:**
- Create `lib/tk-security.sh` - New security module
- `lib/tk-common.sh` - Source tk-security.sh
- All scripts - Use secure temp file functions
- `connect-service.sh` - Use secure file writing for Dockerfile generation

**Tests Required:**
- Test temporary directory creation and cleanup
- Test file permissions (must be 600 or 700)
- Test cleanup on normal exit
- Test cleanup on error/signal
- Test atomic file writing

---

#### SEC-CLI-003: Docker Socket Security

**Priority**: Phase 1 (Critical)
**Estimated Effort**: 3 hours
**Risk Mitigated**: Privilege Escalation, Container Breakout

**Enhanced Implementation:**

```bash
# lib/tk-security.sh - Docker security functions

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
  local perms=$(stat -c "%a" "$docker_socket" 2>/dev/null || stat -f "%Lp" "$docker_socket" 2>/dev/null)
  if [[ "$perms" =~ ^[0-9]*[2367]$ ]]; then
    log_warn "Docker socket has overly permissive permissions: $perms"
    log_warn "This is a security risk. Recommended: 660"
  fi

  return 0
}

validate_docker_image_safe() {
  local image=$1

  # Block pulling from untrusted registries by default
  local trusted_registries=("docker.io" "gcr.io" "ghcr.io" "")
  local image_registry=$(echo "$image" | cut -d'/' -f1)

  # If image has no registry prefix, it's from Docker Hub (trusted)
  if [[ "$image" != *"/"* ]]; then
    return 0
  fi

  local registry_trusted=false
  for registry in "${trusted_registries[@]}"; do
    if [[ "$image_registry" == "$registry" ]] || [[ -z "$registry" && "$image" != *"."* ]]; then
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

  # Check for dangerous Docker Compose configurations
  local dangerous_patterns=(
    "privileged.*true"
    "cap_add.*SYS_ADMIN"
    "cap_add.*NET_ADMIN"
    "network_mode.*host"
    "pid.*host"
    "ipc.*host"
    "volumes.*:/var/run/docker.sock"
  )

  local issues_found=false

  for pattern in "${dangerous_patterns[@]}"; do
    if grep -Eq "$pattern" "$compose_file" 2>/dev/null; then
      log_warn "Potentially dangerous configuration detected: $pattern"
      issues_found=true
    fi
  done

  if [[ "$issues_found" == "true" ]]; then
    log_warn "Review the compose file for security implications"

    if [[ "${STRICT_DOCKER_SECURITY:-true}" == "true" ]]; then
      log_error "Dangerous configurations blocked by STRICT_DOCKER_SECURITY=true"
      return 1
    fi
  fi

  return 0
}

# Wrapper for docker commands with audit logging
docker_exec_safe() {
  local operation=$1
  shift
  local command=("$@")

  # Log the operation for audit trail
  log_audit "DOCKER_EXEC" "$operation" "$(sanitize_for_logging "${command[*]}")"

  # Validate command doesn't contain injection attempts
  validate_command_safe "${command[*]}" || return 1

  # Execute with error handling
  if ! "${command[@]}"; then
    log_error "Docker command failed: $operation"
    return 1
  fi

  return 0
}
```

**Files to Modify:**
- `lib/tk-security.sh` - Add Docker security functions
- `lib/tk-docker.sh` - Use secure Docker functions
- `connect-service.sh` - Validate images and compose configs
- All scripts using Docker - Use docker_exec_safe wrapper

**Tests Required:**
- Test Docker socket validation
- Test untrusted registry blocking
- Test dangerous compose configuration detection
- Test audit logging

---

#### SEC-CLI-004: Audit Logging

**Priority**: Phase 2 (Important)
**Estimated Effort**: 3 hours
**Risk Mitigated**: Unauthorized Access, Compliance

**Implementation:**

```bash
# lib/tk-logging.sh - Enhanced audit logging

# Audit log location
AUDIT_LOG="${TK_AUDIT_LOG:-$HOME/.tk/audit.log}"

setup_audit_logging() {
  # Create audit log directory
  local audit_dir=$(dirname "$AUDIT_LOG")
  mkdir -p "$audit_dir" || {
    log_warn "Failed to create audit log directory: $audit_dir"
    return 1
  }

  # Set restrictive permissions
  chmod 700 "$audit_dir"

  # Create audit log if doesn't exist
  if [[ ! -f "$AUDIT_LOG" ]]; then
    touch "$AUDIT_LOG"
    chmod 600 "$AUDIT_LOG"
  fi

  log_debug "Audit logging enabled: $AUDIT_LOG"
}

log_audit() {
  local event_type=$1
  local event_action=$2
  local event_details=$3

  # Initialize audit logging if not setup
  if [[ ! -f "$AUDIT_LOG" ]]; then
    setup_audit_logging || return 1
  fi

  # Build audit entry
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
  local username=$(whoami)
  local hostname=$(hostname)
  local pid=$$
  local script_name=$(basename "${BASH_SOURCE[-1]}")

  # Sanitize details for logging
  local sanitized_details=$(sanitize_for_logging "$event_details")

  # JSON format for easy parsing
  local audit_entry=$(cat <<EOF
{"timestamp":"$timestamp","user":"$username","host":"$hostname","pid":$pid,"script":"$script_name","event_type":"$event_type","action":"$event_action","details":"$sanitized_details"}
EOF
)

  # Append to audit log with file locking
  (
    flock -x 200
    echo "$audit_entry" >> "$AUDIT_LOG"
  ) 200>"$AUDIT_LOG.lock"

  # Optional: Send to syslog if available
  if command -v logger >/dev/null 2>&1; then
    logger -t "tk-audit" -p user.info "$event_type $event_action by $username: $sanitized_details"
  fi
}

# Convenience audit functions
audit_service_connect() {
  local service_name=$1
  local service_path=$2
  log_audit "SERVICE" "CONNECT" "service=$service_name path=$service_path"
}

audit_service_add() {
  local service_name=$1
  log_audit "SERVICE" "ADD" "service=$service_name"
}

audit_service_remove() {
  local service_name=$1
  log_audit "SERVICE" "REMOVE" "service=$service_name"
}

audit_config_change() {
  local config_type=$1
  local details=$2
  log_audit "CONFIG" "CHANGE" "type=$config_type details=$details"
}

audit_security_event() {
  local event_type=$1
  local details=$2
  log_audit "SECURITY" "$event_type" "$details"
}

# View audit logs (for tk audit command)
show_audit_logs() {
  local limit=${1:-50}

  if [[ ! -f "$AUDIT_LOG" ]]; then
    log_info "No audit logs found"
    return 0
  fi

  log_info "Recent audit events (last $limit):"
  echo ""

  # Pretty print last N entries
  tail -n "$limit" "$AUDIT_LOG" | while read -r line; do
    # Parse JSON and format
    local timestamp=$(echo "$line" | jq -r '.timestamp' 2>/dev/null || echo "N/A")
    local user=$(echo "$line" | jq -r '.user' 2>/dev/null || echo "N/A")
    local event_type=$(echo "$line" | jq -r '.event_type' 2>/dev/null || echo "N/A")
    local action=$(echo "$line" | jq -r '.action' 2>/dev/null || echo "N/A")
    local details=$(echo "$line" | jq -r '.details' 2>/dev/null || echo "N/A")

    echo "[$timestamp] $user - $event_type:$action - $details"
  done
}
```

**Files to Modify:**
- `lib/tk-logging.sh` - Add audit logging functions
- `lib/tk-common.sh` - Initialize audit logging on load
- `tk` - Add `tk audit` command to view logs
- `connect-service.sh` - Audit service connections
- `add-service.sh` - Audit service additions
- All security-sensitive operations - Add audit calls

**Tests Required:**
- Test audit log creation
- Test audit log permissions
- Test concurrent writes (file locking)
- Test sanitization of sensitive data
- Test log rotation (if implemented)

---

#### SEC-CLI-005: Secrets Management

**Priority**: Phase 2 (Important)
**Estimated Effort**: 4 hours
**Risk Mitigated**: Information Disclosure, Credential Theft

**Implementation:**

```bash
# lib/tk-secrets.sh - New secrets management module

# Secrets storage location
SECRETS_DIR="${TK_SECRETS_DIR:-$HOME/.tk/secrets}"

setup_secrets_store() {
  # Create secrets directory with restrictive permissions
  mkdir -p "$SECRETS_DIR" || {
    log_fatal "Failed to create secrets directory"
  }

  chmod 700 "$SECRETS_DIR"

  log_debug "Secrets store initialized: $SECRETS_DIR"
}

store_secret() {
  local secret_name=$1
  local secret_value=$2

  # Validate secret name
  if [[ ! "$secret_name" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
    log_error "Invalid secret name: $secret_name"
    return 1
  fi

  setup_secrets_store

  local secret_file="$SECRETS_DIR/$secret_name"

  # Encrypt if possible
  if command -v openssl >/dev/null 2>&1; then
    # Use OpenSSL encryption
    echo "$secret_value" | openssl enc -aes-256-cbc -salt -pbkdf2 -out "$secret_file" -pass pass:"$(get_encryption_key)" || {
      log_error "Failed to encrypt secret"
      return 1
    }
  else
    # Fallback: Base64 encoding (NOT SECURE, just obfuscation)
    log_warn "OpenSSL not available. Storing secret with base64 encoding only (not secure)"
    echo "$secret_value" | base64 > "$secret_file"
  fi

  # Restrictive permissions
  chmod 600 "$secret_file"

  log_audit "SECRETS" "STORE" "name=$secret_name"
  log_info "Secret stored: $secret_name"
}

retrieve_secret() {
  local secret_name=$1

  setup_secrets_store

  local secret_file="$SECRETS_DIR/$secret_name"

  if [[ ! -f "$secret_file" ]]; then
    log_error "Secret not found: $secret_name"
    return 1
  fi

  # Decrypt if encrypted
  if command -v openssl >/dev/null 2>&1; then
    openssl enc -aes-256-cbc -d -pbkdf2 -in "$secret_file" -pass pass:"$(get_encryption_key)" 2>/dev/null || {
      log_error "Failed to decrypt secret"
      return 1
    }
  else
    # Fallback: Base64 decode
    base64 -d < "$secret_file"
  fi

  log_audit "SECRETS" "RETRIEVE" "name=$secret_name"
}

delete_secret() {
  local secret_name=$1

  local secret_file="$SECRETS_DIR/$secret_name"

  if [[ ! -f "$secret_file" ]]; then
    log_error "Secret not found: $secret_name"
    return 1
  fi

  # Securely wipe file before deletion
  if command -v shred >/dev/null 2>&1; then
    shred -u "$secret_file"
  else
    rm -f "$secret_file"
  fi

  log_audit "SECRETS" "DELETE" "name=$secret_name"
  log_info "Secret deleted: $secret_name"
}

list_secrets() {
  setup_secrets_store

  if [[ ! -d "$SECRETS_DIR" ]] || [[ -z "$(ls -A "$SECRETS_DIR" 2>/dev/null)" ]]; then
    log_info "No secrets stored"
    return 0
  fi

  log_info "Stored secrets:"
  ls -1 "$SECRETS_DIR" | while read -r secret_name; do
    echo "  - $secret_name"
  done
}

get_encryption_key() {
  # Derive encryption key from user's environment
  # This is a simple approach; for production, use a proper key management system
  local key_material="${USER}-${HOSTNAME}-tk-secrets"
  echo -n "$key_material" | sha256sum | cut -d' ' -f1
}

# Check for secrets in command output/logs
detect_secrets_in_output() {
  local output=$1

  # Patterns that might indicate secrets
  local secret_patterns=(
    "password"
    "passwd"
    "api[_-]?key"
    "token"
    "secret"
    "credentials"
    "private[_-]?key"
  )

  for pattern in "${secret_patterns[@]}"; do
    if echo "$output" | grep -qi "$pattern"; then
      log_warn "Possible secret detected in output: $pattern"
      return 1
    fi
  done

  return 0
}
```

**CLI Commands:**
```bash
# Add secrets management commands to tk CLI
tk secret store <name> <value>   # Store a secret
tk secret get <name>              # Retrieve a secret
tk secret delete <name>           # Delete a secret
tk secret list                    # List stored secrets
```

**Files to Modify:**
- Create `lib/tk-secrets.sh` - Secrets management module
- `lib/tk-common.sh` - Source tk-secrets.sh
- `tk` - Add secret commands
- Update documentation to recommend using secrets for sensitive values

**Tests Required:**
- Test secret storage and retrieval
- Test encryption (if OpenSSL available)
- Test permission enforcement
- Test secret deletion (secure wipe)
- Test secret detection in logs

---

#### SEC-CLI-006: Rate Limiting & Resource Controls

**Priority**: Phase 3 (Nice-to-Have)
**Estimated Effort**: 3 hours
**Risk Mitigated**: Denial of Service, Resource Exhaustion

**Implementation:**

```bash
# lib/tk-security.sh - Rate limiting functions

# Rate limiting configuration
declare -A RATE_LIMIT_COUNTS
declare -A RATE_LIMIT_WINDOWS
RATE_LIMIT_ENABLED="${RATE_LIMIT_ENABLED:-true}"

check_rate_limit() {
  local operation=$1
  local max_count=${2:-10}
  local window_seconds=${3:-60}

  if [[ "$RATE_LIMIT_ENABLED" != "true" ]]; then
    return 0
  fi

  local current_time=$(date +%s)
  local window_key="${operation}_window"
  local count_key="${operation}_count"

  # Initialize if first time
  if [[ -z "${RATE_LIMIT_WINDOWS[$window_key]}" ]]; then
    RATE_LIMIT_WINDOWS[$window_key]=$current_time
    RATE_LIMIT_COUNTS[$count_key]=0
  fi

  local window_start=${RATE_LIMIT_WINDOWS[$window_key]}
  local count=${RATE_LIMIT_COUNTS[$count_key]}

  # Check if we're in a new window
  if (( current_time - window_start >= window_seconds )); then
    # Reset window
    RATE_LIMIT_WINDOWS[$window_key]=$current_time
    RATE_LIMIT_COUNTS[$count_key]=0
    count=0
  fi

  # Check if limit exceeded
  if (( count >= max_count )); then
    local time_remaining=$((window_seconds - (current_time - window_start)))
    log_error "Rate limit exceeded for $operation"
    log_error "Try again in $time_remaining seconds"
    audit_security_event "RATE_LIMIT_EXCEEDED" "operation=$operation"
    return 1
  fi

  # Increment counter
  RATE_LIMIT_COUNTS[$count_key]=$((count + 1))

  return 0
}

validate_resource_limits() {
  local operation=$1

  # Check disk space
  local available_space=$(df -k "$(find_project_root)" | tail -1 | awk '{print $4}')
  local min_space_kb=$((1024 * 1024))  # 1GB minimum

  if (( available_space < min_space_kb )); then
    log_error "Insufficient disk space for $operation"
    log_error "Available: $((available_space / 1024))MB, Required: $((min_space_kb / 1024))MB"
    return 1
  fi

  # Check memory (if free command available)
  if command -v free >/dev/null 2>&1; then
    local available_mem=$(free -m | awk 'NR==2{print $7}')
    local min_mem_mb=512

    if (( available_mem < min_mem_mb )); then
      log_warn "Low memory available: ${available_mem}MB"
      log_warn "Some operations may be slow"
    fi
  fi

  return 0
}
```

**Files to Modify:**
- `lib/tk-security.sh` - Add rate limiting functions
- `connect-service.sh` - Rate limit service connections
- `add-service.sh` - Rate limit service additions
- Resource-intensive operations - Check resource limits before executing

**Tests Required:**
- Test rate limit enforcement
- Test rate limit window reset
- Test resource limit checks

---

#### SEC-CLI-007: Configuration Hardening

**Priority**: Phase 2 (Important)
**Estimated Effort**: 2 hours
**Risk Mitigated**: Misconfiguration, Unauthorized Access

**Implementation:**

```bash
# .tkrc.example - Security-focused configuration template

# ==============================================================================
# Traefik tk CLI - Security Configuration
# ==============================================================================

# Security Mode
# Options: strict, normal, permissive
# strict: Maximum security, blocks potentially dangerous operations
# normal: Balanced security and usability (default)
# permissive: Minimal restrictions (not recommended)
SECURITY_MODE="normal"

# Docker Security
STRICT_DOCKER_SECURITY=true           # Block dangerous Docker configurations
ALLOW_UNTRUSTED_REGISTRIES=false      # Block images from untrusted registries
REQUIRE_DOCKER_CONTENT_TRUST=false    # Require signed images (if Docker Content Trust enabled)

# Input Validation
STRICT_INPUT_VALIDATION=true          # Enforce strict input validation
MAX_SERVICE_NAME_LENGTH=63            # Maximum service name length
ALLOWED_PATH_PREFIX="$HOME"           # Restrict paths to this prefix

# Audit Logging
ENABLE_AUDIT_LOGGING=true             # Enable audit logging
TK_AUDIT_LOG="$HOME/.tk/audit.log"    # Audit log location
AUDIT_LOG_MAX_SIZE_MB=100             # Max audit log size before rotation

# Secrets Management
TK_SECRETS_DIR="$HOME/.tk/secrets"    # Secrets storage directory
REQUIRE_ENCRYPTION=true               # Require encryption for secrets (needs OpenSSL)

# Rate Limiting
RATE_LIMIT_ENABLED=true               # Enable rate limiting
MAX_CONNECTIONS_PER_MINUTE=10         # Max service connections per minute
MAX_ADDITIONS_PER_MINUTE=5            # Max service additions per minute

# Temporary Files
SECURE_TMP_CLEANUP=true               # Securely wipe temp files on exit
TMP_FILE_PERMISSIONS=600              # Permissions for temporary files

# Confirmation Prompts
CONFIRM_DESTRUCTIVE=true              # Require confirmation for destructive operations
CONFIRM_EXTERNAL_SERVICES=true        # Confirm before connecting external services

# Logging
LOG_SENSITIVE_DATA=false              # Log sensitive data (not recommended)
SANITIZE_LOGS=true                    # Sanitize logs to remove secrets

# Network
ALLOWED_DOMAINS="*.localhost *.local" # Allowed domain patterns
BLOCK_EXTERNAL_NETWORKS=false         # Block services from accessing external networks

# User Restrictions
ALLOWED_USERS=""                      # Whitelist of users (empty = all users)
BLOCKED_USERS=""                      # Blacklist of users

# ==============================================================================
# Advanced Security Settings
# ==============================================================================

# File System
ENABLE_PATH_ALLOWLIST=true            # Only allow access to allowlisted paths
PATH_ALLOWLIST=(                      # Allowed path prefixes
  "$HOME"
  "/tmp"
  "$(dirname "$0")/.."
)

# Command Execution
ENABLE_COMMAND_ALLOWLIST=false        # Only allow whitelisted commands
BLOCKED_COMMANDS=(                    # Explicitly blocked commands
  "rm -rf /"
  "dd if=/dev/zero"
  "mkfs"
  ":(){:|:&};:"
)

# Compliance
HIPAA_MODE=false                      # HIPAA compliance mode (stricter controls)
PCI_DSS_MODE=false                    # PCI-DSS compliance mode
SOC2_MODE=false                       # SOC 2 compliance mode
```

**Files to Modify:**
- Create `.tkrc.example` - Security-focused configuration template
- `lib/tk-common.sh` - Load security configuration
- `lib/tk-security.sh` - Enforce security configuration
- All scripts - Respect security configuration

---

## GitHub Deployment Process Security

### Overview

The GitHub deployment process needs enhanced security controls to prevent supply chain attacks, unauthorized deployments, and ensure code integrity throughout the CI/CD pipeline.

### Threat Model

**Threat Actors:**
- External attackers attempting to inject malicious code
- Compromised developer accounts
- Malicious dependencies (supply chain attacks)
- Insider threats

**Attack Vectors:**
- Unauthorized direct commits to main
- Malicious pull requests
- Compromised GitHub Actions workflows
- Dependency confusion attacks
- Secret exfiltration through workflows
- Unsigned commits from compromised accounts

### Security Enhancements

---

#### SEC-GH-001: Branch Protection Rules

**Priority**: Phase 1 (Critical)
**Estimated Effort**: 1 hour
**Risk Mitigated**: Unauthorized Code Changes, Broken Builds

**Implementation:**

```yaml
# .github/branch-protection-rules.md

# Branch Protection Configuration for GitHub

## Main Branch (main)

### Required Status Checks
- ✅ All CI tests must pass
- ✅ Security scan must pass
- ✅ Dependency audit must pass

### Pull Request Requirements
- Require pull request before merging
- Require 1 approval from CODEOWNERS
- Dismiss stale pull request approvals when new commits are pushed
- Require review from CODEOWNERS
- Require status checks to pass before merging
- Require branches to be up to date before merging
- Require conversation resolution before merging

### Commit Restrictions
- Require signed commits (GPG or S/MIME)
- Include administrators in restrictions
- Restrict pushes to specific people/teams only
- Allow force pushes: ❌ No
- Allow deletions: ❌ No

### Additional Rules
- Require linear history (no merge commits)
- Lock branch (prevent any changes)

## Develop Branch (develop)

### Required Status Checks
- ✅ All CI tests must pass
- ✅ Lint checks must pass

### Pull Request Requirements
- Require pull request before merging
- Require 1 approval (can be any team member)
- Require status checks to pass before merging

### Commit Restrictions
- Require signed commits recommended
- Allow force pushes: ✅ Yes (for rebasing)
- Allow deletions: ❌ No
```

**Implementation Steps:**

1. Navigate to: Repository Settings → Branches → Branch protection rules
2. Add rule for `main` branch with all settings above
3. Add rule for `develop` branch with settings above
4. Test by attempting unauthorized direct push (should fail)

---

#### SEC-GH-002: CODEOWNERS File

**Priority**: Phase 1 (Critical)
**Estimated Effort**: 30 minutes
**Risk Mitigated**: Unauthorized Changes to Critical Files

**Implementation:**

```
# .github/CODEOWNERS
#
# Code owners are automatically requested for review when someone
# opens a pull request that modifies code that they own.
#
# Documentation: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners

# Default owner for everything in the repo
# Unless a later match takes precedence
* @natejswenson

# Security-sensitive files require review from security team
/.github/workflows/ @natejswenson @security-team
/.github/CODEOWNERS @natejswenson @security-team
/lib/tk-security.sh @natejswenson @security-team
/lib/tk-validation.sh @natejswenson @security-team

# CI/CD pipeline changes require review
/.github/workflows/merge-to-main.yml @natejswenson @cicd-team
/.github/workflows/test.yml @natejswenson @cicd-team
/merge-to-main.sh @natejswenson @cicd-team

# Documentation changes can be reviewed by any maintainer
*.md @natejswenson @docs-team

# Test files require review from test maintainers
/tests/ @natejswenson @test-team

# Library modules require careful review
/lib/ @natejswenson @core-team

# Main CLI requires careful review
/tk @natejswenson @core-team
```

**Files to Create:**
- `.github/CODEOWNERS` - Code ownership definitions

**Note:** Update team names (`@security-team`, `@cicd-team`, etc.) with actual GitHub team names or individual usernames.

---

#### SEC-GH-003: Signed Commits Enforcement

**Priority**: Phase 1 (Critical)
**Estimated Effort**: 1 hour
**Risk Mitigated**: Impersonation, Unauthorized Code Changes

**Implementation:**

```bash
# scripts/setup-commit-signing.sh
#!/usr/bin/env bash
#
# setup-commit-signing.sh - Setup GPG commit signing
#

set -euo pipefail

echo "Setting up GPG commit signing for Git"
echo "======================================"
echo ""

# Check if GPG is installed
if ! command -v gpg >/dev/null 2>&1; then
  echo "Error: GPG is not installed"
  echo ""
  echo "Install GPG:"
  echo "  macOS:  brew install gnupg"
  echo "  Ubuntu: sudo apt-get install gnupg"
  echo "  Fedora: sudo dnf install gnupg2"
  exit 1
fi

# Check for existing GPG key
echo "Checking for existing GPG keys..."
if gpg --list-secret-keys --keyid-format LONG | grep -q "sec"; then
  echo "✓ Existing GPG keys found"
  gpg --list-secret-keys --keyid-format LONG
  echo ""
  read -p "Use existing key? (y/n): " use_existing

  if [[ "$use_existing" != "y" ]]; then
    echo "Generating new GPG key..."
    gpg --full-generate-key
  fi
else
  echo "No GPG keys found. Generating new key..."
  echo ""
  gpg --full-generate-key
fi

# Get the GPG key ID
echo ""
echo "Available GPG keys:"
gpg --list-secret-keys --keyid-format LONG
echo ""
read -p "Enter the GPG key ID to use (e.g., 3AA5C34371567BD2): " key_id

# Configure Git to use GPG key
echo ""
echo "Configuring Git to use GPG key: $key_id"
git config --global user.signingkey "$key_id"
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# Export public key for GitHub
echo ""
echo "Your GPG public key (add this to GitHub):"
echo "=========================================="
gpg --armor --export "$key_id"
echo "=========================================="
echo ""
echo "Add this key to GitHub:"
echo "1. Go to: https://github.com/settings/keys"
echo "2. Click 'New GPG key'"
echo "3. Paste the key above"
echo ""

# Test signing
echo "Testing commit signing..."
test_file=$(mktemp)
echo "test" > "$test_file"
git add "$test_file" 2>/dev/null || true
if git commit -S -m "Test signed commit" 2>/dev/null; then
  echo "✓ Commit signing works!"
  git reset HEAD~1 >/dev/null 2>&1 || true
else
  echo "✗ Commit signing failed"
  echo "Check GPG configuration"
fi
rm -f "$test_file"

echo ""
echo "Setup complete!"
echo ""
echo "All future commits will be signed automatically."
```

**GitHub Configuration:**

1. Enable "Require signed commits" in branch protection for `main` and `develop`
2. Add team GPG keys to GitHub accounts
3. Configure vigilant mode: Settings → SSH and GPG keys → "Flag unsigned commits as unverified"

**Documentation Updates:**
- Add commit signing instructions to README.md
- Create troubleshooting guide for common GPG issues

---

#### SEC-GH-004: GitHub Actions Security

**Priority**: Phase 1 (Critical)
**Estimated Effort**: 3 hours
**Risk Mitigated**: Supply Chain Attacks, Secret Exfiltration

**Implementation:**

```yaml
# .github/workflows/security-scan.yml
name: Security Scan

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main, develop]
  schedule:
    # Run security scan daily at 2 AM UTC
    - cron: '0 2 * * *'

permissions:
  contents: read
  security-events: write

jobs:
  shellcheck:
    name: ShellCheck Linting
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          persist-credentials: false

      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          severity: warning
          scandir: '.'
          format: gcc

  secret-scanning:
    name: Secret Scanning
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for secret scanning
          persist-credentials: false

      - name: TruffleHog OSS
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.repository.default_branch }}
          head: HEAD
          extra_args: --debug --only-verified

      - name: GitLeaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}

  dependency-review:
    name: Dependency Review
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          persist-credentials: false

      - name: Dependency Review
        uses: actions/dependency-review-action@v4
        with:
          fail-on-severity: moderate
          deny-licenses: GPL-3.0, AGPL-3.0

  sast:
    name: SAST - Static Analysis
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          persist-credentials: false

      - name: Semgrep
        uses: returntocorp/semgrep-action@v1
        with:
          config: >-
            p/security-audit
            p/bash
            p/command-injection

  supply-chain:
    name: Supply Chain Security
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          persist-credentials: false

      - name: Verify Action Versions
        run: |
          echo "Checking for unpinned GitHub Actions..."

          # Find all workflow files
          workflow_files=$(find .github/workflows -name "*.yml" -o -name "*.yaml")

          # Check for unpinned actions (using @main or @master)
          unpinned_count=0
          for file in $workflow_files; do
            if grep -E "uses:.*@(main|master|v[0-9]+)$" "$file"; then
              echo "::warning file=$file::Found unpinned action reference"
              unpinned_count=$((unpinned_count + 1))
            fi
          done

          if [[ $unpinned_count -gt 0 ]]; then
            echo "::error::Found $unpinned_count unpinned action references"
            echo "::error::Pin actions to specific commit SHAs for security"
            exit 1
          fi

          echo "✓ All actions are properly pinned"

  security-summary:
    name: Security Summary
    runs-on: ubuntu-latest
    needs: [shellcheck, secret-scanning, dependency-review, sast, supply-chain]
    if: always()

    steps:
      - name: Check Results
        run: |
          echo "Security Scan Summary"
          echo "===================="
          echo "ShellCheck: ${{ needs.shellcheck.result }}"
          echo "Secret Scanning: ${{ needs.secret-scanning.result }}"
          echo "Dependency Review: ${{ needs.dependency-review.result }}"
          echo "SAST: ${{ needs.sast.result }}"
          echo "Supply Chain: ${{ needs.supply-chain.result }}"

          if [[ "${{ needs.shellcheck.result }}" != "success" ]] || \
             [[ "${{ needs.secret-scanning.result }}" != "success" ]] || \
             [[ "${{ needs.sast.result }}" != "success" ]] || \
             [[ "${{ needs.supply-chain.result }}" != "success" ]]; then
            echo "::error::Security scan failed"
            exit 1
          fi

          echo "✓ All security checks passed"
```

**Additional GitHub Actions Security:**

```yaml
# .github/workflows/hardening.yml
name: Action Hardening

on:
  workflow_dispatch:

jobs:
  pin-actions:
    name: Pin GitHub Actions to SHA
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install minder
        run: |
          curl -sSL https://raw.githubusercontent.com/stacklok/minder/main/scripts/install.sh | bash

      - name: Pin actions
        run: |
          minder pin-actions .github/workflows/

      - name: Create PR
        uses: peter-evans/create-pull-request@v5
        with:
          commit-message: "security: pin GitHub Actions to commit SHAs"
          title: "Security: Pin GitHub Actions"
          body: "This PR pins all GitHub Actions to specific commit SHAs for supply chain security"
          branch: security/pin-actions
```

**Secrets Management in Actions:**

```yaml
# .github/workflows/example-with-secrets.yml
name: Example with Secure Secrets

on:
  workflow_dispatch:

# Minimal permissions
permissions:
  contents: read

jobs:
  secure-job:
    runs-on: ubuntu-latest

    # Environment with required reviewers
    environment:
      name: production

    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false  # Don't persist GitHub token

      - name: Use secret securely
        env:
          # Load secret into environment variable
          SECRET_VALUE: ${{ secrets.MY_SECRET }}
        run: |
          # Never echo secrets
          # Never pass secrets as command line arguments
          # Use environment variables or files

          # Good: Use secret from environment
          echo "Processing with secret..."
          # Process with $SECRET_VALUE

          # Bad: Don't do this!
          # echo "$SECRET_VALUE"  # Would expose in logs
          # command --secret "$SECRET_VALUE"  # Would expose in process list
```

**Files to Create/Modify:**
- Create `.github/workflows/security-scan.yml`
- Create `.github/workflows/hardening.yml`
- Update existing workflows to use minimal permissions
- Pin all actions to commit SHAs

---

#### SEC-GH-005: Dependency Security

**Priority**: Phase 2 (Important)
**Estimated Effort**: 2 hours
**Risk Mitigated**: Vulnerable Dependencies, Supply Chain Attacks

**Implementation:**

```yaml
# .github/dependabot.yml
version: 2
updates:
  # GitHub Actions dependencies
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
    open-pull-requests-limit: 10
    reviewers:
      - "natejswenson"
    labels:
      - "dependencies"
      - "security"
    commit-message:
      prefix: "chore(deps)"
      include: "scope"

  # Docker dependencies (if using Dockerfile)
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    reviewers:
      - "natejswenson"
    labels:
      - "dependencies"
      - "docker"
```

**Automated Vulnerability Scanning:**

```yaml
# .github/workflows/vulnerability-scan.yml
name: Vulnerability Scan

on:
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight
  workflow_dispatch:

jobs:
  scan:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Upload Trivy results to GitHub Security tab
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'

      - name: Check for vulnerabilities
        run: |
          if grep -q '"level": "error"' trivy-results.sarif; then
            echo "::error::Critical vulnerabilities found"
            exit 1
          fi
```

---

#### SEC-GH-006: Audit Logging & Monitoring

**Priority**: Phase 2 (Important)
**Estimated Effort**: 2 hours
**Risk Mitigated**: Unauthorized Access, Compliance

**Implementation:**

```yaml
# .github/workflows/audit-log.yml
name: Audit Logging

on:
  push:
    branches: [main, develop]
  pull_request:
    types: [opened, closed, reopened]
  workflow_dispatch:

jobs:
  audit-log:
    runs-on: ubuntu-latest

    steps:
      - name: Log Event
        run: |
          cat <<EOF > audit-event.json
          {
            "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
            "event_type": "${{ github.event_name }}",
            "actor": "${{ github.actor }}",
            "repository": "${{ github.repository }}",
            "ref": "${{ github.ref }}",
            "sha": "${{ github.sha }}",
            "workflow": "${{ github.workflow }}",
            "run_id": "${{ github.run_id }}"
          }
          EOF

          echo "Audit Event:"
          cat audit-event.json

      - name: Send to Audit Service
        if: false  # Enable when audit service is configured
        run: |
          # Send to external audit logging service
          # curl -X POST https://audit-service.example.com/events \
          #   -H "Content-Type: application/json" \
          #   -H "Authorization: Bearer ${{ secrets.AUDIT_TOKEN }}" \
          #   -d @audit-event.json
          echo "Would send to audit service"
```

---

#### SEC-GH-007: Security Policy & Reporting

**Priority**: Phase 2 (Important)
**Estimated Effort**: 1 hour
**Risk Mitigated**: Responsible Disclosure, Vulnerability Management

**Implementation:**

```markdown
# .github/SECURITY.md

# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| develop | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via one of the following methods:

### Email
Send an email to: security@example.com

### GitHub Security Advisories
Use GitHub's private vulnerability reporting:
1. Go to the Security tab
2. Click "Report a vulnerability"
3. Fill out the form with details

### What to Include
Please include the following information:

- Type of vulnerability
- Full paths of source file(s) related to the vulnerability
- Location of the affected source code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it

### Response Timeline

- **Acknowledgment**: Within 24 hours
- **Initial Assessment**: Within 3 business days
- **Status Update**: Weekly updates until resolved
- **Resolution**: Target 30 days for critical issues, 90 days for others

### Disclosure Policy

- We follow coordinated disclosure
- We will notify you when the vulnerability is fixed
- We will credit you in the security advisory (unless you prefer to remain anonymous)
- We ask that you do not publicly disclose the vulnerability until we have released a fix

## Security Best Practices

### For Contributors

1. **Code Review**: All code must be reviewed before merging
2. **Signed Commits**: Use GPG-signed commits
3. **Dependencies**: Keep dependencies up to date
4. **Secrets**: Never commit secrets or credentials
5. **Testing**: Write security tests for new features

### For Users

1. **Keep Updated**: Always use the latest version
2. **Secure Configuration**: Review and harden .tkrc settings
3. **Audit Logs**: Enable and monitor audit logs
4. **Secrets Management**: Use tk secret commands for sensitive data
5. **Least Privilege**: Run with minimal required permissions

## Security Features

### Current Security Controls

- ✅ Input validation and sanitization
- ✅ Path traversal protection
- ✅ Command injection prevention
- ✅ Audit logging
- ✅ Secure temporary file handling
- ✅ Docker socket security checks
- ✅ Rate limiting
- ✅ Secrets management
- ✅ Signed commits required
- ✅ Branch protection enabled
- ✅ Automated security scanning

### Planned Enhancements

- 🔄 Two-factor authentication for sensitive operations
- 🔄 Enhanced secrets encryption
- 🔄 RBAC (Role-Based Access Control)
- 🔄 Integration with security monitoring tools

## Vulnerability Disclosure

Past security advisories can be found in the [Security Advisories](https://github.com/OWNER/REPO/security/advisories) section.

## Security Contact

- Email: security@example.com
- PGP Key: [Link to public key]

## Acknowledgments

We appreciate the security community's efforts in responsible disclosure. Security researchers who responsibly report vulnerabilities will be acknowledged in our hall of fame (unless they prefer to remain anonymous).

---

Last Updated: 2026-01-14
```

**Files to Create:**
- `.github/SECURITY.md` - Security policy and reporting

---

## Implementation Phases

### Phase 1: Critical Security Controls (Week 1)

**Priority**: Must implement immediately

**CLI Tool:**
- ✅ SEC-CLI-001: Enhanced Input Validation
- ✅ SEC-CLI-002: Secure Temporary File Handling
- ✅ SEC-CLI-003: Docker Socket Security

**GitHub:**
- ✅ SEC-GH-001: Branch Protection Rules
- ✅ SEC-GH-002: CODEOWNERS File
- ✅ SEC-GH-003: Signed Commits Enforcement
- ✅ SEC-GH-004: GitHub Actions Security

**Estimated Effort**: 14 hours
**Success Criteria**: All critical vulnerabilities addressed, basic security controls in place

---

### Phase 2: Important Security Controls (Week 2)

**Priority**: Implement soon

**CLI Tool:**
- ✅ SEC-CLI-004: Audit Logging
- ✅ SEC-CLI-005: Secrets Management
- ✅ SEC-CLI-007: Configuration Hardening

**GitHub:**
- ✅ SEC-GH-005: Dependency Security
- ✅ SEC-GH-006: Audit Logging & Monitoring
- ✅ SEC-GH-007: Security Policy & Reporting

**Estimated Effort**: 13 hours
**Success Criteria**: Comprehensive security monitoring, hardened configuration

---

### Phase 3: Enhanced Security (Week 3)

**Priority**: Nice to have

**CLI Tool:**
- ✅ SEC-CLI-006: Rate Limiting & Resource Controls

**Estimated Effort**: 3 hours
**Success Criteria**: DoS protection, resource exhaustion prevention

---

## Testing Requirements

### Security Testing Checklist

**For each security enhancement:**

1. **Unit Tests**
   - [ ] Test valid inputs (should pass)
   - [ ] Test invalid inputs (should fail safely)
   - [ ] Test edge cases
   - [ ] Test boundary conditions

2. **Attack Simulation**
   - [ ] Command injection attempts
   - [ ] Path traversal attempts
   - [ ] SQL injection (if applicable)
   - [ ] XSS attempts (if applicable)
   - [ ] Buffer overflow attempts
   - [ ] Race condition scenarios

3. **Integration Tests**
   - [ ] Test with realistic workloads
   - [ ] Test interaction with other components
   - [ ] Test error handling
   - [ ] Test logging and monitoring

4. **Performance Tests**
   - [ ] Measure overhead of security controls
   - [ ] Test rate limiting under load
   - [ ] Test resource consumption

5. **Compliance Tests**
   - [ ] Verify audit logging captures required events
   - [ ] Verify secrets are never logged
   - [ ] Verify proper access controls

### Test Implementation

```bash
# tests/test-security.sh
#!/usr/bin/env bash
#
# Security-focused integration tests
#

source "$(dirname "$0")/test-common.sh"

# Test command injection prevention
test_command_injection() {
  log_info "Testing command injection prevention..."

  # These should all fail
  assert_fails ./connect-service.sh "/tmp/test; rm -rf /"
  assert_fails ./connect-service.sh "\$(whoami)"
  assert_fails ./connect-service.sh "test|cat /etc/passwd"
  assert_fails ./connect-service.sh "test\`date\`"
}

# Test path traversal prevention
test_path_traversal() {
  log_info "Testing path traversal prevention..."

  # These should all fail
  assert_fails ./connect-service.sh "../../etc/passwd"
  assert_fails ./connect-service.sh "/etc/../../../etc/passwd"
  assert_fails ./connect-service.sh "./.././.././etc/passwd"
}

# Test secrets not in logs
test_secrets_not_logged() {
  log_info "Testing secrets are not logged..."

  # Create test with secret
  local output=$(TEST_PASSWORD="secret123" ./connect-service.sh /tmp/test 2>&1)

  # Secret should not appear in output
  if echo "$output" | grep -q "secret123"; then
    log_error "Secret found in logs!"
    return 1
  fi

  # Should be redacted
  assert_contains "***REDACTED***" "$output"
}

# Test file permissions
test_secure_permissions() {
  log_info "Testing secure file permissions..."

  # Create secret
  ./tk secret store TEST_SECRET "value"

  # Check permissions (should be 600)
  local perms=$(stat -c "%a" "$HOME/.tk/secrets/TEST_SECRET" 2>/dev/null || stat -f "%Lp" "$HOME/.tk/secrets/TEST_SECRET")
  assert_equals "600" "$perms"

  # Cleanup
  ./tk secret delete TEST_SECRET
}

# Test rate limiting
test_rate_limiting() {
  log_info "Testing rate limiting..."

  # Enable rate limiting
  export RATE_LIMIT_ENABLED=true

  # Make 15 rapid connections (limit is 10 per minute)
  local success_count=0
  local fail_count=0

  for i in {1..15}; do
    if ./connect-service.sh /tmp/test-$i --dry-run 2>/dev/null; then
      success_count=$((success_count + 1))
    else
      fail_count=$((fail_count + 1))
    fi
  done

  # Should have been rate limited
  if [[ $fail_count -eq 0 ]]; then
    log_error "Rate limiting not working"
    return 1
  fi

  log_info "Rate limiting: $success_count succeeded, $fail_count blocked"
}

# Test audit logging
test_audit_logging() {
  log_info "Testing audit logging..."

  # Clear existing audit log
  rm -f "$HOME/.tk/audit.log"

  # Perform operation
  ./tk status

  # Check audit log exists and has entry
  assert_file_exists "$HOME/.tk/audit.log"

  # Check log format
  local log_entry=$(tail -1 "$HOME/.tk/audit.log")
  assert_contains "timestamp" "$log_entry"
  assert_contains "user" "$log_entry"
  assert_contains "event_type" "$log_entry"
}

# Run all security tests
run_tests
```

---

## Acceptance Criteria

### CLI Tool Security

**Must Have:**
- [ ] All user inputs are validated before use
- [ ] Path traversal attacks are prevented
- [ ] Command injection attacks are prevented
- [ ] Temporary files are created securely (mode 600)
- [ ] Temporary files are cleaned up on exit
- [ ] Docker socket access is validated
- [ ] Dangerous Docker configurations are blocked
- [ ] All security-sensitive operations are logged
- [ ] Secrets are never exposed in logs
- [ ] Tests pass for all security controls

**Should Have:**
- [ ] Secrets can be stored securely
- [ ] Secrets are encrypted at rest
- [ ] Rate limiting prevents abuse
- [ ] Resource limits prevent exhaustion
- [ ] Configuration file supports security settings
- [ ] Security documentation is complete

**Nice to Have:**
- [ ] Two-factor authentication for sensitive operations
- [ ] Integration with external security tools
- [ ] RBAC support
- [ ] Compliance mode presets (HIPAA, PCI-DSS, etc.)

### GitHub Security

**Must Have:**
- [ ] Branch protection enabled on main and develop
- [ ] Signed commits required
- [ ] CODEOWNERS file in place
- [ ] Required reviews before merging
- [ ] All CI tests must pass before merge
- [ ] GitHub Actions use minimal permissions
- [ ] Actions pinned to specific commit SHAs
- [ ] Secret scanning enabled
- [ ] Dependency scanning enabled

**Should Have:**
- [ ] Automated security scanning in CI/CD
- [ ] Dependabot configured
- [ ] SECURITY.md file published
- [ ] Audit logging for all repository events
- [ ] Vulnerability disclosure process documented

**Nice to Have:**
- [ ] Integration with external SIEM
- [ ] Real-time security alerts
- [ ] Automated incident response
- [ ] Security metrics dashboard

---

## Security Metrics

### Key Performance Indicators (KPIs)

**CLI Tool:**
- Percentage of user inputs validated: **Target 100%**
- Number of security violations blocked: **Track and trend**
- Audit log coverage: **Target 100% of sensitive operations**
- Secrets exposure incidents: **Target 0**
- Security test coverage: **Target >90%**

**GitHub:**
- Percentage of commits signed: **Target 100%**
- Number of unsigned commits merged: **Target 0**
- Security scan failures: **Target 0 critical, <5 high**
- Dependency vulnerabilities: **Target 0 critical, <10 high**
- Time to patch critical vulnerabilities: **Target <24 hours**
- Required reviews completed: **Target 100%**

### Monitoring & Alerting

**Alert on:**
- Failed authentication attempts (future feature)
- Multiple validation failures from same user
- Dangerous commands blocked
- Security scan failures in CI/CD
- New critical vulnerabilities discovered
- Unsigned commits pushed
- Force pushes to protected branches
- Secrets detected in commits

---

## Implementation Checklist

### Phase 1 Tasks

**Week 1 - Critical Security:**
- [ ] Implement enhanced input validation (SEC-CLI-001)
- [ ] Implement secure temp file handling (SEC-CLI-002)
- [ ] Implement Docker socket security (SEC-CLI-003)
- [ ] Configure branch protection (SEC-GH-001)
- [ ] Create CODEOWNERS file (SEC-GH-002)
- [ ] Setup commit signing (SEC-GH-003)
- [ ] Harden GitHub Actions (SEC-GH-004)
- [ ] Write security tests
- [ ] Run full test suite
- [ ] Update documentation
- [ ] Security review

### Phase 2 Tasks

**Week 2 - Important Security:**
- [ ] Implement audit logging (SEC-CLI-004)
- [ ] Implement secrets management (SEC-CLI-005)
- [ ] Create security configuration (SEC-CLI-007)
- [ ] Setup Dependabot (SEC-GH-005)
- [ ] Implement audit logging for GitHub (SEC-GH-006)
- [ ] Create SECURITY.md (SEC-GH-007)
- [ ] Write additional security tests
- [ ] Update documentation
- [ ] Security review

### Phase 3 Tasks

**Week 3 - Enhanced Security:**
- [ ] Implement rate limiting (SEC-CLI-006)
- [ ] Performance testing
- [ ] Final security audit
- [ ] Documentation review
- [ ] Team training on new security features

---

## References & Resources

### Standards & Frameworks
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

### Tools
- [ShellCheck](https://www.shellcheck.net/) - Shell script linting
- [TruffleHog](https://github.com/trufflesecurity/trufflehog) - Secret scanning
- [GitLeaks](https://github.com/gitleaks/gitleaks) - Secret detection
- [Semgrep](https://semgrep.dev/) - SAST tool
- [Trivy](https://github.com/aquasecurity/trivy) - Vulnerability scanner

### GitHub Security
- [GitHub Security Features](https://docs.github.com/en/code-security)
- [Securing GitHub Actions](https://docs.github.com/en/actions/security-guides)
- [Branch Protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)

---

**Document Status**: Draft for Review
**Next Review**: After Phase 1 Implementation
**Owner**: Security Team
**Last Updated**: 2026-01-14
