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

# Authenticate with ECR
log "Authenticating with ECR..."

# Verify AWS CLI is configured
log "Verifying AWS CLI configuration..."
aws configure list || handle_error "AWS CLI is not configured"

# Function to get ECR token with retry
get_ecr_token() {
    local max_retries=5
    local retry_delay=5
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        log "Attempt $attempt of $max_retries to get ECR token..."
        TOKEN=$(aws ecr get-login-password --region ap-southeast-2)
        if [ -n "$TOKEN" ]; then
            log "Successfully got ECR token"
            
            # Save token to file for service user
            TOKEN_FILE="/opt/mquery-staging/ecr-token"
            echo "$TOKEN" > "$TOKEN_FILE"
            chmod 600 "$TOKEN_FILE"
            
            return 0
        fi
        
        log "Failed to get ECR token, retrying in $retry_delay seconds..."
        sleep $retry_delay
        attempt=$((attempt + 1))
    done
    
    handle_error "Failed to get ECR token after $max_retries attempts"
}

# Get ECR token with retry
get_ecr_token

# Function to login to ECR with retry
ecr_login() {
    local max_retries=5
    local retry_delay=5
    local attempt=1
    local TOKEN_FILE="/opt/mquery-staging/ecr-token"
    
    while [ $attempt -le $max_retries ]; do
        log "Attempt $attempt of $max_retries to login to ECR..."
        if [ -f "$TOKEN_FILE" ]; then
            if cat "$TOKEN_FILE" | docker login --username AWS --password-stdin 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com; then
                log "Successfully logged into ECR"
                return 0
            fi
        fi
        
        log "Failed to login to ECR, retrying in $retry_delay seconds..."
        sleep $retry_delay
        attempt=$((attempt + 1))
    done
    
    handle_error "Failed to login to ECR after $max_retries attempts"
}

# Login to ECR with retry
ecr_login

# Verify login
log "Verifying ECR login..."
if ! docker pull 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest; then
    ERROR=$(docker pull 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest 2>&1)
    log "Initial pull failed: $ERROR"
    
    # Try to get new token and login again
    log "Getting new ECR token and retrying login..."
    get_ecr_token
    ecr_login
    
    # Try pull again
    if ! docker pull 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest; then
        ERROR=$(docker pull 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest 2>&1)
        handle_error "Failed to pull image after retry: $ERROR"
    fi
fi

log "ECR authentication verified successfully!"

# Verify ECR authentication
log "Verifying ECR authentication..."
# First check if we can list repositories
aws ecr describe-repositories || handle_error "Failed to describe ECR repositories"

# Then try to pull the image
log "Testing image pull..."
docker pull 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest
if [ $? -ne 0 ]; then
    # Get detailed error
    ERROR=$(docker pull 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest 2>&1)
    handle_error "Failed to pull image: $ERROR"
fi

log "ECR authentication verified successfully!"

# Pull latest image using docker-compose
log "Pulling latest image from ECR using docker-compose..."
docker-compose pull || handle_error "Failed to pull Docker image"

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
