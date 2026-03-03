#!/usr/bin/env bash
# shellcheck disable=SC1091
set -eu

HOST_PORT="5005"

#----------------- Excalidraw ----------------
echo "Setting up Excalidraw in Docker..."

# Check if Docker is installed
if ! command -v docker &> /dev/null || ! docker --version &> /dev/null; then
    echo "Docker not found. Please run tasks/setup_docker.sh first."
    exit 1
fi

# Pull the Excalidraw image
echo "Pulling Excalidraw Docker image..."
docker pull excalidraw/excalidraw:latest

# Check if container is already running
if docker ps --format '{{.Names}}' | grep -q '^excalidraw$'; then
    echo "Excalidraw container is already running."
else
    # Run Excalidraw with auto-restart policy
    echo "Starting Excalidraw container..."
    docker run -dit \
        --name excalidraw \
        --restart always \
        -p "${HOST_PORT}:80" \
        excalidraw/excalidraw:latest
    
    echo "Excalidraw started successfully!"
fi

# Wait for container to be ready
echo "Waiting for Excalidraw to start..."
sleep 3

# Verify the container is running
if docker ps --format '{{.Names}}' | grep -q '^excalidraw$'; then
    echo "Excalidraw is running at http://localhost:${HOST_PORT}"
else
    echo "Warning: Excalidraw container may not be running as expected."
fi
