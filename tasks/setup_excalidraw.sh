#!/usr/bin/env bash
#
# ============================================================================
# Excalidraw Docker Setup Script
# ============================================================================
#
# Description:
#   Sets up and runs Excalidraw (a virtual whiteboard for sketching 
#   hand-drawn like diagrams) in a Docker container with persistent runtime.
#
# Key Actions:
#   1. Verifies Docker is installed and available
#   2. Pulls the latest Excalidraw Docker image from Docker Hub
#   3. Checks if an Excalidraw container is already running
#   4. Creates and starts a new container if not already running
#   5. Configures container with auto-restart policy (always)
#   6. Waits for container initialization and verifies it's running
#
# Important Variables:
#   HOST_PORT - The local port where Excalidraw will be accessible (default: 5005)
#
# Dependencies:
#   - Docker must be installed and running (run setup_docker.sh first)
#   - Network port 5005 must be available
#
# Container Details:
#   - Image: excalidraw/excalidraw:latest
#   - Container name: excalidraw
#   - Port mapping: ${HOST_PORT}:80
#   - Restart policy: always (auto-start on system reboot)
#
# Access:
#   After successful setup, Excalidraw is accessible at:
#   http://localhost:5005
#
# ============================================================================
#
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
