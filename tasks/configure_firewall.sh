#!/usr/bin/env bash
#
# ==============================================================================
# FIREWALL CONFIGURATION SCRIPT
# ==============================================================================
#
# Description:
#   This script configures UFW (Uncomplicated Firewall) rules for a development
#   machine. It allows incoming traffic on specific ports used by various
#   services and applications, then enables the firewall.
#
# Key Actions:
#   1. Displays current firewall status and existing rules
#   2. Configures environment variables for service ports (with defaults)
#   3. Adds UFW allow rules for active services:
#      - SSHD (custom port for SSH access)
#      - LM Studio (local AI model server)
#      - OpenCode Server (code server instance)
#   4. Enables the UFW firewall
#   5. Displays final configured rules
#
# Environment Variables (with defaults):
#   - SSHD_PORT (default: 2224)          - SSH daemon port
#   - LM_STUDIO_PORT (default: 1234)     - LM Studio API port
#   - OPENWEBUI_PORT (default: 3333)     - Open WebUI port (currently disabled)
#   - KUBERNETES_API_PORT (default: 6443) - Kubernetes API port (currently disabled)
#   - GNOME_REMOTE_PORT (default: 3389)  - GNOME Remote Desktop port (currently disabled)
#   - OPENCODE_PORT (default: 4096)      - OpenCode server port
#
# Dependencies:
#   - ufw (Uncomplicated Firewall) must be installed
#   - sudo privileges required for firewall configuration
#
# Notes:
#   - Some services (GNOME Remote, OpenWebUI, Kubernetes) are commented out
#   - Script uses 'set -eu' for strict error handling
#   - Both generic and TCP-specific rules are added for each port
#
# ==============================================================================

set -eu

# ------------ Config --------------
SSHD_PORT="${SSHD_PORT:-2224}"
LM_STUDIO_PORT="${LM_STUDIO_PORT:-1234}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3333}"
KUBERNETES_API_PORT="${KUBERNETES_API_PORT:-6443}"
GNOME_REMOTE_PORT="${GNOME_REMOTE_PORT:-3389}"
OPENCODE_PORT="${OPENCODE_PORT:-4096}"

echo "Configured env vars:"
echo "SSHD_PORT=$SSHD_PORT"
echo "LM_STUDIO_PORT=$LM_STUDIO_PORT"
echo "OPENWEBUI_PORT=$OPENWEBUI_PORT"
echo "KUBERNETES_API_PORT=$KUBERNETES_API_PORT"
echo "GNOME_REMOTE_PORT=$GNOME_REMOTE_PORT"
echo "OPENCODE_PORT=$OPENCODE_PORT"
echo "--------------------------"
echo ""

echo "Firewall status:"
echo "Current firewall status:"
sudo ufw status
echo ""
echo "Currently Configured rules:"
sudo ufw show added
echo "--------------------------"
echo ""

# ------------ firewall rules -------------------

## sshd
echo "Configuring firewall rules for: SSHD - $SSHD_PORT"
sudo ufw allow "$SSHD_PORT"
sudo ufw allow "$SSHD_PORT/tcp"

## LM Studio
echo "Configuring firewall rules for: LM_STUDIO - $LM_STUDIO_PORT"
sudo ufw allow "$LM_STUDIO_PORT"
sudo ufw allow "$LM_STUDIO_PORT/tcp"

## Opencode Server
echo "Configuring firewall rules for: OPENCODE - $OPENCODE_PORT"
sudo ufw allow "$OPENCODE_PORT"
sudo ufw allow "$OPENCODE_PORT/tcp"

## gnome remote
# echo "Configuring firewall rules for: GNOME_REMOTE - $GNOME_REMOTE_PORT"
# sudo ufw allow $GNOME_REMOTE_PORT
# sudo ufw allow $GNOME_REMOTE_PORT/tcp

## openwebui
# echo "Configuring firewall rules for: OPENWEBUI - $OPENWEBUI_PORT"
# sudo ufw allow $OPENWEBUI_PORT
# sudo ufw allow $OPENWEBUI_PORT/tcp

# echo "Configuring firewall rules for: KUBERNETES_API - $KUBERNETES_API_PORT"
# sudo ufw allow $KUBERNETES_API_PORT
# sudo ufw allow $KUBERNETES_API_PORT/tcp

## enable firewall
echo "Enabling firewall"
sudo ufw enable
echo "Firewall enabled"

echo "Configured rules:"
sudo ufw show added
echo ""
echo "-------- FINISHED FIREWALL CONFIGURATION -----------"