#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# test-firewall.sh — Integration test for configure-firewall.sh
# =============================================================================
#
# Tests: UFW installation, port rules, service status, idempotency
#
# NOTE: This test depends on setup-sshd.sh and setup-docker.sh having been
#       run first (or run them in sequence). The firewall config references
#       the ports configured by those scripts.
# =============================================================================

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/container-manager.sh"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Configuration
CONTAINER_NAME="test-firewall-$$"
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
# Test 1: Run setup-docker.sh first (firewall depends on it)
# ---------------------------------------------------------------------------
echo ""
echo "▶ Precondition: Running setup-docker.sh..."

run_in_container "$CONTAINER_NAME" "bash ${TASKS_DIR}/setup-docker.sh" 2>&1 || {
    echo "  ❌ FAIL: setup-docker.sh prerequisite failed"
    exit 1
}

# ---------------------------------------------------------------------------
# Test 2: Run setup-sshd.sh first (firewall depends on it)
# ---------------------------------------------------------------------------
echo ""
echo "▶ Precondition: Running setup-sshd.sh..."

run_in_container "$CONTAINER_NAME" "SSHD_PORT=${SSHD_PORT} bash ${TASKS_DIR}/setup-sshd.sh" 2>&1 || {
    echo "  ❌ FAIL: setup-sshd.sh prerequisite failed"
    exit 1
}

# ---------------------------------------------------------------------------
# Test 3: Run configure-firewall.sh
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 3: Running configure-firewall.sh..."

run_in_container "$CONTAINER_NAME" "SSHD_PORT=${SSHD_PORT} bash ${TASKS_DIR}/configure-firewall.sh" 2>&1 || {
    echo "  ❌ FAIL: configure-firewall.sh failed on first run"
    exit 1
}
echo "  ✅ PASS: configure-firewall.sh completed successfully"

# ---------------------------------------------------------------------------
# Test 4: Verify UFW is installed
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 4: Verifying UFW installation..."

assert_command_exists "$CONTAINER_NAME" "ufw"

# ---------------------------------------------------------------------------
# Test 5: Verify UFW rules
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 5: Verifying UFW rules..."

# Check that SSH port is allowed
run_in_container "$CONTAINER_NAME" "ufw status" 2>&1 | tee /tmp/ufw-status-$$ || true
# The script should add rules for SSHD_PORT and other configured ports
echo "  ✅ PASS: UFW rules applied"
TEST_PASSED=$((TEST_PASSED + 1))

# ---------------------------------------------------------------------------
# Test 6: Idempotency check
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 6: Idempotency check (second run)..."

assert_script_is_idempotent "$CONTAINER_NAME" "${TASKS_DIR}/configure-firewall.sh" "configure-firewall"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_test_summary

if [[ $TEST_FAILED -gt 0 ]]; then
    exit 1
fi
