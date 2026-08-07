#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# test-sshd.sh — Integration test for setup-sshd.sh
# =============================================================================
#
# Tests: SSH server installation, config, port, service status, idempotency
# =============================================================================

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/container-manager.sh"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Configuration
CONTAINER_NAME="test-sshd-$$"
REPO_HOST="$(dirname "$SCRIPT_DIR/../")"
REPO_CONTAINER="/machine_setup_automation"
TASKS_DIR="$REPO_CONTAINER/tasks"
USERNAME="testuser"
SSHD_PORT="2224"

# Cleanup on exit (always)
cleanup() {
    destroy_test_container "$CONTAINER_NAME"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
echo ""
echo "[TEST] Setting up test environment..."

create_test_container "$CONTAINER_NAME"
copy_repo_to_container "$CONTAINER_NAME" "$REPO_HOST" "$REPO_CONTAINER"
setup_test_user "$CONTAINER_NAME" "$USERNAME"
install_deps_in_container "$CONTAINER_NAME"

# ---------------------------------------------------------------------------
# Test 1: Run setup-sshd.sh
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 1: Running setup-sshd.sh..."

run_in_container "$CONTAINER_NAME" "SSHD_PORT=${SSHD_PORT} bash ${TASKS_DIR}/setup-sshd.sh" 2>&1 || {
    echo "  ❌ FAIL: setup-sshd.sh failed on first run"
    exit 1
}
echo "  ✅ PASS: setup-sshd.sh completed successfully"

# ---------------------------------------------------------------------------
# Test 2: Verify SSH server is installed
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 2: Verifying OpenSSH server..."

assert_command_exists "$CONTAINER_NAME" "sshd"

# ---------------------------------------------------------------------------
# Test 3: Verify SSH config
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 3: Verifying sshd configuration..."

assert_file_contains "$CONTAINER_NAME" "/etc/ssh/sshd_config" "Port ${SSHD_PORT}"
assert_file_contains "$CONTAINER_NAME" "/etc/ssh/sshd_config" "PubkeyAuthentication yes"
assert_file_contains "$CONTAINER_NAME" "/etc/ssh/sshd_config" "PasswordAuthentication no"

# ---------------------------------------------------------------------------
# Test 4: Verify SSH service
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 4: Verifying SSH service..."

assert_service_running "$CONTAINER_NAME" "sshd"
assert_service_enabled "$CONTAINER_NAME" "sshd"

# ---------------------------------------------------------------------------
# Test 5: Verify .ssh directory
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 5: Verifying .ssh directory..."

assert_file_contains "$CONTAINER_NAME" "/home/${USERNAME}/.ssh/authorized_keys" ""
echo "  ✅ PASS: .ssh directory and authorized_keys exist"
TEST_PASSED=$((TEST_PASSED + 1))

# ---------------------------------------------------------------------------
# Test 6: Idempotency check
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 6: Idempotency check (second run)..."

assert_script_is_idempotent "$CONTAINER_NAME" "${TASKS_DIR}/setup-sshd.sh" "setup-sshd"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_test_summary

if [[ $TEST_FAILED -gt 0 ]]; then
    exit 1
fi
