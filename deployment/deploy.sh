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

# Verify IAM role and permissions
log "Verifying IAM role and permissions..."

# Verify we can get caller identity
log "Checking AWS STS..."
CALLER_ID=$(aws sts get-caller-identity 2>&1)
if [ $? -ne 0 ]; then
    log "AWS STS output: $CALLER_ID"
    handle_error "Failed to verify AWS STS - IAM role might not be properly attached"
fi

# Extract role name from caller identity
ROLE=$(echo "$CALLER_ID" | jq -r '.Arn' | awk -F'/' '{print $2}')
if [ -z "$ROLE" ]; then
    handle_error "Failed to extract IAM role name from caller identity"
fi

log "Found IAM role: $ROLE"

# Verify ECR permissions
log "Verifying ECR permissions..."
REPOS=$(aws ecr describe-repositories --repository-names dev/mquery-backend 2>&1)
if [ $? -ne 0 ]; then
    log "ECR describe-repositories output: $REPOS"
    handle_error "Failed to verify ECR permissions"
fi

log "Verified ECR permissions"

# Authenticate with ECR
log "Authenticating with ECR..."

# Verify AWS CLI is configured
log "Verifying AWS CLI configuration..."
aws configure list || handle_error "AWS CLI is not configured"

# Get ECR token
log "Getting ECR token..."
TOKEN=$(aws ecr get-login-password --region ap-southeast-2 2>&1)
if [ $? -ne 0 ]; then
    log "AWS CLI output: $TOKEN"
    handle_error "Failed to get ECR token"
fi

# Create a script to handle Docker authentication
AUTH_SCRIPT="/opt/mquery-staging/ecr-auth.sh"
log "Creating Docker authentication script..."
cat > "$AUTH_SCRIPT" << 'EOL'
#!/bin/bash
TOKEN="$1"

# Login to ECR
echo "$TOKEN" | docker login --username AWS --password-stdin 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com

# Pull the image
docker pull 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest

# Verify the pull
docker inspect 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest
EOL
chmod +x "$AUTH_SCRIPT"

# Run the authentication script
log "Running Docker authentication..."
$AUTH_SCRIPT "$TOKEN" || handle_error "Failed to authenticate and pull image"

log "Docker authentication and image pull successful!"

# Clean up
log "Cleaning up authentication script..."
rm -f "$AUTH_SCRIPT"

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
