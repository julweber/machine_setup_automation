#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/container-manager.sh — Docker container lifecycle for test automation
# =============================================================================
#
# Provides functions to create, manage, and destroy disposable Ubuntu 24.04
# containers with systemd support for testing setup scripts.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/container-manager.sh"
#   create_test_container "my-test"
#   run_in_container "my-test" "bash -c 'docker --version'"
#   destroy_test_container "my-test"
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
TEST_IMAGE="${TEST_IMAGE:-ubuntu:24.04}"
TIMEOUT_WAIT="${TIMEOUT_WAIT:-120}"  # seconds to wait for systemd
CONTAINER_ROOT="${CONTAINER_ROOT:-/}"  # mount point for repo

# ---------------------------------------------------------------------------
# create_test_container
#   Spins up a disposable Ubuntu 24.04 container with systemd running as PID 1.
#   Uses --privileged for full systemd support.
#
# Args:
#   $1 - Container name (unique)
# ---------------------------------------------------------------------------
create_test_container() {
    local name="$1"

    # Clean up any leftover container with the same name
    if docker ps -a --format '{{.Names}}' | grep -qx "$name" 2>/dev/null; then
        echo "[TEST] Removing stale container: $name"
        docker rm -f "$name" >/dev/null 2>&1 || true
    fi

    echo "[TEST] Creating container: $name (image: $TEST_IMAGE)"
    docker run -d \
        --name "$name" \
        --privileged \
        --security-opt seccomp=unconfined \
        "$TEST_IMAGE" \
        /sbin/init &>/dev/null

    # Wait for systemd to be ready
    local elapsed=0
    while ! docker exec "$name" bash -c "systemctl is-system-running &>/dev/null" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [[ $elapsed -ge $TIMEOUT_WAIT ]]; then
            echo "[FAIL] Timeout waiting for systemd in $name"
            docker logs "$name" 2>&1 || true
            return 1
        fi
    done
    echo "[OK] Container $name ready (${elapsed}s)"
}

# ---------------------------------------------------------------------------
# destroy_test_container
#   Removes the container and its image layers if no other container uses them.
#   Always runs cleanup regardless of test outcome.
#
# Args:
#   $1 - Container name
# ---------------------------------------------------------------------------
destroy_test_container() {
    local name="$1"
    echo "[TEST] Cleaning up container: $name"
    # Capture logs for debugging on failure
    if docker ps -a --format '{{.Names}}' | grep -qx "$name" 2>/dev/null; then
        docker logs --tail 50 "$name" 2>&1 || true
        docker rm -f "$name" >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# run_in_container
#   Executes a command inside the specified container.
#
# Args:
#   $1 - Container name
#   $2 - Command to execute (passed to docker exec)
#   $3 - (optional) User to run as (default: root)
# ---------------------------------------------------------------------------
run_in_container() {
    local name="$1"
    local cmd="$2"
    local user="${3:-root}"

    docker exec -u "$user" "$name" bash -c "$cmd"
}

# ---------------------------------------------------------------------------
# copy_repo_to_container
#   Copies the automation repo into the container.
#
# Args:
#   $1 - Container name
#   $2 - Path to repo on host
#   $3 - (optional) Destination path in container (default: /machine_setup_automation)
# ---------------------------------------------------------------------------
copy_repo_to_container() {
    local name="$1"
    local host_path="$2"
    local dest="${3:-/machine_setup_automation}"

    echo "[TEST] Copying repo to $name:$dest"
    docker cp "$host_path" "$name:$dest" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# setup_test_user
#   Creates a test user with passwordless sudo and home directory.
#
# Args:
#   $1 - Container name
#   $2 - Username (default: testuser)
# ---------------------------------------------------------------------------
setup_test_user() {
    local name="$1"
    local username="${2:-testuser}"

    echo "[TEST] Setting up test user: $username"
    run_in_container "$name" bash -c "
        # Create user
        useradd -m -s /bin/bash ${username}
        echo '${username} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${username}
        chmod 0440 /etc/sudoers.d/${username}

        # Install sudo if not present
        apt-get update -qq && apt-get install -y -qq sudo >/dev/null 2>&1 || true

        chown -R ${username}:${username} /home/${username}
    "
}

# ---------------------------------------------------------------------------
# install_deps_in_container
#   Installs common dependencies needed for testing inside the container.
#
# Args:
#   $1 - Container name
# ---------------------------------------------------------------------------
install_deps_in_container() {
    local name="$1"

    echo "[TEST] Installing test dependencies in $name"
    run_in_container "$name" bash -c "
        apt-get update -qq && apt-get install -y -qq \
            curl wget jq gnupg lsb-release apt-transport-https ca-certificates \
            software-properties-common net-tools iproute2 procps \
            >/dev/null 2>&1 || true
    "
}

# ---------------------------------------------------------------------------
# Container health check
# ---------------------------------------------------------------------------
container_is_running() {
    local name="$1"
    docker ps --format '{{.Names}}' | grep -qx "$name" 2>/dev/null
}
