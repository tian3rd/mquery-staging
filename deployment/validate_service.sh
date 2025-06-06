#!/bin/bash

# Wait for service to start
sleep 5

# Check service status
if ! curl -s http://localhost:8000/health | grep -q '"status": "ok"'; then
    echo "Service validation failed"
    exit 1
fi

# Check logs for errors
docker-compose logs | grep -i "error" && exit 1

exit 0
