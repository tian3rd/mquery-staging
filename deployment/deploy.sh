#!/bin/bash

# Set up logging
LOG_FILE="/opt/mquery-staging/deployment.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to log messages with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors
handle_error() {
    local error_code=$?
    log "ERROR: $1 failed with code $error_code"
    exit $error_code
}

# Trap errors
trap handle_error ERR

# Configuration
ECR_IMAGE="905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest"
REPO_URL="https://github.com/tian3rd/mquery-staging.git"
DEPLOYMENT_DIR="/opt/mquery-staging"
HEALTH_CHECK_URL="http://localhost:8000/health"

# Check if we're in the deployment directory
if [ "$PWD" != "$DEPLOYMENT_DIR" ]; then
    cd "$DEPLOYMENT_DIR" || handle_error "Failed to change to deployment directory"
fi

# Check if git is installed
if ! command -v git >/dev/null 2>&1; then
    log "Git is not installed"
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose >/dev/null 2>&1; then
    log "Docker Compose is not installed"
    exit 1
fi

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    log "Cloning repository..."
    git clone "$REPO_URL" "$DEPLOYMENT_DIR" || handle_error "Failed to clone repository"
    cd "$DEPLOYMENT_DIR" || handle_error "Failed to change to deployment directory"
else
    log "Updating repository..."
    git fetch origin || handle_error "Failed to fetch from origin"
    git reset --hard origin/backend || handle_error "Failed to reset to backend branch"
fi

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    log "docker-compose.yml not found"
    exit 1
fi

# Check if we have proper permissions
if [ ! -w "docker-compose.yml" ]; then
    log "No write permissions to docker-compose.yml"
    exit 1
fi

# Stop and remove existing containers
log "Stopping and removing existing containers..."
docker-compose down --remove-orphans || handle_error "Failed to stop containers"

# Pull latest image
log "Pulling latest image from ECR..."
docker pull "$ECR_IMAGE" || handle_error "Failed to pull Docker image"

# Start new containers
log "Starting new containers..."
docker-compose up -d || handle_error "Failed to start containers"

# Wait for service to start
log "Waiting for service to start..."
sleep 5

# Verify service health
log "Verifying service health..."
if ! curl -s "$HEALTH_CHECK_URL" | grep -q '"status": "ok"'; then
    log "Health check failed! Rolling back..."
    docker-compose down --remove-orphans || handle_error "Failed to rollback"
    exit 1
fi

log "Deployment successful!"
exit 0
