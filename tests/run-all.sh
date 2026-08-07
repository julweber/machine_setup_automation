#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# run-all.sh — Main test suite entrypoint
# =============================================================================
#
# Usage:
#   ./tests/run-all.sh              # Run everything
#   ./tests/run-all.sh unit         # Run only unit tests
#   ./tests/run-all.sh integration  # Run only integration tests
#   ./tests/run-all.sh integration/test-docker.sh  # Run single test
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║  machine_setup_automation — Test Suite              ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

# Check prerequisites
echo -e "${CYAN}▶ Checking prerequisites...${RESET}"
if ! command -v docker &>/dev/null; then
    echo -e "${RED}✗ Docker is not installed. Please install Docker first.${RESET}"
    exit 1
fi
if ! docker info &>/dev/null; then
    echo -e "${RED}✗ Docker daemon is not running. Please start it.${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Docker is available${RESET}"

if ! command -v bats &>/dev/null; then
    echo -e "${YELLOW}⚠ bats not found — skipping unit tests${RESET}"
fi

# Parse arguments
TARGET="${1:-all}"

# ---------------------------------------------------------------------------
# Run unit tests
# ---------------------------------------------------------------------------
run_unit_tests() {
    echo ""
    echo -e "${BOLD}${CYAN}▶ Phase 1: Static Analysis & Unit Tests${RESET}"
    echo ""

    # ShellCheck on all scripts
    echo -e "${CYAN}▶ ShellCheck...${RESET}"
    if shellcheck "$SCRIPT_DIR/../tasks/"*.sh "$SCRIPT_DIR/../lib/"*.sh 2>&1; then
        echo -e "${GREEN}✓ ShellCheck passed${RESET}"
    else
        echo -e "${RED}✗ ShellCheck found issues${RESET}"
    fi

    # BATS unit tests
    if command -v bats &>/dev/null && [[ -d "$SCRIPT_DIR/unit" ]]; then
        echo -e "${CYAN}▶ BATS unit tests...${RESET}"
        if bats "$SCRIPT_DIR/unit/"*; then
            echo -e "${GREEN}✓ Unit tests passed${RESET}"
        else
            echo -e "${RED}✗ Unit tests failed${RESET}"
        fi
    else
        echo -e "${YELLOW}⚠ Skipping BATS (install with: pip install bats-core or brew install bats-core)${RESET}"
    fi
}

# ---------------------------------------------------------------------------
# Run integration tests
# ---------------------------------------------------------------------------
run_integration_tests() {
    echo ""
    echo -e "${BOLD}${CYAN}▶ Phase 2: Integration Tests (Docker)${RESET}"
    echo ""

    local test_files=()

    if [[ "$TARGET" == "all" || "$TARGET" == "integration" ]]; then
        # Run all integration tests
        test_files=("$SCRIPT_DIR/integration/"*.sh)
    elif [[ -f "$TARGET" ]]; then
        # Run single test file
        test_files=("$TARGET")
    fi

    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo -e "${RED}No test files found for: $TARGET${RESET}"
        exit 1
    fi

    for test_file in "${test_files[@]}"; do
        local test_name
        test_name="$(basename "$test_file" .sh)"
        echo ""
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${BOLD}▶ Test: ${CYAN}$test_name${RESET}"
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

        bash "$test_file"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "$TARGET" in
    unit)
        run_unit_tests
        ;;
    integration)
        run_integration_tests
        ;;
    all)
        run_unit_tests
        run_integration_tests
        ;;
    *)
        # Assume it's a test file path
        if [[ -f "$TARGET" ]]; then
            run_integration_tests
        else
            echo "Usage: $0 [all|unit|integration|test-file.sh]"
            exit 1
        fi
        ;;
esac

echo ""
echo -e "${GREEN}Test suite complete.${RESET}"
