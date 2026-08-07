#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# test-docker.sh — Integration test for setup-docker.sh
# =============================================================================
#
# Tests: Docker Engine installation, group membership, daemon status,
#        compose plugin, idempotency
# =============================================================================

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/container-manager.sh"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Configuration
CONTAINER_NAME="test-docker-$$"
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
# Test 1: Run setup-docker.sh
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 1: Running setup-docker.sh..."

run_in_container "$CONTAINER_NAME" "bash ${TASKS_DIR}/setup-docker.sh" 2>&1 || {
    echo "  ❌ FAIL: setup-docker.sh failed on first run"
    exit 1
}
echo "  ✅ PASS: setup-docker.sh completed successfully"

# ---------------------------------------------------------------------------
# Test 2: Verify Docker is installed
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 2: Verifying Docker installation..."

assert_command_exists "$CONTAINER_NAME" "docker"
assert_command_version_matches "$CONTAINER_NAME" "docker --version" "Docker version [0-9]+\.[0-9]+\.[0-9]+"

# ---------------------------------------------------------------------------
# Test 3: Verify Docker daemon is running
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 3: Verifying Docker daemon..."

assert_service_running "$CONTAINER_NAME" "docker"
assert_service_enabled "$CONTAINER_NAME" "docker"

# ---------------------------------------------------------------------------
# Test 4: Verify user is in docker group
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 4: Verifying user group membership..."

assert_user_in_group "$CONTAINER_NAME" "$USERNAME" "docker"

# ---------------------------------------------------------------------------
# Test 5: Verify Docker Compose plugin
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 5: Verifying Docker Compose plugin..."

assert_command_exists "$CONTAINER_NAME" "docker-compose"
echo "  ✅ PASS: Docker Compose plugin available"
TEST_PASSED=$((TEST_PASSED + 1))

# ---------------------------------------------------------------------------
# Test 6: Idempotency check
# ---------------------------------------------------------------------------
echo ""
echo "▶ Test 6: Idempotency check (second run)..."

assert_script_is_idempotent "$CONTAINER_NAME" "${TASKS_DIR}/setup-docker.sh" "setup-docker"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_test_summary

if [[ $TEST_FAILED -gt 0 ]]; then
    exit 1
fi
