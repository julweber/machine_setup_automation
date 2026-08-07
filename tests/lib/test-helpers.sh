#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/test-helpers.sh — Assertion functions for test automation
# =============================================================================
#
# Provides reusable assertion functions that work inside Docker containers.
# Each function prints PASS/FAIL and returns appropriate exit codes.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
#   assert_command_exists "$CONTAINER" "docker"
#   assert_service_running "$CONTAINER" "docker"
#   assert_file_contains "$CONTAINER" "/etc/ssh/sshd_config" "Port 2224"
# =============================================================================

# Track test results
TEST_PASSED=0
TEST_FAILED=0

# ---------------------------------------------------------------------------
# assert_command_exists
#   Verifies a command is installed and accessible in PATH.
#
# Args:
#   $1 - Container name
#   $2 - Command name
# ---------------------------------------------------------------------------
assert_command_exists() {
    local name="$1"
    local cmd="$2"

    if run_in_container "$name" "command -v $cmd &>/dev/null"; then
        echo "  ✅ PASS: $cmd is installed"
        TEST_PASSED=$((TEST_PASSED + 1))
    else
        echo "  ❌ FAIL: $cmd is NOT installed"
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi
}

# ---------------------------------------------------------------------------
# assert_service_running
#   Verifies a systemd service is active and running.
#
# Args:
#   $1 - Container name
#   $2 - Service name (without .service suffix)
# ---------------------------------------------------------------------------
assert_service_running() {
    local name="$1"
    local service="$2"

    local status
    status=$(run_in_container "$name" "systemctl is-active ${service}.service" 2>/dev/null || echo "unknown")

    if [[ "$status" == "active" ]]; then
        echo "  ✅ PASS: ${service} service is active"
        TEST_PASSED=$((TEST_PASSED + 1))
    else
        echo "  ❌ FAIL: ${service} service is '$status' (expected active)"
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi
}

# ---------------------------------------------------------------------------
# assert_service_enabled
#   Verifies a systemd service is enabled (starts on boot).
#
# Args:
#   $1 - Container name
#   $2 - Service name
# ---------------------------------------------------------------------------
assert_service_enabled() {
    local name="$1"
    local service="$2"

    local status
    status=$(run_in_container "$name" "systemctl is-enabled ${service}.service" 2>/dev/null || echo "unknown")

    if [[ "$status" == "enabled" || "$status" == "static" ]]; then
        echo "  ✅ PASS: ${service} service is enabled"
        TEST_PASSED=$((TEST_PASSED + 1))
    else
        echo "  ❌ FAIL: ${service} service is '$status' (expected enabled)"
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi
}

# ---------------------------------------------------------------------------
# assert_file_contains
#   Verifies a file contains a specific string.
#
# Args:
#   $1 - Container name
#   $2 - File path
#   $3 - Expected string
# ---------------------------------------------------------------------------
assert_file_contains() {
    local name="$1"
    local filepath="$2"
    local expected="$3"

    if run_in_container "$name" "grep -qF '$expected' '$filepath' 2>/dev/null"; then
        echo "  ✅ PASS: $filepath contains '$expected'"
        TEST_PASSED=$((TEST_PASSED + 1))
    else
        echo "  ❌ FAIL: $filepath does NOT contain '$expected'"
        echo "     Content:"
        run_in_container "$name" "cat '$filepath' 2>/dev/null | head -20" | sed 's/^/        /'
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi
}

# ---------------------------------------------------------------------------
# assert_file_not_exists
#   Verifies a file does NOT exist (for idempotency tests).
#
# Args:
#   $1 - Container name
#   $2 - File path
# ---------------------------------------------------------------------------
assert_file_not_exists() {
    local name="$1"
    local filepath="$2"

    if ! run_in_container "$name" "test -f '$filepath'" 2>/dev/null; then
        echo "  ✅ PASS: $filepath does not exist"
        TEST_PASSED=$((TEST_PASSED + 1))
    else
        echo "  ❌ FAIL: $filepath exists (expected not to)"
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi
}

# ---------------------------------------------------------------------------
# assert_user_in_group
#   Verifies a user is a member of a specific group.
#
# Args:
#   $1 - Container name
#   $2 - Username
#   $3 - Group name
# ---------------------------------------------------------------------------
assert_user_in_group() {
    local name="$1"
    local user="$2"
    local group="$3"

    if run_in_container "$name" "id -nG $user | grep -qw '$group'" 2>/dev/null; then
        echo "  ✅ PASS: $user is in group '$group'"
        TEST_PASSED=$((TEST_PASSED + 1))
    else
        echo "  ❌ FAIL: $user is NOT in group '$group'"
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi
}

# ---------------------------------------------------------------------------
# assert_command_version_matches
#   Runs a command and checks its version output contains expected pattern.
#
# Args:
#   $1 - Container name
#   $2 - Command to run (e.g., "docker --version")
#   $3 - Expected pattern (regex)
# ---------------------------------------------------------------------------
assert_command_version_matches() {
    local name="$1"
    local cmd="$2"
    local pattern="$3"

    local output
    output=$(run_in_container "$name" "$cmd" 2>/dev/null || echo "")

    if echo "$output" | grep -qE "$pattern"; then
        echo "  ✅ PASS: $cmd matches '$pattern'"
        TEST_PASSED=$((TEST_PASSED + 1))
    else
        echo "  ❌ FAIL: $cmd does NOT match '$pattern'"
        echo "     Got: $output"
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi
}

# ---------------------------------------------------------------------------
# assert_script_is_idempotent
#   Runs a setup script twice and verifies the second run completes without error.
#   This is the most important test for provisioning scripts.
#
# Args:
#   $1 - Container name
#   $2 - Script path (inside container)
#   $3 - Script name (for logging)
#   $4+ - Environment variables (KEY=value pairs)
# ---------------------------------------------------------------------------
assert_script_is_idempotent() {
    local name="$1"
    local script="$2"
    local script_name="$3"
    shift 3
    local env_vars=("$@")

    echo "  ▶ Running $script_name (first run)..."
    local first_run
    first_run=$(run_in_container "$name" "bash $script" 2>&1 || echo "EXIT:$?")

    if echo "$first_run" | grep -q "^EXIT:"; then
        echo "  ❌ FAIL: First run of $script_name failed"
        echo "     Output: $(echo "$first_run" | tail -5)"
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi
    echo "  ✅ PASS: First run of $script_name succeeded"
    TEST_PASSED=$((TEST_PASSED + 1))

    echo "  ▶ Running $script_name (second run - idempotency check)..."
    local second_run
    second_run=$(run_in_container "$name" "bash $script" 2>&1 || echo "EXIT:$?")

    if echo "$second_run" | grep -q "^EXIT:"; then
        echo "  ❌ FAIL: Second run of $script_name failed (NOT idempotent)"
        echo "     Output: $(echo "$second_run" | tail -5)"
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi

    # Check for "already" or "skipping" or "success" messages on second run
    if echo "$second_run" | grep -qiE "already|skipping|success|configured"; then
        echo "  ✅ PASS: $script_name is idempotent (second run completed cleanly)"
        TEST_PASSED=$((TEST_PASSED + 1))
    else
        echo "  ⚠️  WARN: $script_name second run succeeded but no idempotency message found"
        TEST_PASSED=$((TEST_PASSED + 1))  # still pass if no error
    fi
}

# ---------------------------------------------------------------------------
# print_test_summary
#   Prints a summary of passed/failed tests.
# ---------------------------------------------------------------------------
print_test_summary() {
    local total=$((TEST_PASSED + TEST_FAILED))
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Test Results: $TEST_PASSED passed, $TEST_FAILED failed, $total total"
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo "  ✅ All tests passed!"
    else
        echo "  ❌ $TEST_FAILED test(s) failed"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
