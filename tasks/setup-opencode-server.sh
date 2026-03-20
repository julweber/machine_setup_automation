#!/usr/bin/env bash
#
# ============================================================================
# Script: setup-opencode-server.sh
# ============================================================================
#
# Description:
#   Installs and configures the Opencode AI Coding Agent Server as a
#   systemd service. This script handles installation via npm, creates
#   a systemd service unit, and optionally configures firewall rules.
#
# Key Actions:
#   1. Validates and displays configuration from environment variables
#   2. Optionally generates a secure random password if requested
#   3. Installs Node.js and npm if not already present
#   4. Installs/updates opencode-ai globally via npm
#   5. Creates systemd service file at /etc/systemd/system/opencode-agent.service
#   6. Enables and starts the opencode-agent.service
#   7. Configures UFW firewall rules to allow traffic on the configured port
#   8. Tests the health endpoint and displays service status
#
# Environment Variables:
#   OPENCODE_PORT                - Port for the server (default: 4096)
#   OPENCODE_HOSTNAME            - Hostname to bind to (default: 0.0.0.0)
#   OPENCODE_SERVER_USERNAME     - Username for authentication (default: opencode)
#   OPENCODE_SERVER_PASSWORD     - Password for authentication (default: empty)
#   OPENCODE_INSTALL_METHOD      - Installation method (default: npm)
#   GENERATE_PASSWORD            - Auto-generate password if true (default: false)
#
# Dependencies:
#   - sudo privileges required
#   - openssl (for password generation)
#   - systemd (for service management)
#   - ufw (optional, for firewall configuration)
#   - curl (optional, for health check testing)
#
# Service Details:
#   - Service Name: opencode-agent.service
#   - Service File: /etc/systemd/system/opencode-agent.service
#   - Runs as: Current user ($USER)
#   - Auto-restart: Enabled with 5-second delay
#
# ============================================================================
#
set -eu

# === Configuration ===
OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCODE_HOSTNAME="${OPENCODE_HOSTNAME:-0.0.0.0}"
OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"
OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-}"
OPENCODE_INSTALL_METHOD="${OPENCODE_INSTALL_METHOD:-npm}"

CURRENT_USER="$USER"
HOME_DIR="$HOME"

echo "Opencode Server Configuration:"
echo "  OPENCODE_PORT=$OPENCODE_PORT"
echo "  OPENCODE_HOSTNAME=$OPENCODE_HOSTNAME"
echo "  OPENCODE_SERVER_USERNAME=$OPENCODE_SERVER_USERNAME"
echo "  OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD:+*** (set)}"
echo "  OPENCODE_INSTALL_METHOD=$OPENCODE_INSTALL_METHOD"
echo "--------------------------------"

# Generate password if GENERATE_PASSWORD is true and password is empty
GENERATE_PASSWORD="${GENERATE_PASSWORD:-false}"
if [[ "$GENERATE_PASSWORD" == "true" && -z "$OPENCODE_SERVER_PASSWORD" ]]; then
    echo ""
    echo "Generating secure random password..."
    OPENCODE_SERVER_PASSWORD=$(openssl rand -base64 32)
    echo ""
    echo "=============================================="
    echo "IMPORTANT: Generated Opencode Server Password"
    echo "=============================================="
    echo ""
    echo "Username: $OPENCODE_SERVER_USERNAME"
    echo "Password: $OPENCODE_SERVER_PASSWORD"
    echo ""
    echo "Please save this password securely. It will not be displayed again."
    echo "You can set OPENCODE_SERVER_PASSWORD environment variable to reuse it."
    echo ""
fi


echo "Installing/Updating Opencode Server..."
if ! command -v npm &> /dev/null; then
    echo "npm is not installed. Installing Node.js and npm..."
    sudo apt update
    sudo apt install -y nodejs npm
fi

echo "Installing opencode globally via npm..."
sudo npm install -g opencode-ai

if ! opencode --version &> /dev/null; then
    echo "Error: Opencode CLI installation failed verification."
    exit 1
fi

echo "Opencode CLI installed/updated successfully."

SERVICE_FILE="/etc/systemd/system/opencode-agent.service"

if [[ -f "$SERVICE_FILE" ]]; then
    echo "Service file already exists at $SERVICE_FILE. Skipping creation."
else
    sudo bash -c "cat > $SERVICE_FILE" << EOF
[Unit]
Description=Opencode AI Coding Agent Server
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Environment="OPENCODE_SERVER_USERNAME=$OPENCODE_SERVER_USERNAME"
Environment="OPENCODE_SERVER_PASSWORD=$OPENCODE_SERVER_PASSWORD"
ExecStart=/usr/local/bin/opencode web --hostname 0.0.0.0 --port 4096
Restart=always
RestartSec=5
WorkingDirectory=$HOME_DIR

[Install]
WantedBy=multi-user.target
EOF

    echo "Service file created."
fi

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Enabling opencode-agent.service..."
sudo systemctl enable opencode-agent.service

echo "Starting opencode-agent.service..."
sudo systemctl start opencode-agent.service

if command -v ufw &> /dev/null; then
    if ! sudo ufw status | grep -qE "^$OPENCODE_PORT "; then
        echo "Adding firewall rule for port $OPENCODE_PORT..."
        sudo ufw allow "$OPENCODE_PORT"
        sudo ufw allow "$OPENCODE_PORT/tcp"
    fi
fi

echo ""
echo "=== Opencode Server Installation Complete ==="
echo "Service Status:"
sudo systemctl status opencode-agent.service --no-pager | head -n 10

if [[ "$OPENCODE_HOSTNAME" != "127.0.0.1" && "$OPENCODE_HOSTNAME" != "localhost" ]]; then
    echo ""
    echo "Testing health endpoint..."
    sleep 3
    if command -v curl &> /dev/null; then
        curl -s "http://$OPENCODE_HOSTNAME:$OPENCODE_PORT/global/health" || true
    fi
fi

echo ""
echo "Opencode server is running on $OPENCODE_HOSTNAME:$OPENCODE_PORT"
echo "Username: $OPENCODE_SERVER_USERNAME"
if [[ -n "$OPENCODE_SERVER_PASSWORD" ]]; then
    echo "Password: *** (configured)"
else
    echo "ATTENTION: No password configured !!!"
fi
