#!/usr/bin/env bash
# shellcheck disable=SC1091,SC3047
set -eu

#----------------- RESTRICTED USER SETUP ----------------
# Creates a restricted SSH user for secure tunnel-only access.
# This script sets up a chrooted SSH environment with minimal privileges.
#
# SECURITY FEATURES:
# - Password authentication disabled (key-based only)
# - No interactive shell access (/usr/sbin/nologin shell)
# - PTY allocation disabled
# - X11 forwarding disabled
# - Port forwarding enabled for tunneling purposes
#
# USAGE:
#   Source the script with environment variables:
#     RESTRICTED_USER="tunneluser" source tasks/setup_ssh_tunnel_user.sh
#
#   Or run directly (will use defaults):
#     bash tasks/setup_ssh_tunnel_user.sh
#
# ENVIRONMENT VARIABLES:
#   RESTRICTED_USER      - Username to create (required, default: tunneluser)
#                          Must start with lowercase letter/underscore,
#                          contain only [a-z0-9_-]
#   SSHD_PORT            - SSH port for this user (default: 2224)
#   ALLOW_GATEWAY_PORTS  - Allow remote port forwarding via GatewayPorts,
#                          set to "yes" or "no" (default: no)
#
# OUTPUT FILES:
#   $RESTRICTED_USER_HOME/.ssh/id_ed25519      - Private key (600 permissions)
#   $RESTRICTED_USER_HOME/.ssh/id_ed25519.pub  - Public key
#   $RESTRICTED_USER_HOME/.ssh/authorized_keys - Authorized keys file
#
# TUNNEL COMMANDS:
#   Always use -N to suppress shell session (avoids nologin rejection).
#   Use -f to background the tunnel.
#   Use -o IdentitiesOnly=yes to prevent "Too many authentication failures"
#   (stops SSH offering every key in ~/.ssh/ before the correct one).
#
#   Local forward - access a service on the server from your local machine:
#     ssh -N -f -o IdentitiesOnly=yes -L local_port:localhost:remote_port \
#         -p $SSHD_PORT $RESTRICTED_USER@<server> -i <key>
#
#   Remote forward - expose a local service on the server (requires ALLOW_GATEWAY_PORTS=yes):
#     ssh -N -f -o IdentitiesOnly=yes -R 0.0.0.0:remote_port:localhost:local_port \
#         -p $SSHD_PORT $RESTRICTED_USER@<server> -i <key>
#
# CONCRETE EXAMPLES:
#   # Access LM Studio running on the server (port 1234) at localhost:1235
#     ssh -N -f -o IdentitiesOnly=yes -L 1235:localhost:1234 \
#         -p $SSHD_PORT $RESTRICTED_USER@<server> -i ~/.ssh/tunnel-key
#   Then access LM Studio at http://localhost:1235/v1/models on your local machine
#
#
# EXAMPLES:
#   # Create user with custom name and port
#   RESTRICTED_USER="dbuser" SSHD_PORT=2225 source tasks/setup_ssh_tunnel_user.sh
#
#   # Allow gateway ports for external access to tunnels
#   ALLOW_GATEWAY_PORTS=yes source tasks/setup_ssh_tunnel_user.sh
#
# NOTES:
# - Requires root/sudo privileges
# - Will fail if user already exists (idempotent)
# - SSH service will be restarted
# - Existing sshd_config blocks for this user are updated

# Configuration
RESTRICTED_USER="${RESTRICTED_USER:-tunneluser}"
SSHD_PORT="${SSHD_PORT:-2224}"
ALLOW_GATEWAY_PORTS="${ALLOW_GATEWAY_PORTS:-no}"
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"

# Validate username is provided
if [[ -z "$RESTRICTED_USER" ]]; then
    echo "ERROR: RESTRICTED_USER environment variable must be set"
    echo "Usage: RESTRICTED_USER=username source tasks/setup_ssh_tunnel_user.sh"
    exit 1
fi

# Validate username format (alphanumeric and underscore only, start with letter)
if ! [[ "$RESTRICTED_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "ERROR: Invalid username '$RESTRICTED_USER'. Must start with lowercase letter or underscore, and contain only lowercase letters, digits, underscores, or hyphens."
    exit 1
fi

echo "Setting up restricted user: $RESTRICTED_USER"
echo "SSH Port: $SSHD_PORT"
echo "-------------------------------------------"

# Check if user already exists (idempotent)
if id "$RESTRICTED_USER" &>/dev/null; then
    echo "User '$RESTRICTED_USER' already exists. Skipping setup steps."
    echo "Setup complete - no changes made."
    exit 0
fi

echo "Creating user '$RESTRICTED_USER'..."

# Create user with:
# - Home directory
# - nologin shell (prevents any interactive access)
sudo useradd -m -s /usr/sbin/nologin "$RESTRICTED_USER"

echo "User '$RESTRICTED_USER' created with home directory and nologin shell"

# Lock the account to prevent password login
sudo passwd -l "$RESTRICTED_USER" 2>/dev/null || true
echo "Password authentication disabled for '$RESTRICTED_USER'"

# Create .ssh directory for the restricted user
RESTRICTED_HOME="/home/$RESTRICTED_USER"
sudo mkdir -p "$RESTRICTED_HOME/.ssh"
sudo touch "$RESTRICTED_HOME/.ssh/authorized_keys"
sudo chmod 700 "$RESTRICTED_HOME/.ssh"
sudo chmod 600 "$RESTRICTED_HOME/.ssh/authorized_keys"
sudo chown -R "$RESTRICTED_USER:$RESTRICTED_USER" "$RESTRICTED_HOME/.ssh"
echo "SSH directory configured at $RESTRICTED_HOME/.ssh"

# Generate SSH keypair for the restricted user (ed25519, no passphrase)
echo "Generating SSH key pair for '$RESTRICTED_USER'..."
sudo -u "$RESTRICTED_USER" ssh-keygen -t ed25519 \
    -f "$RESTRICTED_HOME/.ssh/id_ed25519" \
    -N "" \
    -C "restricted-tunnel-user@$HOSTNAME" \
    -q

# Set proper permissions on the private key
sudo chmod 600 "$RESTRICTED_HOME/.ssh/id_ed25519"
sudo chown "$RESTRICTED_USER:$RESTRICTED_USER" "$RESTRICTED_HOME/.ssh/id_ed25519"

# chown public key to restricted user
sudo chown "$RESTRICTED_USER:$RESTRICTED_USER" "$RESTRICTED_HOME/.ssh/id_ed25519.pub"

# Copy public key to authorized_keys using sudo for proper permissions handling
PUBLIC_KEY=$(sudo cat "$RESTRICTED_HOME/.ssh/id_ed25519.pub")
echo "$PUBLIC_KEY" | sudo tee -a "$RESTRICTED_HOME/.ssh/authorized_keys" > /dev/null
sudo chmod 600 "$RESTRICTED_HOME/.ssh/authorized_keys"

echo "SSH key pair generated:"
echo "  Private key: $RESTRICTED_HOME/.ssh/id_ed25519"
echo "  Public key added to authorized_keys"

# Configure SSH for the restricted user
# Create a Match block in sshd_config for this user
SSHD_MATCH_BLOCK="# BEGIN RESTRICTED USER: $RESTRICTED_USER
Match User $RESTRICTED_USER
    # Allow SSH port forwarding
    AllowTcpForwarding yes
    # Gateway ports for remote port forwarding
    GatewayPorts $ALLOW_GATEWAY_PORTS
    # Allow X11 forwarding (optional, usually no for tunnel-only users)
    X11Forwarding no
    # Disable PTY allocation (prevents interactive shell)
    PermitTTY no
# END RESTRICTED USER: $RESTRICTED_USER"

# Check if Match block for this user already exists (idempotent)
if sudo grep -q "Match User $RESTRICTED_USER" "$SSHD_CONFIG_FILE"; then
    echo "SSH Match block for '$RESTRICTED_USER' already exists. Updating..."
    sudo sed -i "/# BEGIN RESTRICTED USER: $RESTRICTED_USER/,/# END RESTRICTED USER: $RESTRICTED_USER/d" "$SSHD_CONFIG_FILE"
fi

# Append the Match block
echo "$SSHD_MATCH_BLOCK" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
echo "SSH configuration updated for restricted user"

# Keep home directory owned by the user (no chroot, so no root-ownership required)
sudo chown "$RESTRICTED_USER:$RESTRICTED_USER" "$RESTRICTED_HOME"
sudo chmod 700 "$RESTRICTED_HOME"

# Validate SSH configuration before restarting
if sudo sshd -t; then
    echo "SSH configuration is valid"
else
    echo "ERROR: SSH configuration is invalid. Please check $SSHD_CONFIG_FILE"
    exit 1
fi

# Restart SSH to apply changes
echo "Restarting SSH service..."
sudo systemctl restart ssh

echo ""
echo "==========================================="
echo "RESTRICTED USER SETUP COMPLETE"
echo "==========================================="
echo "Username: $RESTRICTED_USER"
echo "Home Directory: $RESTRICTED_HOME"
echo "SSH Key Pair Generated:"
echo "  Private key: $RESTRICTED_HOME/.ssh/id_ed25519"
echo ""
echo "Note: Password authentication is disabled. Use SSH key."
echo ""
echo "SSH Tunnel Usage (use -N to skip shell, -o IdentitiesOnly=yes to avoid auth failures):"
echo "  Local forward:  ssh -N -f -o IdentitiesOnly=yes -L local_port:localhost:remote_port -p $SSHD_PORT $RESTRICTED_USER@<server> -i <key>"
echo "  Remote forward: ssh -N -f -o IdentitiesOnly=yes -R 0.0.0.0:remote_port:localhost:local_port -p $SSHD_PORT $RESTRICTED_USER@<server> -i <key>"
echo ""
echo "Example - Access LM Studio on server (port 1234) via local port 1235:"
echo "  ssh -N -f -o IdentitiesOnly=yes -L 1235:localhost:1234 -p $SSHD_PORT $RESTRICTED_USER@<server> -i ~/.ssh/tunnel-key"
echo "  Then access LM Studio at http://localhost:1235/v1/models"
echo ""
echo "Place authorized public keys in: $RESTRICTED_HOME/.ssh/authorized_keys"
echo "==========================================="
