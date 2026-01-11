#!/bin/bash
# Service Auto-Detection Library
# Detects service type, framework, port, and generates appropriate configuration

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect Python service type
detect_python_service() {
    local service_path="$1"
    local result=""

    # Check for FastAPI
    if grep -q "fastapi\|FastAPI" "${service_path}/requirements.txt" 2>/dev/null || \
       grep -q "from fastapi import\|import fastapi" "${service_path}"/*.py 2>/dev/null; then
        result="fastapi"
    # Check for Flask
    elif grep -q "flask\|Flask" "${service_path}/requirements.txt" 2>/dev/null || \
         grep -q "from flask import\|import flask" "${service_path}"/*.py 2>/dev/null; then
        result="flask"
    # Check for Django
    elif [ -f "${service_path}/manage.py" ] || grep -q "django" "${service_path}/requirements.txt" 2>/dev/null; then
        result="django"
    else
        result="python-generic"
    fi

    echo "$result"
}

# Detect Node.js service type
detect_node_service() {
    local service_path="$1"
    local result=""

    if [ -f "${service_path}/package.json" ]; then
        # Check for Express
        if grep -q '"express"' "${service_path}/package.json"; then
            result="express"
        # Check for NestJS
        elif grep -q '@nestjs/core' "${service_path}/package.json"; then
            result="nestjs"
        # Check for Next.js
        elif grep -q '"next"' "${service_path}/package.json"; then
            result="nextjs"
        # Check for Koa
        elif grep -q '"koa"' "${service_path}/package.json"; then
            result="koa"
        else
            result="node-generic"
        fi
    else
        result="node-generic"
    fi

    echo "$result"
}

# Detect primary programming language
detect_language() {
    local service_path="$1"

    # Check for Python
    if [ -f "${service_path}/requirements.txt" ] || \
       [ -f "${service_path}/setup.py" ] || \
       [ -f "${service_path}/pyproject.toml" ] || \
       [ -f "${service_path}/Pipfile" ]; then
        echo "python"
    # Check for Node.js
    elif [ -f "${service_path}/package.json" ]; then
        echo "node"
    # Check for Go
    elif [ -f "${service_path}/go.mod" ]; then
        echo "go"
    # Check for Rust
    elif [ -f "${service_path}/Cargo.toml" ]; then
        echo "rust"
    # Check by file extensions
    elif [ -n "$(find "${service_path}" -maxdepth 2 -name '*.py' -print -quit)" ]; then
        echo "python"
    elif [ -n "$(find "${service_path}" -maxdepth 2 -name '*.js' -o -name '*.ts' -print -quit)" ]; then
        echo "node"
    else
        echo "unknown"
    fi
}

# Extract port from service
extract_port_python() {
    local service_path="$1"
    local port="8000"  # default

    # Check main.py, app.py, server.py for port definitions
    for file in main.py app.py server.py __main__.py; do
        if [ -f "${service_path}/${file}" ]; then
            # Look for port in uvicorn.run, app.run, etc. (looking for assignment or parameter)
            local found_port=$(grep -E 'port\s*[:=]\s*[0-9]+|--port["\s]+[0-9]+' "${service_path}/${file}" 2>/dev/null | grep -o '[0-9][0-9][0-9][0-9]*' | head -1)
            if [ -n "$found_port" ] && [ "$found_port" -ge 3000 ] && [ "$found_port" -le 9999 ]; then
                port="$found_port"
                break
            fi
        fi
    done

    # If still default, check uvicorn command line
    for file in main.py app.py server.py __main__.py; do
        if [ -f "${service_path}/${file}" ] && grep -q "uvicorn" "${service_path}/${file}"; then
            # Found uvicorn, use 8000
            port="8000"
            break
        fi
    done

    echo "$port"
}

# Extract port from Node.js service
extract_port_node() {
    local service_path="$1"
    local port="3000"  # default

    # Check package.json for port in scripts
    if [ -f "${service_path}/package.json" ]; then
        local script_port=$(grep -o 'PORT[=\s]*[0-9][0-9]*' "${service_path}/package.json" 2>/dev/null | grep -o '[0-9][0-9]*' | head -1)
        if [ -n "$script_port" ]; then
            port="$script_port"
        fi
    fi

    # Check main files
    for file in index.js app.js server.js main.js src/index.js src/app.js src/server.js src/main.js; do
        if [ -f "${service_path}/${file}" ]; then
            local found_port=$(grep -o 'PORT.*[0-9][0-9][0-9][0-9]' "${service_path}/${file}" 2>/dev/null | grep -o '[0-9][0-9][0-9][0-9][0-9]*' | head -1)
            if [ -n "$found_port" ]; then
                port="$found_port"
                break
            fi
        fi
    done

    echo "$port"
}

# Find entry point for Python service
find_python_entrypoint() {
    local service_path="$1"
    local framework="$2"

    # Common entry point files in priority order
    for file in main.py app.py server.py api.py application.py __main__.py src/main.py src/app.py; do
        if [ -f "${service_path}/${file}" ]; then
            echo "$file"
            return
        fi
    done

    # If Django, return manage.py
    if [ "$framework" = "django" ] && [ -f "${service_path}/manage.py" ]; then
        echo "manage.py"
        return
    fi

    echo "main.py"  # default
}

# Find entry point for Node.js service
find_node_entrypoint() {
    local service_path="$1"

    # Check package.json for main entry
    if [ -f "${service_path}/package.json" ]; then
        local pkg_main=$(grep -oP '"main"\s*:\s*"\K[^"]+' "${service_path}/package.json" 2>/dev/null)
        if [ -n "$pkg_main" ]; then
            echo "$pkg_main"
            return
        fi
    fi

    # Common entry point files
    for file in index.js app.js server.js main.js src/index.js src/app.js src/server.js src/main.js; do
        if [ -f "${service_path}/${file}" ]; then
            echo "$file"
            return
        fi
    done

    echo "index.js"  # default
}

# Check if service has Dockerfile
has_dockerfile() {
    local service_path="$1"
    [ -f "${service_path}/Dockerfile" ] && echo "true" || echo "false"
}

# Check if service has docker-compose.yml
has_docker_compose() {
    local service_path="$1"
    [ -f "${service_path}/docker-compose.yml" ] && echo "true" || echo "false"
}

# Detect MongoDB dependency
detect_mongodb_dependency() {
    local service_path="$1"
    local language="$2"

    if [ "$language" = "python" ]; then
        if grep -q "pymongo\|motor" "${service_path}/requirements.txt" 2>/dev/null || \
           grep -q "from pymongo\|from motor\|import pymongo\|import motor" "${service_path}"/*.py 2>/dev/null; then
            echo "true"
            return
        fi
    elif [ "$language" = "node" ]; then
        if grep -q '"mongodb"\|"mongoose"' "${service_path}/package.json" 2>/dev/null; then
            echo "true"
            return
        fi
    fi

    echo "false"
}

# Detect PostgreSQL dependency
detect_postgres_dependency() {
    local service_path="$1"
    local language="$2"

    if [ "$language" = "python" ]; then
        if grep -q "psycopg2\|asyncpg\|sqlalchemy" "${service_path}/requirements.txt" 2>/dev/null; then
            echo "true"
            return
        fi
    elif [ "$language" = "node" ]; then
        if grep -q '"pg"\|"postgres"' "${service_path}/package.json" 2>/dev/null; then
            echo "true"
            return
        fi
    fi

    echo "false"
}

# Detect Redis dependency
detect_redis_dependency() {
    local service_path="$1"
    local language="$2"

    if [ "$language" = "python" ]; then
        if grep -q "redis\|aioredis" "${service_path}/requirements.txt" 2>/dev/null; then
            echo "true"
            return
        fi
    elif [ "$language" = "node" ]; then
        if grep -q '"redis"\|"ioredis"' "${service_path}/package.json" 2>/dev/null; then
            echo "true"
            return
        fi
    fi

    echo "false"
}

# Generate service metadata JSON
generate_service_metadata() {
    local service_path="$1"
    local service_name="$2"

    echo -e "${BLUE}🔍 Analyzing service at: ${service_path}${NC}"

    # Detect language
    local language=$(detect_language "$service_path")
    echo -e "${GREEN}  Language: ${language}${NC}"

    if [ "$language" = "unknown" ]; then
        echo -e "${RED}  ❌ Could not detect service language${NC}"
        return 1
    fi

    # Detect framework
    local framework=""
    if [ "$language" = "python" ]; then
        framework=$(detect_python_service "$service_path")
        echo -e "${GREEN}  Framework: ${framework}${NC}"
    elif [ "$language" = "node" ]; then
        framework=$(detect_node_service "$service_path")
        echo -e "${GREEN}  Framework: ${framework}${NC}"
    fi

    # Extract port
    local port=""
    if [ "$language" = "python" ]; then
        port=$(extract_port_python "$service_path")
    elif [ "$language" = "node" ]; then
        port=$(extract_port_node "$service_path")
    else
        port="8080"
    fi
    echo -e "${GREEN}  Port: ${port}${NC}"

    # Find entry point
    local entrypoint=""
    if [ "$language" = "python" ]; then
        entrypoint=$(find_python_entrypoint "$service_path" "$framework")
    elif [ "$language" = "node" ]; then
        entrypoint=$(find_node_entrypoint "$service_path")
    fi
    echo -e "${GREEN}  Entry point: ${entrypoint}${NC}"

    # Check for existing Docker files
    local has_docker=$(has_dockerfile "$service_path")
    local has_compose=$(has_docker_compose "$service_path")

    # Detect dependencies
    local needs_mongodb=$(detect_mongodb_dependency "$service_path" "$language")
    local needs_postgres=$(detect_postgres_dependency "$service_path" "$language")
    local needs_redis=$(detect_redis_dependency "$service_path" "$language")

    echo -e "${BLUE}  Dependencies:${NC}"
    [ "$needs_mongodb" = "true" ] && echo -e "${GREEN}    ✓ MongoDB${NC}"
    [ "$needs_postgres" = "true" ] && echo -e "${GREEN}    ✓ PostgreSQL${NC}"
    [ "$needs_redis" = "true" ] && echo -e "${GREEN}    ✓ Redis${NC}"

    # Generate JSON metadata
    cat <<EOF
{
  "service_name": "${service_name}",
  "language": "${language}",
  "framework": "${framework}",
  "port": ${port},
  "entrypoint": "${entrypoint}",
  "has_dockerfile": ${has_docker},
  "has_docker_compose": ${has_compose},
  "dependencies": {
    "mongodb": ${needs_mongodb},
    "postgres": ${needs_postgres},
    "redis": ${needs_redis}
  }
}
EOF
}

# Export functions if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f detect_python_service
    export -f detect_node_service
    export -f detect_language
    export -f extract_port_python
    export -f extract_port_node
    export -f find_python_entrypoint
    export -f find_node_entrypoint
    export -f has_dockerfile
    export -f has_docker_compose
    export -f detect_mongodb_dependency
    export -f detect_postgres_dependency
    export -f detect_redis_dependency
    export -f generate_service_metadata
fi
