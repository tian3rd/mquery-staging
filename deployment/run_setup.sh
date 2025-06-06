#!/bin/bash

# Set up logging
LOG_FILE="/var/log/setup.log"
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

# Check if we're running as root
if [ "$EUID" -ne 0 ]; then
    log "This script must be run as root. Attempting to run with sudo..."
    sudo $0 "$@" || handle_error "Failed to run with sudo"
    exit $?
fi

# Run the actual setup script
log "Running setup script with root privileges..."
./safe_setup_ec2.sh || handle_error "Failed to run setup script"

# Verify setup
if [ $? -eq 0 ]; then
    log "Setup completed successfully"
else
    log "Setup failed with error code $?"
    exit 1
fi

# Verify Docker installation
log "Verifying Docker installation..."
docker --version || handle_error "Docker installation failed"
docker-compose --version || handle_error "Docker Compose installation failed"

# Verify service status
log "Verifying Docker service status..."
systemctl status docker --no-pager || handle_error "Docker service failed to start"

# Verify directory permissions
log "Verifying directory permissions..."
if [ ! -w "/opt/mquery-staging" ]; then
    log "Warning: /opt/mquery-staging directory not writable"
    exit 1
fi

# Verify user in docker group
log "Verifying user in docker group..."
if ! groups $USER | grep -q docker; then
    log "Warning: User not in docker group"
    exit 1
fi

# Verify repository
log "Verifying repository..."
if [ ! -d "/opt/mquery-staging/.git" ]; then
    log "Repository not found in deployment directory"
    exit 1
fi

# Final success message
log "Setup completed successfully!"
log "1. Place your docker-compose.yml in /opt/mquery-staging/"
log "2. Place your deployment script in /opt/mquery-staging/deployment/"
log "3. The system will automatically monitor and update your deployment"
