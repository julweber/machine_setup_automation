#!/usr/bin/env bash

# usage
# general: 
# ./ssh-port-forward.sh $LOCAL_PORT $TARGET_MACHINE $REMOTE_PORT $TARGET_MACHINE_SSH_USER $TARGET_MACHINE_SSH_PORT
# e.g.:
# ./ssh-port-forward.sh 3333 192.168.0.3 3333 myuser 2224
# ./ssh-port-forward.sh --help

usage() {
    cat <<EOF
Usage: $0 <local_port> <remote_host> <remote_port> <ssh_user> [ssh_port]

Establishes an SSH local port forward: local port <local_port> on this
machine is forwarded to localhost:<remote_port> on <remote_host>.

Arguments:
  local_port    Local port to bind (numeric)
  remote_host   Host to connect to via SSH (IP or hostname)
  remote_port   Port on the remote host to forward to (numeric)
  ssh_user      SSH user on the remote host
  ssh_port      SSH port of the remote server (optional, default: 22)

Options:
  -h, --help    Show this help and exit

Example:
  $0 3333 192.168.0.3 3333 myuser 2224
EOF
}

# Handle help flag before positional arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

# Parameters
LOCAL_PORT=$1
REMOTE_HOST=$2
REMOTE_PORT=$3
SSH_USER=$4
SSH_PORT=$5

# Colored status messages
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if all parameters are provided
if [ -z "$LOCAL_PORT" ] || [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_PORT" ] || [ -z "$SSH_USER" ]; then
    echo -e "${RED}Error: Missing parameters. Usage: $0 <local_port> <remote_host> <remote_port> <ssh_user> <optional: sshd port of the remote server>${YELLOW}"
    exit 1
fi

if [ -z "$SSH_PORT" ]; then
    SSH_PORT=22
fi

# Validate port numbers are numeric
if ! [[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] || ! [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Ports must be numeric.${YELLOW}"
    exit 1
fi

echo -e "${GREEN}[STATUS]${NC} Forwarding local port ${LOCAL_PORT} to ${REMOTE_HOST}:${REMOTE_PORT} via SSH user ${SSH_USER}"
echo -e "${YELLOW}[INFO]${NC} Establishing SSH connection..."
ssh -p "${SSH_PORT}" -N -L "${LOCAL_PORT}:localhost:${REMOTE_PORT}" "${SSH_USER}@${REMOTE_HOST}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} SSH port forwarding established successfully!"
else
    echo -e "${RED}[ERROR]${NC} Failed to establish SSH port forwarding!"
    exit 1
fi

echo -e "${YELLOW}[INFO]${NC} Press Ctrl+C to stop the forwarding process..."
# Keep the process running to maintain the port forward
while true; do
    sleep 1
done