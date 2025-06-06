#!/bin/bash

# Set up logging
LOG_FILE="/var/log/health-check.log"
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

# Check if we're in the deployment directory
if [ "$PWD" != "/opt/mquery-staging" ]; then
    cd "/opt/mquery-staging" || handle_error "Failed to change to deployment directory"
fi

# Verify repository
log "Verifying repository..."
if [ ! -d ".git" ]; then
    log "No git repository found"
    exit 1
fi

# Check if Docker is running
log "Checking Docker service..."
if ! systemctl is-active --quiet docker; then
    log "Docker service is not running"
    exit 1
fi

# Check if containers are running
log "Checking running containers..."
if ! docker ps | grep -q "Up"; then
    log "No containers are running"
    exit 1
fi

# Check health endpoint
log "Checking health endpoint..."
if ! curl -s "http://localhost:8000/health" | grep -q '"status": "ok"'; then
    log "Health check endpoint failed"
    exit 1
fi

log "Health check passed"
exit 0
