#!/bin/bash

# Set up logging
LOG_FILE="/var/log/ec2-update.log"
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

# Update package list
log "Updating package list..."
apt-get update -y || handle_error "Failed to update package list"

# Install git if not installed
if ! command -v git >/dev/null 2>&1; then
    log "Installing git..."
    apt-get install -y git || handle_error "Failed to install git"
fi

# Clone or update the repository
REPO_DIR="/opt/mquery-staging"

if [ -d "$REPO_DIR/.git" ]; then
    log "Updating existing repository..."
    cd "$REPO_DIR" || handle_error "Failed to change to repository directory"
    git fetch origin || handle_error "Failed to fetch from origin"
    git reset --hard origin/backend || handle_error "Failed to reset to backend branch"
else
    log "Cloning repository..."
    git clone https://github.com/tian3rd/mquery-staging.git "$REPO_DIR" || handle_error "Failed to clone repository"
    cd "$REPO_DIR" || handle_error "Failed to change to repository directory"
fi

# Ensure deployment directory exists and has proper permissions
if [ ! -d "deployment" ]; then
    log "Creating deployment directory..."
    mkdir -p deployment
    chmod 755 deployment
fi

# Ensure all deployment scripts have proper permissions
log "Setting up script permissions..."
for script in deployment/*.sh; do
    if [ -f "$script" ]; then
        log "Setting permissions for $script..."
        chmod +x "$script"
        if ! [ -x "$script" ]; then
            log "Warning: Failed to set execute permission for $script"
        fi
    fi
done

# Run setup script with proper path
log "Running setup script..."
sudo ./deployment/safe_setup_ec2.sh || handle_error "Failed to run setup script"

# Install required packages
log "Installing required packages..."
apt-get update -y
apt-get install -y bc jq || handle_error "Failed to install bc"

# Set up deployment service
log "Setting up deployment service..."
tee /etc/systemd/system/deploy.service > /dev/null <<EOL
[Unit]
Description=Run deployment script on startup
After=docker.service
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/mquery-staging/deployment/deploy.sh
RemainAfterExit=true
User=$USER
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
WorkingDirectory=/opt/mquery-staging
TimeoutStartSec=600
Restart=on-failure
RestartSec=30

# Ensure proper permissions
PermissionsStartOnly=true
ExecStartPre=/bin/chown -R $USER:$USER /opt/mquery-staging
ExecStartPre=/bin/chmod -R 700 /opt/mquery-staging

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd and start service
log "Reloading systemd and starting service..."
systemctl daemon-reload
systemctl enable deploy.service
systemctl start deploy.service

# Check service status
log "Checking service status..."
if ! systemctl is-active --quiet deploy.service; then
    log "Service failed to start. Checking logs..."
    systemctl status deploy.service
    journalctl -xeu deploy.service
    exit 1
fi

log "Service started successfully!"

# Set up container monitoring
log "Setting up container monitoring..."
tee /etc/systemd/system/container-monitor.service > /dev/null <<EOL
[Unit]
Description=Container health monitor
After=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/bash -c 'while true; do \
    if ! curl -s http://localhost:8000/health | grep -q '""status": "ok""'; then \
        echo "Health check failed, restarting containers" >> /var/log/container-monitor.log \
        docker-compose down --remove-orphans \
        docker-compose up -d \
    fi \
    sleep 30; \
done'
Restart=always
RestartSec=5
User=$USER

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload || handle_error "Failed to reload systemd"
systemctl enable container-monitor.service || handle_error "Failed to enable container monitor"
systemctl start container-monitor.service || handle_error "Failed to start container monitor"

log "EC2 instance update completed successfully!"
exit 0
