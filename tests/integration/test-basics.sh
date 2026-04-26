#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# test-basics.sh — Integration test for setup-basics.sh
# =============================================================================
#
# Tests: essential packages, uv, NVM installation, idempotency
# =============================================================================

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/container-manager.sh"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Configuration
CONTAINER_NAME="test-basics-$$"
REPO_HOST="$(dirname "$SCRIPT_DIR/../")"
REPO_CONTAINER="/machine_setup_automation"
TASKS_DIR="$REPO_CONTAINER/tasks"
USERNAME="testuser"

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
# Test 1: Run setup-basics.sh
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 1: Running setup-basics.sh..."

run_in_container "$CONTAINER_NAME" "bash ${TASKS_DIR}/setup-basics.sh" 2>&1 || {
    echo "  ❌ FAIL: setup-basics.sh failed on first run"
    exit 1
}
echo "  ✅ PASS: setup-basics.sh completed successfully"

# ---------------------------------------------------------------------------
# Test 2: Verify packages are installed
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 2: Verifying installed packages..."

assert_command_exists "$CONTAINER_NAME" "curl"
assert_command_exists "$CONTAINER_NAME" "git"
assert_command_exists "$CONTAINER_NAME" "python3"
assert_command_exists "$CONTAINER_NAME" "jq"
assert_command_exists "$CONTAINER_NAME" "yq"
assert_command_exists "$CONTAINER_NAME" "tmux"
assert_command_exists "$CONTAINER_NAME" "bat"
assert_command_exists "$CONTAINER_NAME" "tldr"
assert_command_exists "$CONTAINER_NAME" "uv"
assert_command_exists "$CONTAINER_NAME" "node"
assert_command_exists "$CONTAINER_NAME" "npm"

# ---------------------------------------------------------------------------
# Test 3: Verify NVM is installed
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 3: Verifying NVM installation..."

assert_file_contains "$CONTAINER_NAME" "/home/${USERNAME}/.nvm/nvm.sh" "NVM"
assert_file_contains "$CONTAINER_NAME" "/home/${USERNAME}/.profile" "NVM_DIR"
echo "  ✅ PASS: NVM installed and configured"
TEST_PASSED=$((TEST_PASSED + 1))

# ---------------------------------------------------------------------------
# Test 4: Idempotency check
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 4: Idempotency check (second run)..."

assert_script_is_idempotent "$CONTAINER_NAME" "${TASKS_DIR}/setup-basics.sh" "setup-basics"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_test_summary

if [[ $TEST_FAILED -gt 0 ]]; then
    exit 1
fi
