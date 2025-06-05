#!/bin/bash

# Update code from git
echo "Pulling latest code from git..."
git pull

# Pull latest image from ECR
echo "Pulling latest image from ECR..."
docker-compose pull

# Stop and remove existing containers
echo "Stopping existing containers..."
docker-compose down

# Start new containers
echo "Starting new containers..."
docker-compose up -d

# Verify deployment
echo "Verifying deployment..."
docker-compose ps

# Wait for healthcheck
echo "Waiting for healthcheck..."
for i in {1..30}; do
    curl -s http://localhost:8000/health >/dev/null && break
    echo "Waiting for healthcheck... ($i/30)"
    sleep 2
done

echo "Deployment complete!"
