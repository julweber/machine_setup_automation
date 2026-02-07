#!/usr/bin/env bash
set -eu

# ------------ Config --------------
SSHD_PORT="${SSHD_PORT:-2224}"
LM_STUDIO_PORT="${LM_STUDIO_PORT:-1234}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3333}"
KUBERNETES_API_PORT="${KUBERNETES_API_PORT:-6443}"
GNOME_REMOTE_PORT="${GNOME_REMOTE_PORT:-3389}"

echo "Configured env vars:"
echo "SSHD_PORT=$SSHD_PORT"
echo "LM_STUDIO_PORT=$LM_STUDIO_PORT"
echo "OPENWEBUI_PORT=$OPENWEBUI_PORT"
echo "KUBERNETES_API_PORT=$KUBERNETES_API_PORT"
echo "GNOME_REMOTE_PORT=$GNOME_REMOTE_PORT"
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