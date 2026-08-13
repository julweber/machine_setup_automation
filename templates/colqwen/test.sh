#!/usr/bin/env bash
# =============================================================================
# test.sh - Post-install smoke test for the ColQwen embedding service.
#
# Run once after installation, when the service is up:
#   docker compose up -d      # wait for "Application startup complete"
#   ./test.sh
#
# Exercises the service end-to-end (spec: Behavior 5):
#   GET  /health          readiness                        (T5.9)
#   POST /embed/queries   happy path, dim 128              (T5.2)
#   POST /embed/queries   empty list -> 400                (T5.6)
#   POST /embed/images    two files, count + dim 128       (T5.3)
#   POST /embed/images    non-image -> 400 naming the file (T5.7)
#
# Exit code 0 if all checks pass, 1 otherwise.
# The port is read from the .env next to this script (COLQWEN_PORT); an
# already-set COLQWEN_PORT environment variable takes precedence.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

PASSED=0
FAILED=0
LAST_STATUS=""

pass() { echo -e "  ${GREEN}✓${RESET} $*"; PASSED=$((PASSED + 1)); }
fail() { echo -e "  ${RED}✗${RESET} $*";   FAILED=$((FAILED + 1)); }

# -- Configuration ------------------------------------------------------------
if [[ -z "${COLQWEN_PORT:-}" && -f "${SCRIPT_DIR}/.env" ]]; then
  COLQWEN_PORT="$(grep -E '^COLQWEN_PORT=' "${SCRIPT_DIR}/.env" | tail -n 1 | cut -d '=' -f 2)"
fi
COLQWEN_PORT="${COLQWEN_PORT:-8100}"
BASE_URL="http://localhost:${COLQWEN_PORT}"
TEST_IMAGE="${SCRIPT_DIR}/test.png"
CURL_TIMEOUT=120   # first request after startup can be slow (CUDA warmup)

# -- Pre-flight ---------------------------------------------------------------
for cmd in curl python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}[ERROR]${RESET} '${cmd}' is required but not installed." >&2
    exit 1
  fi
done
if [[ ! -f "$TEST_IMAGE" ]]; then
  echo -e "${RED}[ERROR]${RESET} test image not found: ${TEST_IMAGE}" >&2
  exit 1
fi

RESP="$(mktemp)"
NON_IMAGE="$(mktemp --suffix=.txt 2>/dev/null || mktemp)"
echo "this is not an image" > "$NON_IMAGE"
trap 'rm -f "$RESP" "$NON_IMAGE"' EXIT

# request <expected_status> <curl args...>
# Body goes to $RESP. Returns 0 on status match, 1 on mismatch (status in
# LAST_STATUS), 2 if the connection failed entirely.
request() {
  local expected="$1"; shift
  LAST_STATUS="$(curl -s -o "$RESP" -w '%{http_code}' --max-time "$CURL_TIMEOUT" "$@")" || return 2
  [[ "$LAST_STATUS" == "$expected" ]]
}

# verify_embeddings <expected_count>
# Validates the embeddings JSON in $RESP; prints a one-line summary or a
# one-line error (never a traceback).
verify_embeddings() {
  python3 - "$RESP" "$1" 2>&1 <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        embeddings = json.load(f)["embeddings"]
    expected = int(sys.argv[2])
    assert len(embeddings) == expected, \
        f"expected {expected} embedding(s), got {len(embeddings)}"
    for emb in embeddings:
        assert len(emb) > 0, "empty multi-vector embedding"
        bad = [len(v) for v in emb if len(v) != 128]
        assert not bad, f"vector dims != 128 found: {bad[:3]}"
    print(f"{len(embeddings)} embedding(s), "
          f"{len(embeddings[0])} vectors each, dim 128")
except Exception as exc:  # noqa: BLE001 - single-line error for the report
    print(f"invalid response: {exc}")
    sys.exit(1)
PY
}

echo -e "${BOLD}ColQwen smoke test -> ${BASE_URL}${RESET}"

# -- T5.9: /health ------------------------------------------------------------
echo -e "\n${BOLD}> GET /health${RESET}"
request 200 "${BASE_URL}/health"
case $? in
  0) pass "service is ready (200)" ;;
  2)
    fail "cannot connect to ${BASE_URL}"
    echo -e "    Is the service up? Start it with:   docker compose up -d"
    echo -e "    Model may still be loading - check: docker compose logs -f colqwen"
    exit 1
    ;;
  *)
    fail "unexpected status ${LAST_STATUS} (expected 200)"
    exit 1
    ;;
esac

# -- T5.2: /embed/queries happy path -------------------------------------------
echo -e "\n${BOLD}> POST /embed/queries (one query)${RESET}"
if request 200 -X POST "${BASE_URL}/embed/queries" \
     -H 'Content-Type: application/json' \
     -d '{"queries": ["What is the total amount on this invoice?"]}'; then
  if out="$(verify_embeddings 1)"; then
    pass "200 -> ${out}"
  else
    fail "${out}"
  fi
else
  fail "unexpected status ${LAST_STATUS:-<none>} (expected 200)"
fi

# -- T5.6: /embed/queries empty list -> 400 ------------------------------------
echo -e "\n${BOLD}> POST /embed/queries (empty list)${RESET}"
if request 400 -X POST "${BASE_URL}/embed/queries" \
     -H 'Content-Type: application/json' -d '{"queries": []}'; then
  pass "empty query list rejected (400)"
else
  fail "unexpected status ${LAST_STATUS:-<none>} (expected 400)"
fi

# -- T5.3: /embed/images with two files ----------------------------------------
echo -e "\n${BOLD}> POST /embed/images (two images)${RESET}"
if request 200 -X POST "${BASE_URL}/embed/images" \
     -F "files=@${TEST_IMAGE}" -F "files=@${TEST_IMAGE}"; then
  if out="$(verify_embeddings 2)"; then
    pass "200 -> ${out}"
  else
    fail "${out}"
  fi
else
  fail "unexpected status ${LAST_STATUS:-<none>} (expected 200)"
fi

# -- T5.7: /embed/images with a non-image -> 400 naming the file ----------------
echo -e "\n${BOLD}> POST /embed/images (non-image file)${RESET}"
if request 400 -X POST "${BASE_URL}/embed/images" -F "files=@${NON_IMAGE}"; then
  if grep -q "$(basename "$NON_IMAGE")" "$RESP"; then
    pass "non-image rejected (400), offending file named"
  else
    fail "400 returned, but the offending file is not named in the response"
  fi
else
  fail "unexpected status ${LAST_STATUS:-<none>} (expected 400)"
fi

# -- Summary --------------------------------------------------------------------
echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${BOLD}${GREEN}All ${PASSED} checks passed.${RESET}"
  exit 0
fi
echo -e "${BOLD}${RED}${FAILED} check(s) failed${RESET} (${PASSED} passed)."
exit 1
