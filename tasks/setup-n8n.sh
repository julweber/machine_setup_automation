#!/usr/bin/env bash
# =============================================================================
#  n8n Setup Script – a single‑file, self‑contained installer.
#
#  It mirrors the style of existing tasks like `setup-forgejo.sh` or
#  `setup-openwebui.sh`. The script:
#    • creates an isolated workspace under $PI_ROOT/n8n
#    • writes a default .env (edit before running)
#    • generates a base docker‑compose file for n8n + Postgres
#    • if TRAEFIK_ENABLED=true it injects Traefik labels so the service is
#      exposed through the existing reverse proxy with automatic Let’s Encrypt.
#
#  Usage (run from the project root):
#       export TRAEFIK_ENABLED=true   # or omit / set false
#       ./tasks/setup-n8n.sh
# =============================================================================

set -euo pipefail

# ---------- Helper functions ----------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }

# ---------- Pre‑flight ----------
if ! command -v docker &>/dev/null; then
  error "Docker is not installed. Run setup-docker.sh first."
fi

# Allow override via N8N_DIR env var, default to /srv/n8n
N8N_DIR="${N8N_DIR:-/srv/n8n}"
COMPOSE_FILE="${N8N_DIR}/docker-compose.yml"

# ---------- 1️⃣ Create workspace ----------
info "Creating n8n workspace at ${N8N_DIR} ..."
sudo mkdir -p "${N8N_DIR}"
success "Workspace created."

# ---------- Persistent data directories ----------
# Official docs recommend using Docker named volumes instead of bind mounts
# to avoid permission issues. We still create local-files for file node access.
info "Creating persistent storage directories under ${N8N_DIR}"
sudo mkdir -p "${N8N_DIR}/local-files"   # For Read/Write Files from Disk node
success "Directories ready."

# ---------- 2️⃣ Write .env (default values) ----------
sudo tee "${N8N_DIR}/.env" <<'EOF' > /dev/null
# -------------------------------------------------
# n8n environment – edit before first launch!
# -------------------------------------------------

# Public domain that resolves to this server.
DOMAIN_NAME=example.com
SUBDOMAIN=n8n

# Internal port exposed by the container (Traefik talks over 5678)
N8N_PORT=5678
N8N_PROTOCOL=https            # Traefik terminates TLS → n8n thinks it's HTTPS
WEBHOOK_URL=https://${SUBDOMAIN}.${DOMAIN_NAME}/   # note trailing slash!

# Timezone settings (optional, defaults to New York)
GENERIC_TIMEZONE=Europe/Berlin

# Email for TLS/SSL certificate creation
SSL_EMAIL=user@example.com

# Optional: enforce settings file permissions
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

EOF
success ".env written – review and adjust values before starting n8n."

# ---------- 3️⃣ Base docker‑compose (static part) ----------
TRAEFIK_ENABLED="${TRAEFIK_ENABLED:-false}"

# Build the n8n service definition following official n8n docs approach
if [[ "$TRAEFIK_ENABLED" == "true" ]]; then
  info "Traefik is enabled – will inject labels."
  N8N_SERVICE=$(cat <<'N8N_TRAEFIK'
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    labels:
      - traefik.enable=true
      - traefik.docker.network=proxy
      - traefik.http.routers.n8n.rule=Host(`${SUBDOMAIN}.${DOMAIN_NAME}`)
      - traefik.http.routers.n8n.tls=true
      - traefik.http.routers.n8n.entrypoints=web,websecure
      - traefik.http.routers.n8n.middlewares=n8n@docker
      - traefik.http.middlewares.n8n.headers.SSLRedirect=true
      - traefik.http.middlewares.n8n.headers.STSSeconds=315360000
      - traefik.http.middlewares.n8n.headers.browserXSSFilter=true
      - traefik.http.middlewares.n8n.headers.contentTypeNosniff=true
      - traefik.http.middlewares.n8n.headers.forceSTSHeader=true
      - "traefik.http.middlewares.n8n.headers.SSLHost=${DOMAIN_NAME}"
      - traefik.http.middlewares.n8n.headers.STSIncludeSubdomains=true
      - traefik.http.middlewares.n8n.headers.STSPreload=true
    environment:
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=${N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS:-true}
      - N8N_HOST=${SUBDOMAIN}.${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${SUBDOMAIN}.${DOMAIN_NAME}/
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE:-Europe/Berlin}
      - TZ=${GENERIC_TIMEZONE:-Europe/Berlin}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files

  traefik:
    image: "traefik"
    restart: always
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.mytlschallenge.acme.tlsChallenge=true"
      - "--certificatesresolvers.mytlschallenge.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.mytlschallenge.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
N8N_TRAEFIK
)
else
  warn "TRAEFIK_ENABLED is false – n8n will run without Traefik labels (exposed only on localhost:5678)."
  N8N_SERVICE=$(cat <<'N8N_LOCAL'
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=${N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS:-true}
      - N8N_HOST=localhost
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=http://localhost:5678/
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE:-Europe/Berlin}
      - TZ=${GENERIC_TIMEZONE:-Europe/Berlin}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files
N8N_LOCAL
)
fi

# Write the complete compose file
{
  echo "services:"
  echo "$N8N_SERVICE"
  
  # PostgreSQL service (shared between both modes)
  cat <<'POSTGRES'
  postgres:
    image: postgres:15-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-n8n}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-changeme}
      - POSTGRES_DB=n8n
    volumes:
      - pg_data:/var/lib/postgresql/data

volumes:
  n8n_data:
  pg_data:
POSTGRES
  
  # Add traefik_data volume only when Traefik is enabled
  if [[ "$TRAEFIK_ENABLED" == "true" ]]; then
    echo "  traefik_data:"
  fi

  echo ""
  echo "networks:"
  echo "  proxy:"
  echo "    external: true"
} | sudo tee "${COMPOSE_FILE}" > /dev/null

success "Base docker‑compose.yml written (static part)."

# ---------- 4️⃣ Traefik network setup ----------
if [[ "$TRAEFIK_ENABLED" == "true" ]]; then
  # Ensure the shared network 'proxy' exists (used by other services)
  if ! docker network inspect proxy >/dev/null 2>&1; then
    warn "'proxy' Docker network not found – creating it now."
    docker network create proxy || true   # ignore already‑exists error
  else
    success "Docker network 'proxy' is present."
  fi
fi

# ---------- 5️⃣ Bring the stack up ----------
info "Starting n8n container..."
docker compose -f "${COMPOSE_FILE}" up -d --build n8n

success "n8n should now be reachable at http://localhost:5678 (or https://automation.example.com when Traefik is enabled)."

# ---------- 6️⃣ Post‑install hint ----------
info
echo -e "${BOLD}Next steps:${RESET}"
if [[ "$TRAEFIK_ENABLED" == "true" ]]; then
  echo "- Verify TLS with: curl -I https://automation.example.com"
else
  echo "- n8n UI is only local; consider enabling Traefik for public access."
fi
echo "- Edit the .env file if you need to change passwords or domain names."
echo "- When your workflows are ready, expose a webhook endpoint from your LangChain agent and point an HTTP Request node in n8n at that URL."

exit 0
