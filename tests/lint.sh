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
#   2. No floating `:latest` image in the traefik templates — the socket
#      proxy image is pinned to tag + digest by tasks/setup-traefik.sh
#      (SOCKET_PROXY_IMAGE). Pinning the remaining non-traefik `:latest`
#      images (concourse, hermes, opencode) is ticket 17; once it lands,
#      widen check 2 to all of templates/.
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

# ── Guard 2: no floating :latest images in the traefik templates
latest_hits="$(grep -rn "image: .*:latest" templates/traefik/ || true)"
if [[ -n "${latest_hits}" ]]; then
  echo "FAIL: floating :latest image in templates/traefik/:"
  echo "${latest_hits}"
  fail=1
else
  echo "ok: no floating :latest images in templates/traefik/"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "lint guards: FAIL"
  exit 1
fi
echo "lint guards: PASS"
