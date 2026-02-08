#!/usr/bin/env bash
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

# Check if opencode is already installed
if command -v opencode &> /dev/null && opencode --version &> /dev/null; then
    echo "Opencode CLI is already installed. Skipping installation."
else
    echo "Installing Opencode Server..."

    case "$OPENCODE_INSTALL_METHOD" in
        npm)
            if ! command -v npm &> /dev/null; then
                echo "npm is not installed. Installing Node.js and npm..."
                sudo apt update
                sudo apt install -y nodejs npm
            fi

            echo "Installing opencode globally via npm..."
            sudo npm install -g @opencode/agent

            if ! opencode --version &> /dev/null; then
                echo "Error: Opencode CLI installation failed verification."
                exit 1
            fi
            ;;
        curl)
            LATEST_RELEASE=$(curl -s https://api.github.com/repos/opencode-ai/opencode/releases/latest | grep '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
            if [[ -z "$LATEST_RELEASE" ]]; then
                echo "Failed to get latest release version. Falling back to v0.1.0"
                LATEST_RELEASE="v0.1.0"
            fi

            DOWNLOAD_URL="https://github.com/opencode-ai/opencode/releases/download/$LATEST_RELEASE/opencode-linux-amd64"

            sudo curl -sL "$DOWNLOAD_URL" -o /usr/local/bin/opencode
            sudo chmod +x /usr/local/bin/opencode

            if ! opencode --version &> /dev/null; then
                echo "Error: Opencode CLI installation failed verification."
                exit 1
            fi
            ;;
        *)
            echo "Error: Unknown install method '$OPENCODE_INSTALL_METHOD'. Valid options: npm, curl"
            exit 1
            ;;
    esac

    echo "Opencode CLI installed successfully."
fi

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
ExecStart=/usr/local/bin/opencode server --host $OPENCODE_HOSTNAME --port $OPENCODE_PORT
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
    echo "Note: No password configured. HTTP basic auth will fail if password is required."
fi
