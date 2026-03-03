#!/usr/bin/env bash
# shellcheck disable=SC1091,SC3047
set -eu

#----------------- RESTRICTED USER SETUP ----------------
# Creates a restricted SSH user for secure tunnel-only access.
# This script sets up a chrooted SSH environment with minimal privileges.
#
# SECURITY FEATURES:
# - Password authentication disabled (key-based only)
# - Chroot jail to user's home directory
# - No interactive shell access (ForceCommand /bin/true)
# - PTY allocation disabled
# - X11 forwarding disabled
# - Restricted PATH environment
# - Port forwarding enabled for tunneling purposes
#
# USAGE:
#   Source the script with environment variables:
#     RESTRICTED_USER="tunneluser" source tasks/setup_restricted_user.sh
#
#   Or run directly (will use defaults):
#     bash tasks/setup_restricted_user.sh
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
#   $RESTRICTED_USER_HOME/data                 - User-writable data directory
#
# TUNNEL COMMANDS:
#   Local forward (outbound):
#     ssh -L local_port:dest_host:dest_port \
#         -p $SSHD_PORT $RESTRICTED_USER@<server>
#
#   Remote forward (inbound):
#     ssh -R remote_port:local_host:local_port \
#         -p $SSHD_PORT $RESTRICTED_USER@<server>
#
#   With gateway port binding (requires ALLOW_GATEWAY_PORTS=yes):
#     ssh -R 0.0.0.0:remote_port:local_host:local_port \
#         -p $SSHD_PORT $RESTRICTED_USER@<server>
#
# CONCRETE EXAMPLES:
#   # Forward LM Studio port 1234 to local port 1235 (remote -> local)
#     ssh -R 0.0.0.0:1235:localhost:1234 \
#         -p $SSHD_PORT $RESTRICTED_USER@<server>
#   Then access LM Studio at http://localhost:1235/v1/models on your local machine
#
#
# EXAMPLES:
#   # Create user with custom name and port
#   RESTRICTED_USER="dbuser" SSHD_PORT=2225 source tasks/setup_restricted_user.sh
#
#   # Allow gateway ports for external access to tunnels
#   ALLOW_GATEWAY_PORTS=yes source tasks/setup_restricted_user.sh
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
    echo "Usage: RESTRICTED_USER=username source tasks/setup_restricted_user.sh"
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
# - rbash (restricted bash) as shell
sudo useradd -m -s /bin/rbash "$RESTRICTED_USER"

echo "User '$RESTRICTED_USER' created with home directory and rbash shell"

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

# Copy public key to authorized_keys
cat "$RESTRICTED_HOME/.ssh/id_ed25519.pub" >> "$RESTRICTED_HOME/.ssh/authorized_keys"
sudo chmod 600 "$RESTRICTED_HOME/.ssh/authorized_keys"

echo "SSH key pair generated:"
echo "  Private key: $RESTRICTED_HOME/.ssh/id_ed25519"
echo "  Public key added to authorized_keys"

# Set up restrictive home directory permissions
# User owns their home, no group/other access
sudo chmod 700 "$RESTRICTED_HOME"
sudo chown "$RESTRICTED_USER:$RESTRICTED_USER" "$RESTRICTED_HOME"
echo "Home directory permissions set to 700"

# Create a restricted PATH environment
# User can only run basic commands needed for SSH tunneling
RESTRICTED_BIN="$RESTRICTED_HOME/bin"
sudo mkdir -p "$RESTRICTED_BIN"

# Create .bashrc_profile to set restricted PATH
sudo tee "$RESTRICTED_HOME/.bashrc" > /dev/null << 'BASHRC_EOF'
# Restricted bash profile - minimal PATH
export PATH="$HOME/bin"
# Disable common escape commands
unset BASH_ENV
BASHRC_EOF

sudo chown "$RESTRICTED_USER:$RESTRICTED_USER" "$RESTRICTED_HOME/.bashrc"
sudo chmod 644 "$RESTRICTED_HOME/.bashrc"

# Create .bash_profile for login shell
sudo tee "$RESTRICTED_HOME/.bash_profile" > /dev/null << 'BASHPROFILE_EOF'
# Restricted bash profile
export PATH="$HOME/bin"
# Source bashrc if exists
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
BASHPROFILE_EOF

sudo chown "$RESTRICTED_USER:$RESTRICTED_USER" "$RESTRICTED_HOME/.bash_profile"
sudo chmod 644 "$RESTRICTED_HOME/.bash_profile"

echo "Restricted PATH environment configured"

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
    # Force the user to only use their home directory
    ChrootDirectory $RESTRICTED_HOME
    # Force command to prevent shell access (tunnel only)
    ForceCommand /bin/true
# END RESTRICTED USER: $RESTRICTED_USER"

# Check if Match block for this user already exists (idempotent)
if sudo grep -q "Match User $RESTRICTED_USER" "$SSHD_CONFIG_FILE"; then
    echo "SSH Match block for '$RESTRICTED_USER' already exists. Updating..."
    sudo sed -i "/# BEGIN RESTRICTED USER: $RESTRICTED_USER/,/# END RESTRICTED USER: $RESTRICTED_USER/d" "$SSHD_CONFIG_FILE"
fi

# Append the Match block
echo "$SSHD_MATCH_BLOCK" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
echo "SSH configuration updated for restricted user"

# For ChrootDirectory to work, the home directory must be owned by root
# We create a subdirectory for the user's actual files
sudo chown root:root "$RESTRICTED_HOME"
sudo chmod 755 "$RESTRICTED_HOME"

# Create user-writable subdirectory
USER_DATA_DIR="$RESTRICTED_HOME/data"
sudo mkdir -p "$USER_DATA_DIR"
sudo chown "$RESTRICTED_USER:$RESTRICTED_USER" "$USER_DATA_DIR"
sudo chmod 700 "$USER_DATA_DIR"
echo "Created user data directory: $USER_DATA_DIR"

# Set up required devices in chroot (for SSH to work)
sudo mkdir -p "$RESTRICTED_HOME/dev"
sudo mkdir -p "$RESTRICTED_HOME/etc"

# Create minimal /etc/passwd and /etc/group for chroot
sudo grep "^$RESTRICTED_USER:" /etc/passwd | sudo tee "$RESTRICTED_HOME/etc/passwd" > /dev/null
sudo grep "^$RESTRICTED_USER:" /etc/group | sudo tee "$RESTRICTED_HOME/etc/group" > /dev/null
echo "Chroot environment configured"

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
echo "User Data Directory: $USER_DATA_DIR"
echo "SSH Key Pair Generated:"
echo "  Private key: $RESTRICTED_HOME/.ssh/id_ed25519"
echo ""
echo "Note: Password authentication is disabled. Use SSH key."
echo ""
echo "SSH Tunnel Usage:"
echo "  Local forward: ssh -L local_port:dest_host:dest_port -p $SSHD_PORT $RESTRICTED_USER@<server>"
echo "  Remote forward: ssh -R remote_port:local_host:local_port -p $SSHD_PORT $RESTRICTED_USER@<server>"
echo ""
echo "Place authorized public keys in: $RESTRICTED_HOME/.ssh/authorized_keys"
echo "==========================================="
