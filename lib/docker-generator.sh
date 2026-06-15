#!/bin/bash
# Docker Configuration Generator
# Generates Dockerfile and docker-compose service definitions
#
# HARDEN mode (set HARDEN=true, via `tk connect --harden`): emits production-
# hardened artifacts instead of the dev-hot-reload defaults — non-root uid 1001,
# data/secrets excluded from the image, no source bind-mount, no --reload,
# cap_drop ALL + no-new-privileges, and a wired (not enforced) API token. The
# default (HARDEN unset/false) is unchanged for backward compatibility.

set -e

# --- Hardened Dockerfile helpers ---------------------------------------------
# Shared non-root production base. $1=port  $2=CMD (JSON array line)  $3=extra apt pkgs
_hardened_py_dockerfile() {
    local port="$1"; local cmd="$2"; local extra_apt="${3:-}"
    cat <<EOF
FROM python:3.12-slim

# curl for the healthcheck; nothing else in the runtime image.
RUN apt-get update && apt-get install -y --no-install-recommends curl ${extra_apt}\\
    && rm -rf /var/lib/apt/lists/*

# Non-root user (uid 1001) — a container should never run as root.
RUN useradd --create-home --uid 1001 app
WORKDIR /app

# Deps first so the layer caches independent of source changes.
COPY --chown=app:app requirements.txt* pyproject.toml* setup.py* ./
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; \\
    elif [ -f pyproject.toml ]; then pip install --no-cache-dir .; fi

# Source. The hardened .dockerignore keeps data/ + secrets OUT of the image.
COPY --chown=app:app . .

USER app
EXPOSE ${port}

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \\
    CMD curl -fsS http://127.0.0.1:${port}/health || exit 1

# Production entrypoint — no auto-reload.
CMD ${cmd}
EOF
}

# Shared non-root Node production base. $1=port  $2=CMD (JSON array line)  $3=pre-CMD build step
# A non-empty build step implies devDeps are needed, so install the full tree in
# that case (a proper multi-stage prune is a future improvement); otherwise omit dev.
_hardened_node_dockerfile() {
    local port="$1"; local cmd="$2"; local build_step="${3:-}"
    local install_line
    if [ -n "$build_step" ]; then
        install_line='RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi'
    else
        install_line='RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi'
    fi
    cat <<EOF
FROM node:20-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl \\
    && rm -rf /var/lib/apt/lists/*

# Non-root user (uid 1001).
RUN useradd --create-home --uid 1001 app
WORKDIR /app

COPY --chown=app:app package*.json ./
${install_line}

COPY --chown=app:app . .
${build_step}
USER app
EXPOSE ${port}

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \\
    CMD curl -fsS http://127.0.0.1:${port}/health || exit 1

CMD ${cmd}
EOF
}

# Shared data/secret excludes appended to every .dockerignore in HARDEN mode.
_dockerignore_data_excludes() {
    cat <<'EOF'

# --- hardened: keep data + secrets out of the image (do NOT remove) ---
data/
*.db
*.sqlite
*.sqlite3
logs/
backups/
*.ofx
*.qfx
*.qbo
*.pem
*.key
.env.*
EOF
}

# Generate Dockerfile for FastAPI
generate_dockerfile_fastapi() {
    local port="$1"
    local entrypoint="$2"

    # Extract module and app variable from entrypoint (e.g., main.py -> main:app)
    local module=$(basename "$entrypoint" .py)
    local app_var="${3:-app}"

    if [ "${HARDEN:-false}" = "true" ]; then
        _hardened_py_dockerfile "$port" \
            "[\"uvicorn\", \"${module}:${app_var}\", \"--host\", \"0.0.0.0\", \"--port\", \"${port}\"]"
        return
    fi

    cat <<EOF
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies including curl for healthcheck
RUN apt-get update && apt-get install -y \\
    curl \\
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files
COPY requirements.txt* pyproject.toml* setup.py* ./

# Install Python dependencies
RUN if [ -f requirements.txt ]; then \\
        pip install --no-cache-dir -r requirements.txt; \\
    elif [ -f pyproject.toml ]; then \\
        pip install --no-cache-dir .; \\
    fi

# Copy application code
COPY . .

EXPOSE ${port}

# Use uvicorn with auto-reload for development
CMD ["uvicorn", "${module}:${app_var}", "--host", "0.0.0.0", "--port", "${port}", "--reload"]
EOF
}

# Generate Dockerfile for Flask
generate_dockerfile_flask() {
    local port="$1"
    local entrypoint="$2"

    if [ "${HARDEN:-false}" = "true" ]; then
        # Production: gunicorn (no Flask dev server, no debug). Assumes the app
        # exposes `app` in the entrypoint module; add gunicorn to requirements.
        local module=$(basename "$entrypoint" .py)
        _hardened_py_dockerfile "$port" \
            "[\"gunicorn\", \"--bind\", \"0.0.0.0:${port}\", \"${module}:app\"]"
        return
    fi

    cat <<EOF
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies including curl for healthcheck
RUN apt-get update && apt-get install -y \\
    curl \\
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files
COPY requirements.txt* pyproject.toml* setup.py* ./

# Install Python dependencies
RUN if [ -f requirements.txt ]; then \\
        pip install --no-cache-dir -r requirements.txt; \\
    elif [ -f pyproject.toml ]; then \\
        pip install --no-cache-dir .; \\
    fi

# Copy application code
COPY . .

EXPOSE ${port}

# Use Flask development server with auto-reload
ENV FLASK_APP=${entrypoint}
ENV FLASK_ENV=development
CMD ["flask", "run", "--host=0.0.0.0", "--port=${port}"]
EOF
}

# Generate Dockerfile for Django
generate_dockerfile_django() {
    local port="$1"

    if [ "${HARDEN:-false}" = "true" ]; then
        # Production: migrate then gunicorn the WSGI app. Assumes a top-level
        # <project>/wsgi.py; set DJANGO settings + add gunicorn to requirements.
        _hardened_py_dockerfile "$port" \
            "[\"sh\", \"-c\", \"python manage.py migrate && gunicorn --bind 0.0.0.0:${port} \$(ls */wsgi.py | head -1 | sed 's#/wsgi.py##').wsgi\"]" \
            "postgresql-client "
        return
    fi

    cat <<EOF
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    curl \\
    postgresql-client \\
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files
COPY requirements.txt* pyproject.toml* setup.py* ./

# Install Python dependencies
RUN if [ -f requirements.txt ]; then \\
        pip install --no-cache-dir -r requirements.txt; \\
    elif [ -f pyproject.toml ]; then \\
        pip install --no-cache-dir .; \\
    fi

# Copy application code
COPY . .

EXPOSE ${port}

# Run migrations and start development server
CMD ["sh", "-c", "python manage.py migrate && python manage.py runserver 0.0.0.0:${port}"]
EOF
}

# Generate Dockerfile for Express
generate_dockerfile_express() {
    local port="$1"

    if [ "${HARDEN:-false}" = "true" ]; then
        # Production: `npm start` (the app must define a start script).
        _hardened_node_dockerfile "$port" "[\"npm\", \"start\"]"
        return
    fi

    cat <<EOF
FROM node:20-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    wget \\
    && rm -rf /var/lib/apt/lists/*

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application code
COPY . .

EXPOSE ${port}

# Use nodemon for auto-reload in development
CMD ["npm", "run", "dev"]
EOF
}

# Generate Dockerfile for NestJS
generate_dockerfile_nestjs() {
    local port="$1"

    if [ "${HARDEN:-false}" = "true" ]; then
        # Production: build then run the compiled output.
        _hardened_node_dockerfile "$port" "[\"node\", \"dist/main\"]" "RUN npm run build"$'\n'
        return
    fi

    cat <<EOF
FROM node:20-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    wget \\
    && rm -rf /var/lib/apt/lists/*

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application code
COPY . .

EXPOSE ${port}

# Use NestJS dev mode for auto-reload
CMD ["npm", "run", "start:dev"]
EOF
}

# Generate Dockerfile for Next.js
generate_dockerfile_nextjs() {
    local port="$1"

    if [ "${HARDEN:-false}" = "true" ]; then
        # Production: build then `npm start` (next start). PORT is read from env.
        _hardened_node_dockerfile "$port" "[\"npm\", \"start\"]" "RUN npm run build"$'\n'
        return
    fi

    cat <<EOF
FROM node:20-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    wget \\
    && rm -rf /var/lib/apt/lists/*

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application code
COPY . .

EXPOSE ${port}

# Use Next.js dev mode
CMD ["npm", "run", "dev"]
EOF
}

# Generate Dockerfile for nginx static site
generate_dockerfile_nginx() {
    local port="$1"

    cat <<EOF
FROM nginx:alpine

# Install curl for healthcheck
RUN apk add --no-cache curl

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx config if present, otherwise create default
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy static files
COPY . /usr/share/nginx/html

# Remove nginx.conf from html directory (we already copied it to the right place)
RUN rm -f /usr/share/nginx/html/nginx.conf

EXPOSE ${port}

CMD ["nginx", "-g", "daemon off;"]
EOF
}

# Generate Dockerfile for generic static site (no nginx.conf)
generate_dockerfile_static_generic() {
    local port="$1"

    cat <<EOF
FROM nginx:alpine

# Install curl for healthcheck
RUN apk add --no-cache curl

# Create custom nginx config for SPA-friendly routing
RUN echo 'server { \\
    listen ${port}; \\
    server_name localhost; \\
    root /usr/share/nginx/html; \\
    index index.html index.htm; \\
    \\
    location / { \\
        try_files \$uri \$uri/ /index.html; \\
    } \\
    \\
    location /health { \\
        access_log off; \\
        return 200 "healthy\\n"; \\
        add_header Content-Type text/plain; \\
    } \\
}' > /etc/nginx/conf.d/default.conf

# Copy static files
COPY . /usr/share/nginx/html

EXPOSE ${port}

CMD ["nginx", "-g", "daemon off;"]
EOF
}

# Generate Dockerfile based on framework
generate_dockerfile() {
    local language="$1"
    local framework="$2"
    local port="$3"
    local entrypoint="$4"

    case "${language}" in
        python)
            case "${framework}" in
                fastapi)
                    generate_dockerfile_fastapi "$port" "$entrypoint"
                    ;;
                flask)
                    generate_dockerfile_flask "$port" "$entrypoint"
                    ;;
                django)
                    generate_dockerfile_django "$port"
                    ;;
                *)
                    generate_dockerfile_fastapi "$port" "$entrypoint"
                    ;;
            esac
            ;;
        node)
            case "${framework}" in
                express|koa|node-generic)
                    generate_dockerfile_express "$port"
                    ;;
                nestjs)
                    generate_dockerfile_nestjs "$port"
                    ;;
                nextjs)
                    generate_dockerfile_nextjs "$port"
                    ;;
                *)
                    generate_dockerfile_express "$port"
                    ;;
            esac
            ;;
        static)
            case "${framework}" in
                nginx)
                    generate_dockerfile_nginx "$port"
                    ;;
                *)
                    generate_dockerfile_static_generic "$port"
                    ;;
            esac
            ;;
    esac
}

# Generate .dockerignore for Python
generate_dockerignore_python() {
    cat <<'EOF'
__pycache__
*.pyc
*.pyo
*.pyd
.Python
env/
venv/
.venv/
ENV/
.pytest_cache/
.coverage
htmlcov/
.tox/
.git
.gitignore
.dockerignore
README.md
.env
.env.local
*.egg-info/
dist/
build/
.mypy_cache/
.ruff_cache/
EOF
    if [ "${HARDEN:-false}" = "true" ]; then _dockerignore_data_excludes; fi
}

# Generate .dockerignore for Node.js
generate_dockerignore_node() {
    cat <<'EOF'
node_modules
npm-debug.log
yarn-debug.log
yarn-error.log
.git
.gitignore
.dockerignore
README.md
.env
.env.local
.env.*.local
.next/
.nuxt/
dist/
coverage/
.cache/
EOF
    if [ "${HARDEN:-false}" = "true" ]; then _dockerignore_data_excludes; fi
}

# Generate .dockerignore for static sites
generate_dockerignore_static() {
    cat <<'EOF'
.git
.gitignore
.dockerignore
README.md
SPEC.md
.env
.env.local
*.md
.DS_Store
Thumbs.db
.vscode/
.idea/
docker-compose.yml
docker-compose*.yml
Dockerfile.dev
EOF
    if [ "${HARDEN:-false}" = "true" ]; then _dockerignore_data_excludes; fi
}

# Generate docker-compose service definition
generate_compose_service() {
    local service_name="$1"
    local service_path="$2"
    local port="$3"
    local language="$4"
    local needs_mongodb="$5"
    local needs_postgres="$6"
    local needs_redis="$7"

    local hardened="${HARDEN:-false}"
    # Uppercase env prefix for the token var (e.g. my-api -> MY_API).
    local svc_upper=$(echo "$service_name" | tr '[:lower:]-' '[:upper:]_')

    # Build environment variables section
    local env_vars
    if [ "$hardened" = "true" ]; then
        env_vars="      - ENV=production
      - ${svc_upper}_API_TOKEN=\${${svc_upper}_API_TOKEN}"
    else
        env_vars="      - ENV=development"
    fi

    if [ "$needs_mongodb" = "true" ]; then
        env_vars="${env_vars}
      - MONGODB_ROOT_USER=\${MONGODB_ROOT_USER:-admin}
      - MONGODB_ROOT_PASSWORD=\${MONGODB_ROOT_PASSWORD:-changeme}
      - MONGODB_HOST=mongodb
      - MONGODB_PORT=27017
      - MONGODB_DATABASE=\${MONGODB_DATABASE:-appdb}"
    fi

    if [ "$needs_postgres" = "true" ]; then
        env_vars="${env_vars}
      - POSTGRES_USER=\${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD:-changeme}
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - POSTGRES_DB=\${POSTGRES_DB:-appdb}"
    fi

    if [ "$needs_redis" = "true" ]; then
        env_vars="${env_vars}
      - REDIS_HOST=redis
      - REDIS_PORT=6379"
    fi

    # Build depends_on section
    local depends_on="      traefik:
        condition: service_healthy"

    if [ "$needs_mongodb" = "true" ]; then
        depends_on="${depends_on}
      mongodb:
        condition: service_healthy"
    fi

    if [ "$needs_postgres" = "true" ]; then
        depends_on="${depends_on}
      postgres:
        condition: service_healthy"
    fi

    if [ "$needs_redis" = "true" ]; then
        depends_on="${depends_on}
      redis:
        condition: service_healthy"
    fi

    # Volume mount pattern. HARDEN: no source bind-mount — the code lives in the
    # image (prod). Persistent data needs a manual data-only volume (documented).
    local volumes=""
    if [ "$hardened" = "true" ]; then
        volumes=""
    elif [ "$language" = "static" ]; then
        # Static sites serve from nginx html directory
        volumes="      - ${service_path}:/usr/share/nginx/html:ro"
    else
        volumes="      - ${service_path}:/app:delegated"
        if [ "$language" = "node" ]; then
            volumes="${volumes}
      - /app/node_modules"
        fi
    fi

    # Health check command
    local health_cmd="curl"
    if [ "$language" = "node" ]; then
        health_cmd="wget --no-verbose --tries=1 --spider"
    fi

    # Health check path - static sites may not have /health, check root instead
    local health_path="/health"
    if [ "$language" = "static" ]; then
        health_path="/"
    fi

    # Convert service name to title case for display
    local service_display=$(echo "$service_name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')

    # HARDEN: container hardening + omit the volumes: key when there's no mount.
    local hardening_block=""
    if [ "$hardened" = "true" ]; then
        hardening_block="    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
"
    fi
    local volumes_block=""
    if [ -n "$volumes" ]; then
        volumes_block="    volumes:
${volumes}
"
    fi

    cat <<EOF
  #----------------------------------------------------
  # ${service_display} - Auto-connected
  #----------------------------------------------------
  ${service_name}:
    <<: *common-config
    build:
      context: ${service_path}
    container_name: ${service_name}
${hardening_block}    environment:
${env_vars}
${volumes_block}    labels:
      <<: *traefik-base-labels
      traefik.http.routers.${service_name}.rule: Host(\`${service_name}.internal\`)
      traefik.http.routers.${service_name}.entrypoints: websecure
      traefik.http.routers.${service_name}.tls: "true"
      traefik.http.services.${service_name}.loadbalancer.server.port: ${port}
    healthcheck:
      <<: *healthcheck-defaults
      test: ["CMD", "${health_cmd}", "-f", "http://localhost:${port}${health_path}"]
      start_period: 10s
    depends_on:
${depends_on}
EOF
}

# Export functions if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f generate_dockerfile_fastapi
    export -f generate_dockerfile_flask
    export -f generate_dockerfile_django
    export -f generate_dockerfile_express
    export -f generate_dockerfile_nestjs
    export -f generate_dockerfile_nextjs
    export -f generate_dockerfile_nginx
    export -f generate_dockerfile_static_generic
    export -f generate_dockerfile
    export -f generate_dockerignore_python
    export -f generate_dockerignore_node
    export -f generate_dockerignore_static
    export -f generate_compose_service
fi
