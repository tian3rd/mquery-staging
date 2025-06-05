#!/bin/sh

# Create data directory if it doesn't exist
if [ ! -d "data" ]; then
    echo "Creating data directory..."
    mkdir -p data
fi

# Give proper permissions
chmod -R 755 data

# Execute the main application
exec uvicorn app:app --host 0.0.0.0 --port 8000 --workers 2
