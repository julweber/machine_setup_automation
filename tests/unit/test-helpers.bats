#!/usr/bin/env bats
# shellcheck shell=bash
# =============================================================================
# test-helpers.bats — Unit tests for lib/helpers.sh
# =============================================================================
#
# Tests the shared helper library functions without needing Docker.
# These are fast (~ms per test) and catch issues before integration testing.
#
# Run with: bats tests/unit/test-helpers.bats
# Install bats: pip install bats-core  or  brew install bats-core
# =============================================================================

# Source the helpers library
load '../lib/test-helpers.sh'

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------

@test "step function outputs with arrow prefix" {
    # Capture output of step function
    run bash -c 'source lib/helpers.sh; step "test message"'
    [[ "$output" =~ "▶ test message" ]]
}

@test "info function outputs with [INFO] prefix" {
    run bash -c 'source lib/helpers.sh; info "test info"'
    [[ "$output" =~ "[INFO]" ]]
    [[ "$output" =~ "test info" ]]
}

@test "success function outputs with [OK] prefix" {
    run bash -c 'source lib/helpers.sh; success "test success"'
    [[ "$output" =~ "[OK]" ]]
    [[ "$output" =~ "test success" ]]
}

@test "error function outputs with [ERROR] prefix and exits" {
    run bash -c 'source lib/helpers.sh; error "test error"'
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "[ERROR]" ]]
    [[ "$output" =~ "test error" ]]
}

@test "warn function outputs with [WARN] prefix" {
    run bash -c 'source lib/helpers.sh; warn "test warning"'
    [[ "$output" =~ "[WARN]" ]]
    [[ "$output" =~ "test warning" ]]
}

# ---------------------------------------------------------------------------
# Color variables
# ---------------------------------------------------------------------------

@test "color variables are defined" {
    run bash -c 'source lib/helpers.sh; echo -n "${RED}${GREEN}${YELLOW}${CYAN}${BOLD}${RESET}"'
    [[ -n "$output" ]]
}

# ---------------------------------------------------------------------------
# Guarded definitions (re-sourcing safety)
# ---------------------------------------------------------------------------

@test "helpers can be safely re-sourced" {
    run bash -c 'source lib/helpers.sh; step "first"; source lib/helpers.sh; step "second"'
    [[ "$output" =~ "first" ]]
    [[ "$output" =~ "second" ]]
}

# ---------------------------------------------------------------------------
# Test helper assertions (without Docker)
# ---------------------------------------------------------------------------

@test "assert_command_exists function exists" {
    run bash -c 'source lib/test-helpers.sh; declare -f assert_command_exists'
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "assert_command_exists" ]]
}

@test "assert_service_running function exists" {
    run bash -c 'source lib/test-helpers.sh; declare -f assert_service_running'
    [[ "$status" -eq 0 ]]
}

@test "assert_file_contains function exists" {
    run bash -c 'source lib/test-helpers.sh; declare -f assert_file_contains'
    [[ "$status" -eq 0 ]]
}

@test "assert_user_in_group function exists" {
    run bash -c 'source lib/test-helpers.sh; declare -f assert_user_in_group'
    [[ "$status" -eq 0 ]]
}

@test "assert_script_is_idempotent function exists" {
    run bash -c 'source lib/test-helpers.sh; declare -f assert_script_is_idempotent'
    [[ "$status" -eq 0 ]]
}

@test "print_test_summary outputs results" {
    run bash -c 'source lib/test-helpers.sh; TEST_PASSED=3; TEST_FAILED=1; print_test_summary'
    [[ "$output" =~ "3 passed" ]]
    [[ "$output" =~ "1 failed" ]]
    [[ "$output" =~ "4 total" ]]
}
