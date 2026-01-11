#!/bin/bash
#==============================================================================
# Add Service Script
#==============================================================================
# Purpose: Add a new service to Traefik setup from scratch
# Usage:   ./add-service.sh <service-name> [port] [language]
#
# Arguments:
#   service-name  - Name for the new service (required)
#   port          - Internal port for the service (default: 8000)
#   language      - Service language: python|node (default: python)
#
# Examples:
#   ./add-service.sh my-api
#   ./add-service.sh api-v2 8080 python
#   ./add-service.sh web-app 3000 node
#
# This script will:
#   - Create service directory structure
#   - Generate Dockerfile for specified language
#   - Create boilerplate application files
#   - Add service to docker-compose.yml with Traefik labels
#
# Note: For connecting existing services, use connect-service.sh instead
#==============================================================================

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <service-name> [port] [language]"
    echo "Example: $0 api-v2 8001 python"
    exit 1
fi

SERVICE_NAME=$1
PORT=${2:-8000}
LANGUAGE=${3:-python}

SERVICE_DIR="services/${SERVICE_NAME}"

echo "🔧 Adding new service: ${SERVICE_NAME}"

# Create service directory
mkdir -p "${SERVICE_DIR}"

# Create Dockerfile based on language
if [ "$LANGUAGE" == "python" ]; then
    cat > "${SERVICE_DIR}/Dockerfile" <<EOF
FROM python:3.11-slim

WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE ${PORT}

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "${PORT}", "--reload"]
EOF

    cat > "${SERVICE_DIR}/requirements.txt" <<EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
EOF

    cat > "${SERVICE_DIR}/main.py" <<EOF
from fastapi import FastAPI
from datetime import datetime

app = FastAPI(title="${SERVICE_NAME}")

@app.get("/")
async def root():
    return {"message": "${SERVICE_NAME}"}

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "${SERVICE_NAME}",
        "version": "1.0.0"
    }
EOF

    cat > "${SERVICE_DIR}/.dockerignore" <<EOF
__pycache__
*.pyc
*.pyo
*.pyd
.Python
env/
venv/
.venv/
.pytest_cache/
.coverage
htmlcov/
.git
.gitignore
.dockerignore
README.md
EOF

elif [ "$LANGUAGE" == "node" ]; then
    cat > "${SERVICE_DIR}/Dockerfile" <<EOF
FROM node:20-slim

WORKDIR /app

# Install wget for healthcheck
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE ${PORT}

CMD ["npm", "run", "dev"]
EOF

    cat > "${SERVICE_DIR}/package.json" <<EOF
{
  "name": "${SERVICE_NAME}",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF

    cat > "${SERVICE_DIR}/index.js" <<EOF
const express = require('express');
const app = express();
const PORT = process.env.PORT || ${PORT};

app.use(express.json());

app.get('/', (req, res) => {
  res.json({ message: '${SERVICE_NAME}' });
});

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: '${SERVICE_NAME}',
    version: '1.0.0'
  });
});

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(\\\`${SERVICE_NAME} running on port \\\${PORT}\\\`);
});

process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
});
EOF

    cat > "${SERVICE_DIR}/.dockerignore" <<EOF
node_modules
npm-debug.log
.git
.gitignore
.dockerignore
README.md
.env
.env.local
EOF
fi

echo "✅ Service files created in ${SERVICE_DIR}"
echo ""
echo "📝 Next steps:"
echo "1. Add the following to docker-compose.yml:"
echo ""
cat <<EOF
  ${SERVICE_NAME}:
    build:
      context: ./services/${SERVICE_NAME}
    container_name: ${SERVICE_NAME}
    restart: unless-stopped
    environment:
      - ENV=development
    volumes:
      - ./services/${SERVICE_NAME}:/app:delegated
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${SERVICE_NAME}.rule=Host(\\\`${SERVICE_NAME}.localhost\\\`)"
      - "traefik.http.routers.${SERVICE_NAME}.entrypoints=websecure"
      - "traefik.http.routers.${SERVICE_NAME}.tls=true"
      - "traefik.http.services.${SERVICE_NAME}.loadbalancer.server.port=${PORT}"
      - "traefik.docker.network=traefik"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${PORT}/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s
    depends_on:
      traefik:
        condition: service_healthy
EOF
echo ""
echo "2. Run: docker compose up -d ${SERVICE_NAME}"
echo "3. Access at: https://${SERVICE_NAME}.localhost"
