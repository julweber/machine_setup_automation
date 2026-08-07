#!/usr/bin/env bash
# shellcheck shell=bash
# Convenience wrapper: run a single integration test
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <test-name>  (e.g., test-docker)"
    echo "Available tests:"
    ls "$SCRIPT_DIR/integration/"*.sh | xargs -n1 basename | sed 's/.sh$//'
    exit 1
fi

TEST_FILE="$SCRIPT_DIR/integration/${1}.sh"
if [[ ! -f "$TEST_FILE" ]]; then
    echo "Test not found: $1"
    exit 1
fi

bash "$TEST_FILE"
