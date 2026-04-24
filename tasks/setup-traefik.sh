#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# setup-traefik.sh — Install Traefik v3 reverse proxy
# =============================================================================
#
# PURPOSE: Deploy production-ready Traefik v3 on Ubuntu with Docker Compose.
# Features: TLS via Let's Encrypt, security headers, rate limiting, basic auth.
#
# KEY VARIABLES:
#   TRAEFIK_HOME=/opt/traefik     - Config directory
#   TRAEFIK_DASHBOARD=false       - Enable dashboard (requires DOMAIN)
#   ACME_EMAIL=admin@example.com  - Let's Encrypt email
#   DNS_PROVIDER=                 - Cloudflare or empty for HTTP challenge
#   CF_DNS_API_TOKEN=             - Required if using DNS challenge
#
# USAGE:
#   ./tasks/setup-traefik.sh                      # Default setup
#   TRAEFIK_DASHBOARD=true ACME_EMAIL=x@y.com \
#     ./tasks/setup-traefik.sh --interactive
#
# =============================================================================

set -euo pipefail

# Determine script directory and source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LIB_PATH="$(realpath "${SCRIPT_DIR}/../lib/helpers.sh")"

# shellcheck disable=SC1090
source "${LIB_PATH}" || {
  echo "[ERROR] Shared library not found: ${LIB_PATH}" >&2
  exit 1
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ CONFIGURATION — defaults; override via environment variables           │
# │                                                                         │
# │   ┌──────────────┐    ┌──────────────┐                                 │
# │   │ ENV VARS     │──▶│ Script vars  │                                 │
# │   │ \(optional\)   │    │ \(with defaults\)                            │
# │   └──────────────┘    └──────────────┘                                 │
# │                                                                         │
# │   TRAEFIK_HOME=/opt/traefik    # Config directory                      │
# │   TRAEFIK_DASHBOARD=false      # Enable dashboard                       │
# │   ACME_EMAIL=admin@example.com # Let's Encrypt email                    │
# │   DNS_PROVIDER=                # Cloudflare or empty for HTTP          │
# └─────────────────────────────────────────────────────────────────────────┘

TRAEFIK_HOME="${TRAEFIK_HOME:-/opt/traefik}"
TRAEFIK_IMAGE="${TRAEFIK_IMAGE:-traefik:v3}"
TRAEFIK_DOMAIN="${TRAEFIK_DOMAIN:-traefik.example.com}"
TRAEFIK_DASHBOARD="${TRAEFIK_DASHBOARD:-false}"
ACME_EMAIL="${ACME_EMAIL:-admin@example.com}"
ACME_STAGING="${ACME_STAGING:-false}"
DNS_PROVIDER="${DNS_PROVIDER:-}"
CF_DNS_API_TOKEN="${CF_DNS_API_TOKEN:-}"
TRAEFIK_ADMIN_USER="${TRAEFIK_ADMIN_USER:-admin}"
TRAEFIK_ADMIN_PASS="${TRAEFIK_ADMIN_PASS:-}"
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"
USE_SOCKET_PROXY="${USE_SOCKET_PROXY:-true}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ COLOURS & HELPERS (using library helpers)                              │
# └─────────────────────────────────────────────────────────────────────────┘

# Logging functions are now provided by lib/helpers.sh

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ ARGUMENT PARSING — parse command-line flags                            │
# │                                                                         │
# │   $@ arguments                                                          │
# │        │                                                                  │
# │        ▼                                                                  │
# │   ┌───────────────┐                                                     │
# │   │ for arg in \$@│                                                     │
# │   └──────┬────────┘                                                     │
# │          │                                                              │
# │     ┌────┴────┐                                                          │
# │  --interactive?                                             │
# │        │                                                                  │
# │   YES│NO                                                                   │
# │    ▼       │                                                             │
# │ INTERACTIVE= true │ Ignore unknown                                      │
# │      true     │ flags                                                   │
# └─────────────────────────────────────────────────────────────────────────┘

INTERACTIVE=false

for arg in "$@"; do
  case "$arg" in
    --interactive) INTERACTIVE=true ;;
    *) warn "Unknown flag: ${arg} (ignored)" ;;
  esac
done

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ VALIDATION — ensure ACME_EMAIL is provided                             │
# │                                                                         │
# │     ACME_EMAIL set?                                                     │
# │          │                                                              │
# │   ┌─────┴──────┐                                                        │
# │   │            │                                                        │
# │  YES│           NO                                                       │
# │    ▼            ▼                                                        │
# │ Proceed      Check if default used                                        │
# │              │                                                            │
# │              ▼                                                            │
# │     ┌───────────────┐                                                    │
# │     │ Default email?│                                                    │
# │     └───────┬───────┘                                                    │
# │             │                                                            │
# │          YES│NO                                                          │
# │             ▼                                                            │
# │    Fail with error + instructions                                        │
# │    (exit 1)                                                              │
# └─────────────────────────────────────────────────────────────────────────┘

if [[ "$ACME_EMAIL" == "admin@example.com" ]]; then
  echo ""
  echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${RED}║   ERROR: ACME_EMAIL not configured!                      ║${RESET}"
  echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo "Let's Encrypt requires a valid email address for account registration."
  echo "The default 'admin@example.com' is rejected by Let's Encrypt."
  echo ""
  echo -e "${YELLOW}Please run with your real email:${RESET}"
  echo ""
  echo -e "${BOLD}  ACME_EMAIL=your@email.com ./tasks/setup-traefik.sh${RESET}"
  echo ""
  echo "Examples:"
  echo -e "  ${CYAN}ACME_EMAIL=admin@denkfabrik.space ./tasks/setup-traefik.sh${RESET}"
  echo -e "  ${CYAN}ACME_EMAIL=admin@example.com ./tasks/setup-traefik.sh${RESET}"
  echo ""
  exit 1
fi

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ PRE-FLIGHT CHECKS — verify prerequisites before proceeding             │
# │                                                                         │
# │     ┌─────────────┐                                                     │
# │     │ Docker      │ → Check installed                                   │
# │     └──────┬──────┘                                                     │
# │            ▼                                                              │
# │   ┌─────────────────┐                                                   │
# │   │ Docker daemon   │ → Check running                                   │
# │   └──────┬──────────┘                                                   │
# │          ▼                                                              │
# │   ┌─────────────────┐                                                   │
# │   │ User in docker  │ → Check group membership                          │
# │   └──────┬──────────┘                                                   │
# │          ▼                                                              │
# │   ┌─────────────────┐                                                   │
# │   │ htpasswd        │ → Install if missing                              │
# │   └─────────────────┘                                                   │
# └─────────────────────────────────────────────────────────────────────────┘
step "Running pre-flight checks"

if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not in PATH. Run setup-docker.sh first."
fi
success "Docker $(docker --version | awk '{print $3}' | tr -d ',') detected."

if ! docker info &>/dev/null; then
  error "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi
success "Docker daemon is running."

if ! groups | grep -qw docker; then
  error "Current user is not in the docker group. Fix with: sudo usermod -aG docker \$USER (then log out and back in)"
fi
success "User is in the docker group."

if ! command -v htpasswd &>/dev/null; then
  info "htpasswd not found — installing apache2-utils..."
  if ! sudo apt-get install -y apache2-utils; then
    error "Failed to install apache2-utils. Please install it manually and re-run."
  fi
fi
success "htpasswd is available."

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ IDEMPOTENCY — detect existing Traefik and handle appropriately         │
# │                                                                         │
# │     Traefik running?                                                    │
# │          │                                                              │
# │   ┌─────┴──────┐                                                        │
# │   │            │                                                        │
# │ YES│            NO                                                       │
# │    ▼            │                                                        │
# │ Interactive?    Existing compose file?                                  │
# │  ┌─┴─┐          │                                                       │
# │ YES│NO│      ┌──┴──┐                                                    │
# │   ▼  │     YES│NO│                                                      │
# │ Tear  │     │        Proceed                                            │
# │ down  │ NO  │                                                            │
# │ or    │     ▼                                                            │
# │ skip  │ ┌──────┐                                                         │
# │       │ │ Ask? │                                                         │
# │       │ └─┬───┘                                                          │
# │       │YES│NO                                                           │
# │       ▼   │                                                              │
# │    Tear down                                                       │
# └─────────────────────────────────────────────────────────────────────────┘
step "Checking for an existing Traefik installation"

COMPOSE_FILE="${TRAEFIK_HOME}/docker-compose.yml"
TRAEFIK_RUNNING=false

if docker ps --format '{{.Names}}' | grep -qx 'traefik' 2>/dev/null; then
  TRAEFIK_RUNNING=true
fi

if [[ "$TRAEFIK_RUNNING" == "true" ]]; then
  if [[ "$INTERACTIVE" == "false" ]]; then
    info "Traefik is already running — skipping setup."
    exit 0
  else
    # Show container status
    CONTAINER_INFO=$(docker ps --filter name='^traefik$' --format 'Image: {{.Image}} | Status: {{.Status}}' 2>/dev/null || true)
    info "Existing Traefik container found: ${CONTAINER_INFO}"
    read -rp "    Traefik is already running. Tear down and recreate? Data in ${TRAEFIK_HOME}/letsencrypt will be preserved. [y/N] " _answer
    if [[ "${_answer,,}" == "y" ]]; then
      info "Stopping and removing existing stack..."
      docker compose -f "${COMPOSE_FILE}" down 2>/dev/null || true
      success "Existing stack removed."
    else
      warn "Skipping setup. Exiting."
      exit 0
    fi
  fi
elif [[ -f "$COMPOSE_FILE" ]]; then
  # docker-compose.yml exists but no container is running
  if [[ "$INTERACTIVE" == "true" ]]; then
    info "Found existing ${COMPOSE_FILE} but no container is running."
    read -rp "    Tear down and recreate? Data in ${TRAEFIK_HOME}/letsencrypt will be preserved. [y/N] " _answer
    if [[ "${_answer,,}" != "y" ]]; then
      warn "Skipping setup. Exiting."
      exit 0
    fi
  fi
  # Non-interactive with stopped compose: proceed with fresh install
fi

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ SHARED DOCKER NETWORK — create the proxy network                       │
# │                                                                         │
# │     docker network create                                               │
# │          │                                                              │
# │   ┌─────┴──────┐                                                        │
# │   │            │                                                        │
# │ EXISTS│       CREATED                                                   │
# │    ▼         │                                                          │
# │  Skip      Success                                                      │
# └─────────────────────────────────────────────────────────────────────────┘
step "Creating shared Docker network '${PROXY_NETWORK}'"

if _net_err=$(docker network create "${PROXY_NETWORK}" 2>&1); then
  success "Docker network '${PROXY_NETWORK}' created."
else
  if echo "${_net_err}" | grep -qi 'already exists'; then
    warn "Network '${PROXY_NETWORK}' already exists — skipping."
  else
    error "Failed to create Docker network '${PROXY_NETWORK}': ${_net_err}"
  fi
fi

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ DIRECTORY STRUCTURE — create Traefik configuration directories         │
# │                                                                         │
# │     /opt/traefik/                                                       │
# │     ├── dynamic/                                                        │
# │     │   ├── middlewares.yml                                             │
# │     │   ├── tls.yml                                                     │
# │     │   └── host-services.yml.example                                   │
# │     ├── letsencrypt/                                                    │
# │     │   └── acme.json \(chmod 600\)                                       │
# │     ├── auth/                                                           │
# │     │   └── .htpasswd                                                   │
# │     ├── traefik.yml                                                     │
# │     └── docker-compose.yml                                              │
# │                                                                         │
# │   Permission checks and corrections applied                             │
# └─────────────────────────────────────────────────────────────────────────┘
step "Creating directory structure under ${TRAEFIK_HOME}"

sudo mkdir -p "${TRAEFIK_HOME}/dynamic" \
              "${TRAEFIK_HOME}/letsencrypt" \
              "${TRAEFIK_HOME}/auth"

ACME_JSON="${TRAEFIK_HOME}/letsencrypt/acme.json"
if [[ ! -f "${ACME_JSON}" ]]; then
  sudo touch "${ACME_JSON}"
  sudo chmod 600 "${ACME_JSON}"
  success "Created ${ACME_JSON} (chmod 600)."
else
  # Verify and correct permissions if needed
  _perms=$(stat -c '%a' "${ACME_JSON}" 2>/dev/null || stat -f '%A' "${ACME_JSON}" 2>/dev/null || echo "unknown")
  if [[ "${_perms}" != "600" ]]; then
    sudo chmod 600 "${ACME_JSON}"
    warn "Corrected permissions on ${ACME_JSON} (was ${_perms}, now 600)."
  else
    success "${ACME_JSON} already exists with correct permissions (600)."
  fi
fi

success "Directory structure ready."

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ CREDENTIAL GENERATION — generate BCrypt-hashed password                │
# │                                                                         │
# │     TRAEFIK_ADMIN_PASS set?                                             │
# │          │                                                              │
# │   ┌─────┴──────┐                                                        │
# │   │            │                                                        │
# │  YES│           NO                                                       │
# │    ▼            ▼                                                        │
# │ Use provided  Generate random                                          │
# │ password      \(openssl/rand\)                                           │
# │               │                                                          │
# │               ▼                                                          │
# │          ┌───────────────┐                                              │
# │          │ htpasswd -nbB │                                              │
# │          │ -C 12         │                                              │
# │          └───────┬───────┘                                              │
# │                  ▼                                                       │
# │          Write to auth/.htpasswd                                        │
# │          \(chmod 600\)                                                    │
# └─────────────────────────────────────────────────────────────────────────┘
step "Generating dashboard credentials"

PASS_GENERATED=false
if [[ -z "${TRAEFIK_ADMIN_PASS}" ]]; then
  PASS_GENERATED=true
  if command -v openssl &>/dev/null; then
    TRAEFIK_ADMIN_PASS="$(openssl rand -base64 18)"
  else
    TRAEFIK_ADMIN_PASS="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)"
  fi
fi

HTPASSWD_HASH="$(htpasswd -nbB -C 12 "${TRAEFIK_ADMIN_USER}" "${TRAEFIK_ADMIN_PASS}")"

_htpasswd_tmp="$(mktemp)"
echo "${HTPASSWD_HASH}" > "${_htpasswd_tmp}"
sudo mv "${_htpasswd_tmp}" "${TRAEFIK_HOME}/auth/.htpasswd"
sudo chmod 600 "${TRAEFIK_HOME}/auth/.htpasswd"

success "Credentials generated and written to ${TRAEFIK_HOME}/auth/.htpasswd"

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ CONFIGURATION FILE GENERATION — generate all Traefik config files     │
# │                                                                         │
# │     ┌─────────────────────────────────────────────────────────────┐    │
# │     │ .env \(environment variables\)                                │    │
# │     │   - DOMAIN                                                  │    │
# │     │   - ACME_EMAIL                                              │    │
# │     │   - CF_DNS_API_TOKEN                                        │    │
# │     └─────────────┬───────────────────────────────────────────────┘    │
# │                   ▼                                                     │
# │     ┌─────────────────────────────────────────────────────────────┐    │
# │     │ traefik.yml \(Static Config\)                                 │    │
# │     │   - API/Dashboard settings                                  │    │
# │     │   - Entry points: web → websecure                           │    │
# │     │   - Providers: docker + file                                │    │
# │     │   - CertificatesResolvers: letsencrypt                      │    │
# │     └─────────────┬───────────────────────────────────────────────┘    │
# │                   ▼                                                     │
# │     ┌─────────────────────────────────────────────────────────────┐    │
# │     │ dynamic/middlewares.yml                                     │    │
# │     │   - security-headers                                        │    │
# │     │   - rate-limit                                              │    │
# │     │   - auth-basic                                              │    │
# │     │   - ip-allowlist-private                                    │    │
# │     │   - dashboard-security \(chain\)                              │    │
# │     └─────────────┬───────────────────────────────────────────────┘    │
# │                   ▼                                                     │
# │     ┌─────────────────────────────────────────────────────────────┐    │
# │     │ dynamic/tls.yml                                             │    │
# │     │   - minVersion: TLS12                                       │    │
# │     │   - sniStrict: true                                         │    │
# │     │   - cipherSuites \(ECDSA + RSA\)                              │    │
# │     └─────────────┬───────────────────────────────────────────────┘    │
# │                   ▼                                                     │
# │     ┌─────────────────────────────────────────────────────────────┐    │
# │     │ dynamic/host-services.yml.example                           │    │
# │     │   \(Reference file only\)                                     │    │
# │     └─────────────────────────────────────────────────────────────┘    │
# └─────────────────────────────────────────────────────────────────────────┘
step "Generating configuration files"

# ── .env ─────────────────────────────────────────────────────────────────────
info "Writing ${TRAEFIK_HOME}/.env ..."
_env_tmp="$(mktemp)"
{
  echo "DOMAIN=${TRAEFIK_DOMAIN}"
  echo "ACME_EMAIL=${ACME_EMAIL}"
  if [[ "${DNS_PROVIDER}" == "cloudflare" && -n "${CF_DNS_API_TOKEN}" ]]; then
    echo "CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}"
  fi
} > "${_env_tmp}"
sudo mv "${_env_tmp}" "${TRAEFIK_HOME}/.env"
sudo chmod 600 "${TRAEFIK_HOME}/.env"
success ".env written."

# ── traefik.yml \(Static Configuration\) ───────────────────────────────────────
info "Writing ${TRAEFIK_HOME}/traefik.yml ..."
_traefik_yml_tmp="$(mktemp)"

# Build ACME challenge block
if [[ -n "${DNS_PROVIDER}" ]]; then
  _acme_challenge="      dnsChallenge:
        provider: ${DNS_PROVIDER}"
else
  _acme_challenge="      httpChallenge:
        entryPoint: web"
fi

# Build ACME caServer line
if [[ "${ACME_STAGING}" == "true" ]]; then
  _acme_caserver="      caServer: \"https://acme-staging-v02.api.letsencrypt.org/directory\""
else
  _acme_caserver=""
fi

# Build Docker provider endpoint
if [[ "${USE_SOCKET_PROXY}" == "true" ]]; then
  _docker_endpoint="tcp://socket-proxy:2375"
else
  _docker_endpoint="unix:///var/run/docker.sock"
fi

# Build dashboard flag
if [[ "${TRAEFIK_DASHBOARD}" == "true" ]]; then
  _api_dashboard="true"
else
  _api_dashboard="false"
fi

cat > "${_traefik_yml_tmp}" <<TRAEFIKYML
# /etc/traefik/traefik.yml — Static Configuration
# Generated by setup-traefik.sh — do not edit manually

# ── API / Dashboard ───────────────────────────────────────────────────────────
api:
  dashboard: ${_api_dashboard}
  insecure: false

# ── Entry Points ──────────────────────────────────────────────────────────────
entryPoints:
  web:
    address: ":${HTTP_PORT}"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":${HTTPS_PORT}"
    http:
      tls:
        options: default

# ── Providers ─────────────────────────────────────────────────────────────────
providers:
  docker:
    endpoint: "${_docker_endpoint}"
    exposedByDefault: false
    network: ${PROXY_NETWORK}
    watch: true

  file:
    directory: /etc/traefik/dynamic
    watch: true

# ── Certificate Resolvers ─────────────────────────────────────────────────────
certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ACME_EMAIL}
      storage: /letsencrypt/acme.json
${_acme_challenge}
TRAEFIKYML

# Append caServer line only when staging
if [[ -n "${_acme_caserver}" ]]; then
  echo "${_acme_caserver}" >> "${_traefik_yml_tmp}"
fi

cat >> "${_traefik_yml_tmp}" <<'TRAEFIKYMLTAIL'

# ── Logging ───────────────────────────────────────────────────────────────────
log:
  level: INFO

accessLog:
  bufferingSize: 100
TRAEFIKYMLTAIL

sudo mv "${_traefik_yml_tmp}" "${TRAEFIK_HOME}/traefik.yml"
success "traefik.yml written."

# ── dynamic/middlewares.yml ───────────────────────────────────────────────────
info "Writing ${TRAEFIK_HOME}/dynamic/middlewares.yml ..."
_mw_tmp="$(mktemp)"
cat > "${_mw_tmp}" <<'MIDDLEWARES'
# /etc/traefik/dynamic/middlewares.yml — Dynamic Configuration \(hot-reloaded\)
# Generated by setup-traefik.sh — do not edit manually

http:
  middlewares:

    # ── Security Headers ──────────────────────────────────────────────────────
    security-headers:
      headers:
        frameDeny: true
        contentTypeNosniff: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        referrerPolicy: "same-origin"
        customResponseHeaders:
          Server: ""
          X-Powered-By: ""

    # ── Rate Limiting ─────────────────────────────────────────────────────────
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: "1s"

    # ── Basic Authentication ──────────────────────────────────────────────────
    auth-basic:
      basicAuth:
        usersFile: /etc/traefik/auth/.htpasswd
        removeHeader: true

    # ── IP Allow List \(RFC 1918 private ranges + loopback\) ────────────────────
    ip-allowlist-private:
      ipAllowList:
        sourceRange:
          - "127.0.0.1/32"
          - "::1/128"
          - "10.0.0.0/8"
          - "172.16.0.0/12"
          - "192.168.0.0/16"
        rejectStatusCode: 403

    # ── Dashboard Security Chain ──────────────────────────────────────────────
    dashboard-security:
      chain:
        middlewares:
          - ip-allowlist-private
          - auth-basic

    # ── Compression ───────────────────────────────────────────────────────────
    compress:
      compress: {}
MIDDLEWARES

sudo mv "${_mw_tmp}" "${TRAEFIK_HOME}/dynamic/middlewares.yml"
success "dynamic/middlewares.yml written."

# ── dynamic/tls.yml ───────────────────────────────────────────────────────────
info "Writing ${TRAEFIK_HOME}/dynamic/tls.yml ..."
_tls_tmp="$(mktemp)"
cat > "${_tls_tmp}" <<'TLSYML'
# /etc/traefik/dynamic/tls.yml — Dynamic Configuration \(hot-reloaded\)
# Generated by setup-traefik.sh — do not edit manually
#
# NOTE: TLS options are DYNAMIC configuration only — they cannot go in
# traefik.yml \(static config\). They are referenced by name from entryPoints.

tls:
  options:
    default:
      minVersion: VersionTLS12
      sniStrict: true
      cipherSuites:
        # ECDSA ciphers — required for Let's Encrypt ECDSA certs \(default since 2024\)
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256
        # RSA ciphers — for backward compatibility
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256
TLSYML

sudo mv "${_tls_tmp}" "${TRAEFIK_HOME}/dynamic/tls.yml"
success "dynamic/tls.yml written."

# ── dynamic/host-services.yml.example ────────────────────────────────────────
info "Writing ${TRAEFIK_HOME}/dynamic/host-services.yml.example ..."
_hs_tmp="$(mktemp)"
cat > "${_hs_tmp}" <<'HOSTSERVICES'
# host-services.yml.example — Example for proxying host-local services
# ─────────────────────────────────────────────────────────────────────────────
# Copy this file to host-services.yml \(remove .example\) to activate.
# Traefik ignores .example files — this is safe to keep as a reference.
#
# Use this pattern to proxy services running directly on the Docker host
# \(not in containers\) via host.docker.internal \(resolves to Docker bridge\).
#
# NOTE: The host service must bind to 0.0.0.0 \(not 127.0.0.1\) so that
# Docker containers can reach it through the bridge interface.
#
# Example: Expose a host-local service on port 8096 at media.example.com

# http:
#   routers:
#     media:
#       rule: "Host\(`media.example.com`\)"
#       entrypoints:
#         - websecure
#       service: media
#       tls:
#         certResolver: letsencrypt
#       middlewares:
#         - security-headers@file
#
#   services:
#     media:
#       loadBalancer:
#         servers:
#           - url: "http://host.docker.internal:8096"
HOSTSERVICES

sudo mv "${_hs_tmp}" "${TRAEFIK_HOME}/dynamic/host-services.yml.example"
success "dynamic/host-services.yml.example written."

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ DOCKER COMPOSE FILE — generate docker-compose.yml                      │
# │                                                                         │
# │     TRAEFIK_DASHBOARD enabled?                                          │
# │          │                                                              │
# │   ┌─────┴──────┐                                                        │
# │   │            │                                                        │
# │  YES│           NO                                                       │
# │    ▼            │                                                        │
# │ Warn about      Proceed                                                  │
# │ default domain  with validation                                          │
# └──────────────────────────┬───────────────────────────────────────────────┘
#                            │
#                            ▼
# │   USE_SOCKET_PROXY?                                                    │
# │          │                                                              │
# │   ┌─────┴──────┐                                                        │
# │   │            │                                                        │
# │  YES│           NO                                                       │
# │    ▼            │                                                        │
# │ Write socket-proxy│ Write without                                       │
# │ service           │ socket-proxy                                         │
# │                   │                                                       │
# └───────────┬───────┴───────────────────────────────────────────────────────┘
#             │
#             ▼
# ┌─────────────────────────────────────────────────────────────────────────┐
# │                    TRAEFIK SERVICE DEFINITION                           │
# │                                                                         │
# │   image: []                                               │
# │   container_name: traefik                                               │
# │   restart: unless-stopped                                               │
# │   security_opt: [no-new-privileges:true]                                │
# │                                                                         │
# │   depends_on:                                                           │
# │     socket-proxy [conditional on USE_SOCKET_PROXY=true]                 │
# │                                                                         │
# │   ports:                                                                │
# │     - target: [] \(80\)//, published, mode:host                   │
# │     - target: [] \(443\)//, published, mode:host                 │
# │                                                                         │
# │   extra_hosts:                                                          │
# │     - "host.docker.internal:host-gateway"                               │
# │                                                                         │
# │   volumes:                                                              │
# │     - traefik.yml:/etc/traefik/traefik.yml:ro                           │
# │     - dynamic/:/etc/traefik/dynamic:ro                                  │
# │     - letsencrypt/:/letsencrypt                                         │
# │     - auth/:/etc/traefik/auth:ro                                        │
# │                                                                         │
# │   env_file: .env [if DNS challenge]                                     │
# │                                                                         │
# │   networks:                                                             │
# │     - socket-net [if USE_SOCKET_PROXY=true]                             │
# │     - []                                                  │
# │                                                                         │
# │   labels:                                                               │
# │     traefik.enable=true                                                 │
# │     traefik.docker.network=[]                             │
# │     [dashboard labels if enabled]                                       │
# └─────────────────────────────────────────────────────────────────────────┘
#             │
#             ▼
# ┌─────────────────────────────────────────────────────────────────────────┐
# │                      NETWORKS SECTION                                   │
# │                                                                         │
# │   socket-net:                                                           │
# │     internal: true                                                      │
# │   []:                                                       │
# │     external: true                                                      │
# └─────────────────────────────────────────────────────────────────────────┘

step "Generating ${COMPOSE_FILE}"

# Warn if dashboard is enabled but domain is still the default
if [[ "${TRAEFIK_DASHBOARD}" == "true" && "${TRAEFIK_DOMAIN}" == "traefik.example.com" ]]; then
  warn "TRAEFIK_DASHBOARD is enabled but TRAEFIK_DOMAIN is still the default 'traefik.example.com'."
  warn "Set TRAEFIK_DOMAIN to a real hostname before using in production!"
fi

_compose_tmp="$(mktemp)"

# ── Write socket-proxy service \(conditional\) and start of file ───────────────
if [[ "${USE_SOCKET_PROXY}" == "true" ]]; then
  cat > "${_compose_tmp}" <<COMPOSEFILE
# docker-compose.yml — Generated by setup-traefik.sh — do not edit manually

services:

  # ── Docker Socket Proxy ────────────────────────────────────────────────────
  socket-proxy:
    image: ghcr.io/tecnativa/docker-socket-proxy:latest
    container_name: traefik-socket-proxy
    restart: unless-stopped
    privileged: true
    environment:
      CONTAINERS: 1
      NETWORKS: 1
      EVENTS: 1
      PING: 1
      VERSION: 1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - socket-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:2375/_ping"]
      interval: 10s
      timeout: 3s
      retries: 3

COMPOSEFILE
else
  cat > "${_compose_tmp}" <<'COMPOSENOSOCKET'
# docker-compose.yml — Generated by setup-traefik.sh — do not edit manually

services:

COMPOSENOSOCKET
fi

# ── Traefik service ───────────────────────────────────────────────────────────
{
  cat <<TRAEFIKSERVICE
  # ── Traefik ─────────────────────────────────────────────────────────────────
  traefik:
    image: ${TRAEFIK_IMAGE}
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
TRAEFIKSERVICE

  # depends_on only when using socket proxy
  if [[ "${USE_SOCKET_PROXY}" == "true" ]]; then
    cat <<'DEPENDSON'
    depends_on:
      socket-proxy:
        condition: service_healthy
DEPENDSON
  fi

  cat <<PORTS
    ports:
      - target: ${HTTP_PORT}
        published: ${HTTP_PORT}
        mode: host
      - target: ${HTTPS_PORT}
        published: ${HTTPS_PORT}
        mode: host
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ${TRAEFIK_HOME}/traefik.yml:/etc/traefik/traefik.yml:ro
      - ${TRAEFIK_HOME}/dynamic:/etc/traefik/dynamic:ro
      - ${TRAEFIK_HOME}/letsencrypt:/letsencrypt
      - ${TRAEFIK_HOME}/auth:/etc/traefik/auth:ro
PORTS

  # Environment for DNS challenge credentials
  if [[ -n "${DNS_PROVIDER}" && -n "${CF_DNS_API_TOKEN}" ]]; then
    cat <<'ENVBLOCK'
    env_file:
      - .env
ENVBLOCK
  fi

  # Networks
  if [[ "${USE_SOCKET_PROXY}" == "true" ]]; then
    cat <<NETWORKS_PROXY
    networks:
      - socket-net
      - ${PROXY_NETWORK}
NETWORKS_PROXY
  else
    cat <<NETWORKS_NOPROXY
    networks:
      - ${PROXY_NETWORK}
NETWORKS_NOPROXY
  fi

  # Labels
  cat <<LABELS
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=${PROXY_NETWORK}"
LABELS

  # Dashboard labels \(only when enabled\)
  if [[ "${TRAEFIK_DASHBOARD}" == "true" ]]; then
    cat <<DASHLABELS
      - "traefik.http.routers.dashboard.rule=Host(\`${TRAEFIK_DOMAIN}\`) && (PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`))"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.routers.dashboard.middlewares=dashboard-security@file"
DASHLABELS
  fi

} >> "${_compose_tmp}"

# ── Networks section ──────────────────────────────────────────────────────────
{
  echo ""
  echo "networks:"

  if [[ "${USE_SOCKET_PROXY}" == "true" ]]; then
    cat <<'SOCKETNET'
  socket-net:
    internal: true
SOCKETNET
  fi

  cat <<PROXYNET
  ${PROXY_NETWORK}:
    external: true
PROXYNET
} >> "${_compose_tmp}"

sudo mv "${_compose_tmp}" "${COMPOSE_FILE}"
success "docker-compose.yml written to ${COMPOSE_FILE}"

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ STACK STARTUP — pull, start, and wait for health                       │
# │                                                                         │
# │     docker compose pull                                                 │
# │          │                                                              │
# │          ▼                                                              │
# │     docker compose up -d                                                │
# │          │                                                              │
# │          ▼                                                              │
# │   ┌───────────────────┐         ┌─────────────────────────────┐       │
# │   │ Wait for health   │◀───────▶│ Check: Container healthy?   │       │
# │   │ check \(60s max\)   │         └──────────────┬──────────────┘       │
# │   └───────────────────┘                       │ YES                   │
# │          ▲                                  │                         │
# │          │ NO                              ▼                         │
# │          └──────────────────────────────▶│  SUCCESS │                 │
# └─────────────────────────────────────────────────────────────────────────┘
step "Pulling Docker images"
if ! docker compose -f "${COMPOSE_FILE}" pull; then
  error "Failed to pull Docker images. Check the error output above."
fi
success "Images pulled."

step "Starting Traefik stack (detached)"
if ! docker compose -f "${COMPOSE_FILE}" up -d; then
  error "Failed to start Traefik stack. Check the error output above."
fi
success "Stack started."

step "Waiting for Traefik container to become healthy (up to 60s)"
MAX_WAIT=60
INTERVAL=5
ELAPSED=0
HEALTH_OK=false

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  _status="$(docker ps --filter 'name=^traefik$' --format '{{.Status}}' 2>/dev/null || true)"
  if [[ -n "${_status}" ]]; then
    HEALTH_OK=true
    break
  fi
  echo -ne "\r    Waited ${ELAPSED}s / ${MAX_WAIT}s ..."
  sleep "${INTERVAL}"
  ELAPSED=$((ELAPSED + INTERVAL))
done
echo ""

if [[ "${HEALTH_OK}" == "true" ]]; then
  success "Traefik is up and running!"
else
  warn "Traefik container did not appear within ${MAX_WAIT}s."
  warn "It may still be starting. Check logs with:"
  warn "  docker compose -f ${COMPOSE_FILE} logs -f traefik"
fi

# ┌─────────────────────────────────────────────────────────────────────────┐
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ UFW FIREWALL — open ports if UFW is active                             │
# └─────────────────────────────────────────────────────────────────────────┘
step "Configuring UFW firewall"

if ufw_available && ufw_active; then
  info "UFW is active — opening ports ${HTTP_PORT}/tcp and ${HTTPS_PORT}/tcp ..."
  ufw_add_rule "${HTTP_PORT}" "tcp" "HTTP"
  ufw_add_rule "${HTTPS_PORT}" "tcp" "HTTPS"
else
  warn "UFW is not installed or not active — skipping firewall configuration."
  warn "Make sure ports ${HTTP_PORT} and ${HTTPS_PORT} are open in your firewall."
fi

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ SUMMARY — display all credentials and quick references                  │
# │                                                                         │
# │     ┌─────────────────────────────────────────────────────────────┐    │
# │     │ IMAGE:         [TRAEFIK_IMAGE]                                │    │
# │     │ CONFIG DIR:    []]                                 │    │
# │     │ COMPOSE FILE:  []]                                 │    │
# │     │ PROXY NETWORK: [PROXY_NETWORK]                                  │    │
# │     │ ACME MODE:     Production / Staging                            │    │
# │     │ ACME CHALLENGE: HTTP or DNS                                    │    │
# │     │ ACME EMAIL:    []]                                   │    │
# │     └─────────────────────────────────────────────────────────────┘    │
# │                                                                         │
# │   IF DASHBOARD ENABLED:                                                 │
# │     ┌─────────────────────────────────────────────────────────────┐    │
# │     │ Dashboard URL: https://[]]/dashboard/            │    │
# │     │ Admin user:    []]                           │    │
# │     │ Admin password: []] \(if generated!\)          │    │
# │     └─────────────────────────────────────────────────────────────┘    │
# │                                                                         │
# │   QUICK REFERENCE: ADDING AN APP                                        │
# │     1. Add app container to '[PROXY_NETWORK]' network                  │
# │     2. Add labels:                                                      │
# │        traefik.enable=true                                                │
# │        traefik.docker.network=[]                            │
# │        traefik.http.routers.myapp.rule=Host(                              │
# │        traefik.http.routers.myapp.entrypoints=websecure                   │
# │        traefik.http.routers.myapp.tls.certresolver=letsencrypt            │
# │        traefik.http.services.myapp.loadbalancer.server.port=8080          │
# └─────────────────────────────────────────────────────────────────────────┘

# Determine ACME mode and challenge type
if [[ "${ACME_STAGING}" == "true" ]]; then
  _acme_mode="Staging (untrusted certs — for testing)"
else
  _acme_mode="Production"
fi

if [[ -n "${DNS_PROVIDER}" ]]; then
  _acme_challenge_type="DNS challenge (provider: ${DNS_PROVIDER})"
else
  _acme_challenge_type="HTTP challenge"
fi

echo ""
if [[ "${HEALTH_OK}" == "false" ]]; then
  echo -e "${YELLOW}⚠  Health check timed out — Traefik may still be starting. Run:${RESET}"
  echo -e "${YELLOW}   docker compose -f ${COMPOSE_FILE} logs -f traefik${RESET}"
  echo ""
fi
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Traefik v3 setup complete!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Image${RESET}           ${TRAEFIK_IMAGE}"
echo -e "  ${BOLD}Config dir${RESET}      ${TRAEFIK_HOME}"
echo -e "  ${BOLD}Compose file${RESET}    ${COMPOSE_FILE}"
echo -e "  ${BOLD}Proxy network${RESET}   ${PROXY_NETWORK}"
echo -e "  ${BOLD}ACME mode${RESET}       ${_acme_mode}"
echo -e "  ${BOLD}ACME challenge${RESET}  ${_acme_challenge_type}"
echo -e "  ${BOLD}ACME email${RESET}      ${ACME_EMAIL}"
echo ""

if [[ "${TRAEFIK_DASHBOARD}" == "true" ]]; then
  echo -e "  ${BOLD}Dashboard URL${RESET}   https://${TRAEFIK_DOMAIN}/dashboard/"
  echo -e "  ${BOLD}Admin user${RESET}      ${TRAEFIK_ADMIN_USER}"
  if [[ "${PASS_GENERATED}" == "true" ]]; then
    # Save password to a secure file instead of printing to stdout
    CREDENTIALS_FILE="${TRAEFIK_HOME}/.credentials"
    cat > "${CREDENTIALS_FILE}" <<CREDS
# Traefik Dashboard Credentials
# Generated by setup-traefik.sh — $(date -I)
# WARNING: Keep this file secure and delete after saving credentials elsewhere

Admin user: ${TRAEFIK_ADMIN_USER}
Admin password: ${TRAEFIK_ADMIN_PASS}
CREDS
    chmod 600 "${CREDENTIALS_FILE}"
    echo -e "  ${BOLD}Admin password${RESET}  ${YELLOW}saved to ${CREDENTIALS_FILE} (chmod 600)${RESET}"
  else
    echo -e "  ${BOLD}Admin password${RESET}  (as provided via TRAEFIK_ADMIN_PASS env var)"
  fi
  echo ""
fi

echo -e "${BOLD}Quick-reference — adding an app to Traefik:${RESET}"
echo -e "  1. Add your app's container to the '${PROXY_NETWORK}' Docker network."
echo -e "  2. Add these labels to your app service:"
echo -e "     ${CYAN}traefik.enable=true${RESET}"
echo -e "     ${CYAN}traefik.docker.network=${PROXY_NETWORK}${RESET}"
echo -e "     ${CYAN}traefik.http.routers.myapp.rule=Host(\`app.example.com\`)${RESET}"
echo -e "     ${CYAN}traefik.http.routers.myapp.entrypoints=websecure${RESET}"
echo -e "     ${CYAN}traefik.http.routers.myapp.tls.certresolver=letsencrypt${RESET}"
echo -e "     ${CYAN}traefik.http.services.myapp.loadbalancer.server.port=8080${RESET}"
echo ""
echo -e "${BOLD}Quick-reference — applying basic auth middleware:${RESET}"
echo -e "  Add label: ${CYAN}traefik.http.routers.myapp.middlewares=auth-basic@file${RESET}"
echo ""
echo -e "${BOLD}Useful commands:${RESET}"
echo -e "  Follow logs    : docker compose -f ${COMPOSE_FILE} logs -f traefik"
echo -e "  Stop stack     : docker compose -f ${COMPOSE_FILE} down"
echo -e "  Start stack    : docker compose -f ${COMPOSE_FILE} up -d"
echo -e "  Restart stack  : docker compose -f ${COMPOSE_FILE} restart"
echo -e "  Shell into app : docker exec -it traefik sh"
echo ""
