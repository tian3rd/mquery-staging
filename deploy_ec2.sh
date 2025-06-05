#!/bin/bash

# Update system
sudo apt update && sudo apt upgrade -y

# Install Python and pip
sudo apt install python3-pip python3-venv -y

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Copy your Parquet file to EC2
# You'll need to upload your YouthRisk2007.pq file to EC2
# You can do this using scp or AWS S3

# Set up service to run the FastAPI application
sudo tee /etc/systemd/system/fastapi.service > /dev/null <<EOL
[Unit]
Description=FastAPI Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd and start service
sudo systemctl daemon-reload
sudo systemctl enable fastapi
sudo systemctl start fastapi

# Set up firewall rules
sudo ufw allow 8000
sudo ufw enable

# Print status
systemctl status fastapi --no-pager
