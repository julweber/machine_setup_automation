#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# tests/lint.sh — template hardening guards
# =============================================================================
#
# Regression guards established by .tickets/improvements-2/07-socket-proxy-drop-privileged.md:
#
#   1. No `privileged:` container in templates/ — the Docker socket proxy in
#      the traefik templates must stay unprivileged. The only allowlisted
#      exception is the concourse worker: it runs a containerd runtime
#      *inside* the container, which requires privileged mode (a functional
#      requirement, not an escape surface).
#   2. No floating/untagged image reference in templates/. Every `image:` line
#      is a `${...}` placeholder that the task script substitutes from a pinned
#      default (ticket 07 for SOCKET_PROXY_IMAGE, ticket 17 for the rest), so a
#      literal `:latest`/`:main` or an untagged `image: foo` in a template means
#      the pinning regressed.
#
# The full lint gate (shellcheck / yamllint / config-sync / CI) is planned in
# ticket 20 (lint-gate-and-ci) and will extend this script in place.
# =============================================================================

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0

# ── Guard 1: no privileged containers (except the documented concourse worker)
privileged_hits="$(grep -rn "privileged:" templates/ || true)"
if [[ -n "${privileged_hits}" ]]; then
  unallowed="$(echo "${privileged_hits}" | grep -v '^templates/concourse/' || true)"
  if [[ -n "${unallowed}" ]]; then
    echo "FAIL: privileged container in templates/ (outside the concourse allowlist):"
    echo "${unallowed}"
    fail=1
  else
    echo "ok: privileged: only in the concourse worker (containerd runtime requires it)"
  fi
else
  echo "ok: no privileged containers in templates/"
fi

# ── Guard 2: no floating :latest/:main images anywhere in templates/
latest_hits="$(grep -rnE "image: [^$]\S*:(latest|main)[[:space:]]*$" templates/ || true)"
if [[ -n "${latest_hits}" ]]; then
  echo "FAIL: floating :latest/:main image in templates/ (render the image from a"
  echo "      script-level *_IMAGE default instead — see ticket improvements-2/17):"
  echo "${latest_hits}"
  fail=1
else
  echo "ok: no floating :latest/:main images in templates/"
fi

# ── Guard 3: no untagged image pulls. An `image:` value without `${`, a `:` tag
# or a `@digest` resolves to `:latest`. Locally BUILT images are not pulls, so
# the nanobot stack (image + build: in the same service) is allowlisted.
untagged_hits="$(grep -rnE '^[[:space:]]*image:[[:space:]]+"?[A-Za-z0-9][A-Za-z0-9._/-]*"?[[:space:]]*$' templates/ \
  | grep -v '^templates/nanobot/' || true)"
if [[ -n "${untagged_hits}" ]]; then
  echo "FAIL: untagged image pull in templates/ (implicitly :latest):"
  echo "${untagged_hits}"
  fail=1
else
  echo "ok: no untagged image pulls in templates/ (nanobot builds locally)"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "lint guards: FAIL"
  exit 1
fi
echo "lint guards: PASS"
