#!/bin/bash

# Create data directory if it doesn't exist
if [ ! -d "data" ]; then
    echo "Creating data directory..."
    mkdir -p data
fi

# Give proper permissions
chmod -R 755 data
