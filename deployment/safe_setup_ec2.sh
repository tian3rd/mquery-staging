#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a service is running
service_running() {
    systemctl is-active --quiet "$1"
}

# Function to check if a directory exists and has proper permissions
check_directory() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        echo "Creating directory: $dir"
        sudo mkdir -p "$dir"
    fi
    if [ ! -w "$dir" ]; then
        echo "Setting permissions for: $dir"
        sudo chown -R $USER:$USER "$dir"
    fi
}

# Function to check if we're running as root
is_root() {
    [ "$EUID" -eq 0 ]
}

# Function to check if user is in docker group
in_docker_group() {
    groups $USER | grep -q docker
}

# Main setup function
setup_ec2() {
    # Update package list
    echo "Updating package list..."
    apt-get update -y

    # Install Docker if needed
    if ! command_exists docker; then
        echo "Installing Docker..."
        apt-get install -y docker.io
    fi

    # Install Docker Compose if needed
    if ! command_exists docker-compose; then
        echo "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi

    # Start Docker service if not running
    if ! service_running docker; then
        echo "Starting Docker service..."
        systemctl start docker
        systemctl enable docker
    fi

    # Create system directories
    check_directory "/opt/mquery-staging"
    check_directory "/var/backups"

    # Set up Docker resources
    if [ ! -f "/etc/systemd/system/docker.service.d/override.conf" ]; then
        echo "Setting up Docker resources..."
        tee /etc/systemd/system/docker.service.d/override.conf > /dev/null <<EOL
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --default-runtime=nvidia --storage-driver=overlay2
EOL
        systemctl daemon-reload
        systemctl restart docker
    fi

    # Set up cleanup cron job
    if [ ! -f "/etc/cron.daily/docker-cleanup" ]; then
        echo "Setting up Docker cleanup..."
        tee /etc/cron.daily/docker-cleanup > /dev/null <<EOL
#!/bin/bash
docker container prune -f
docker image prune -f
docker volume prune -f
EOL
        chmod +x /etc/cron.daily/docker-cleanup
    fi

    # Add user to docker group if needed
    if ! in_docker_group; then
        echo "Adding user to docker group..."
        sudo usermod -aG docker $USER
        echo "Please log out and log back in for group changes to take effect"
    fi

    # Copy deployment script
    if [ ! -f "/opt/mquery-staging/deployment/deploy.sh" ]; then
        echo "Copying deployment script..."
        cp deployment/deploy.sh /opt/mquery-staging/deployment/
        chmod +x /opt/mquery-staging/deployment/deploy.sh
    fi

    # Verify installation
    echo "Verifying installation..."
    docker --version
    docker-compose --version

    echo "Setup complete!"
    echo "1. Place your docker-compose.yml in /opt/mquery-staging/"
    echo "2. Place your deployment script in /opt/mquery-staging/deployment/"
    echo "3. The system will automatically monitor and update your deployment"
}

# Check if we're running as root
if ! is_root; then
    echo "This script must be run as root"
    exit 1
fi

# Run the setup
setup_ec2

# Update package list
echo "Updating package list..."
apt-get update -y

# Check if Docker is installed
if ! command_exists docker; then
    echo "Installing Docker..."
    apt-get install -y docker.io
else
    echo "Docker is already installed"
fi

# Check if Docker Compose is installed
if ! command_exists docker-compose; then
    echo "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose is already installed"
fi

# Check if Docker service is running
if ! service_running docker; then
    echo "Starting Docker service..."
    systemctl start docker
    systemctl enable docker
else
    echo "Docker service is already running"
fi

# Add current user to docker group if not already there
if ! groups $USER | grep -q docker; then
    echo "Adding user to docker group..."
    usermod -aG docker $USER
else
    echo "User is already in docker group"
fi

# Create deployment directory
check_directory "/opt/mquery-staging"

# Set up Docker resources
if [ ! -f "/etc/systemd/system/docker.service.d/override.conf" ]; then
    echo "Setting up Docker resources..."
    tee /etc/systemd/system/docker.service.d/override.conf > /dev/null <<EOL
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --default-runtime=nvidia --storage-driver=overlay2
EOL
    systemctl daemon-reload
    systemctl restart docker
else
    echo "Docker resources already configured"
fi

# Set up Docker Compose log rotation
if [ ! -f "/etc/logrotate.d/docker-compose" ]; then
    echo "Setting up Docker Compose log rotation..."
    tee /etc/logrotate.d/docker-compose > /dev/null <<EOL
/var/lib/docker/containers/*/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
EOL
else
    echo "Docker Compose log rotation already configured"
fi

# Set up health check monitoring
echo "Setting up health check..."
sudo tee /etc/cron.d/health-check > /dev/null <<EOL
*/5 * * * * root curl -s http://localhost:8000/health || (docker-compose down --remove-orphans && docker-compose up -d)
EOL

# Set up automatic updates
echo "Setting up automatic updates..."
sudo tee /etc/cron.daily/docker-update > /dev/null <<EOL
#!/bin/bash
docker pull 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest
docker-compose down --remove-orphans
docker-compose up -d
EOL
sudo chmod +x /etc/cron.daily/docker-update

# Set up log cleanup
echo "Setting up log cleanup..."
sudo tee /etc/cron.daily/log-cleanup > /dev/null <<EOL
#!/bin/bash
find /var/log -type f -name "*.log" -mtime +7 -exec rm -f {} \;
EOL
sudo chmod +x /etc/cron.daily/log-cleanup

# Set up Docker cleanup
echo "Setting up Docker cleanup..."
sudo tee /etc/cron.daily/docker-cleanup > /dev/null <<EOL
#!/bin/bash
docker container prune -f
docker image prune -f
docker volume prune -f
EOL
sudo chmod +x /etc/cron.daily/docker-cleanup

# Set up automatic restart of Docker if it fails
echo "Setting up Docker restart..."
sudo tee /etc/systemd/system/docker-restart.service > /dev/null <<EOL
[Unit]
Description=Restart Docker if it fails
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart docker
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL
sudo systemctl enable docker-restart

# Set up automatic restart of Docker Compose if it fails
echo "Setting up Docker Compose restart..."
sudo tee /etc/systemd/system/docker-compose-restart.service > /dev/null <<EOL
[Unit]
Description=Restart Docker Compose if it fails
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/docker-compose up -d
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL
sudo systemctl enable docker-compose-restart

# Set up monitoring of disk space
echo "Setting up disk space monitoring..."
sudo tee /etc/cron.daily/disk-monitor > /dev/null <<EOL
#!/bin/bash
threshold=85
usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$usage" -gt "$threshold" ]; then
    echo "Warning: Disk usage is at $usage%" | mail -s "Disk Space Alert" admin@example.com
fi
EOL
sudo chmod +x /etc/cron.daily/disk-monitor

# Set up monitoring of CPU and memory usage
echo "Setting up resource monitoring..."
sudo tee /etc/cron.daily/resource-monitor > /dev/null <<EOL
#!/bin/bash
# CPU usage
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
if (( $(echo "$cpu_usage > 85" | bc -l) )); then
    echo "Warning: CPU usage is at $cpu_usage%" | mail -s "CPU Usage Alert" admin@example.com
fi

# Memory usage
mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
if (( $(echo "$mem_usage > 85" | bc -l) )); then
    echo "Warning: Memory usage is at $mem_usage%" | mail -s "Memory Usage Alert" admin@example.com
fi
EOL
sudo chmod +x /etc/cron.daily/resource-monitor

# Set up automatic backup of important files
echo "Setting up backups..."
sudo tee /etc/cron.daily/backup > /dev/null <<EOL
#!/bin/bash
backup_dir="/var/backups/$(date +%Y%m%d)"
mkdir -p $backup_dir
tar -czf $backup_dir/docker-compose.yml /opt/mquery-staging/docker-compose.yml
tar -czf $backup_dir/deployment.tar.gz /opt/mquery-staging/deployment/
EOL
sudo chmod +x /etc/cron.daily/backup

# Set up automatic cleanup of old backups
echo "Setting up backup cleanup..."
sudo tee /etc/cron.daily/backup-cleanup > /dev/null <<EOL
#!/bin/bash
find /var/backups -type d -mtime +7 -exec rm -rf {} \;
EOL
sudo chmod +x /etc/cron.daily/backup-cleanup

# Make the script executable
sudo chmod +x /opt/mquery-staging/deployment/deploy.sh

# Verify installation
echo "Verifying installation..."
docker --version
docker-compose --version

# Note: You may need to log out and log back in for the docker group changes to take effect

# Usage:
# 1. This script is run automatically when the EC2 instance launches (via EC2 User Data)
# 2. The script will:
#    - Set up Docker and Docker Compose
#    - Configure system directories and permissions
#    - Set up automated cleanup and monitoring
#    - Copy the deployment script
# 3. Deployment is handled automatically by CodeDeploy:
#    - CodePipeline triggers CodeDeploy when code is pushed
#    - CodeDeploy runs deploy.sh to update your application
#    - The system monitors health and performs automatic updates
