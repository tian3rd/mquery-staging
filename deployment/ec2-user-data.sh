#!/bin/bash

# Set up logging
LOG_FILE="/var/log/ec2-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to log messages with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors
handle_error() {
    local error_code=$?
    log "ERROR: Operation failed with code $error_code"
    exit $error_code
}

# Trap errors
trap handle_error ERR

# Log start
log "Starting EC2 User Data script"

# Update package list
log "Updating package list..."
apt-get update -y || handle_error

# Install git for repository cloning
log "Installing git..."
apt-get install -y git || handle_error

# Clone the repository
log "Cloning repository..."
git clone https://github.com/tian3rd/mquery-staging.git /opt/mquery-staging || handle_error

# Run the setup script
log "Running setup script..."
/opt/mquery-staging/deployment/safe_setup_ec2.sh || handle_error

# Add user to docker group
log "Configuring docker group..."
if ! getent group docker > /dev/null; then
    groupadd docker || handle_error
fi

CURRENT_USER=$(whoami)
if ! id "$CURRENT_USER" | grep -q docker; then
    usermod -aG docker "$CURRENT_USER" || handle_error
    log "Added $CURRENT_USER to docker group"
else
    log "$CURRENT_USER is already in docker group"
fi

# Set up deployment service
log "Setting up deployment service..."
tee /etc/systemd/system/deploy.service > /dev/null <<EOL
[Unit]
Description=Run deployment script on startup
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/mquery-staging/deployment/deploy.sh
RemainAfterExit=true
User=$CURRENT_USER

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload || handle_error
systemctl enable deploy.service || handle_error
systemctl start deploy.service || handle_error

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
        docker-compose -f /opt/mquery-staging/docker-compose.yml down --remove-orphans \
        docker-compose -f /opt/mquery-staging/docker-compose.yml up -d \
    fi \
    sleep 30; \
done'
Restart=always
RestartSec=5
User=$CURRENT_USER

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload || handle_error
systemctl enable container-monitor.service || handle_error
systemctl start container-monitor.service || handle_error

# Log completion
log "EC2 User Data script completed successfully"
exit 0
