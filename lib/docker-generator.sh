#!/bin/bash
# Docker Configuration Generator
# Generates Dockerfile and docker-compose service definitions

set -e

# Generate Dockerfile for FastAPI
generate_dockerfile_fastapi() {
    local port="$1"
    local entrypoint="$2"

    # Extract module and app variable from entrypoint (e.g., main.py -> main:app)
    local module=$(basename "$entrypoint" .py)
    local app_var="${3:-app}"

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

    # Build environment variables section
    local env_vars="      - ENV=development"

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

    # Volume mount pattern
    local volumes="      - ${service_path}:/app:delegated"
    if [ "$language" = "node" ]; then
        volumes="${volumes}
      - /app/node_modules"
    fi

    # Health check command
    local health_cmd="curl"
    if [ "$language" = "node" ]; then
        health_cmd="wget --no-verbose --tries=1 --spider"
    fi

    # Convert service name to title case for display
    local service_display=$(echo "$service_name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')

    cat <<EOF
  #----------------------------------------------------
  # ${service_display} - Auto-connected
  #----------------------------------------------------
  ${service_name}:
    <<: *common-config
    build:
      context: ${service_path}
    container_name: ${service_name}
    environment:
${env_vars}
    volumes:
${volumes}
    labels:
      <<: *traefik-base-labels
      traefik.http.routers.${service_name}.rule: Host(\`${service_name}.home.local\`)
      traefik.http.routers.${service_name}.entrypoints: websecure
      traefik.http.routers.${service_name}.tls: "true"
      traefik.http.services.${service_name}.loadbalancer.server.port: ${port}
    healthcheck:
      <<: *healthcheck-defaults
      test: ["CMD", "${health_cmd}", "-f", "http://localhost:${port}/health"]
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
    export -f generate_dockerfile
    export -f generate_dockerignore_python
    export -f generate_dockerignore_node
    export -f generate_compose_service
fi
