# Behaviors — traefik-setup

> **Information source:** [`docs/traefik-research-result-final.md`](../../../docs/traefik-research-result-final.md) — Traefik v3 research & implementation reference (verified against v3.6.9 docs).

## Overview

This feature adds `tasks/setup-traefik.sh` — a modular, idempotent Bash script that deploys a production-ready Traefik v3 reverse proxy on Ubuntu, following the project's existing conventions. It also adds `lib/helpers.sh` (shared helper library) and updates `tasks/setup-forgejo.sh` as a reference Traefik integration.

### Files Delivered

| File | Purpose |
|------|---------|
| `tasks/setup-traefik.sh` | Core Traefik setup script |
| `lib/helpers.sh` | Shared helper library (`ensure_proxy_network`, `ensure_traefik_running`) |
| `tasks/setup-forgejo.sh` | Updated with opt-in Traefik integration |

### Design Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Socket proxy | **Enabled** by default (`USE_SOCKET_PROXY=true`) |
| 2 | Interactive prompts | Non-interactive by default (skip + exit 0 if already running); `--interactive` flag enables prompt for destructive actions |
| 3 | ACME mode | **Production CA** by default; `ACME_STAGING=true` opt-in |
| 4 | Root requirement | **Docker-group user**; `sudo` only where needed |
| 5 | Dashboard | **Disabled** by default; opt-in via `TRAEFIK_DASHBOARD=true` |
| 6 | Scope | Core Traefik + helper functions for other scripts |
| 7 | Helper location | `lib/helpers.sh` shared library |
| 8 | Helpers provided | `ensure_proxy_network()` + `ensure_traefik_running()` |
| 9 | Host-local services | Infrastructure ready + example template (`dynamic/host-services.yml.example`) |
| 10 | Existing app updates | Update `setup-forgejo.sh` as reference integration |
| 11 | Domain configuration | Each app owns its full domain via its own env var (e.g. `FORGEJO_DOMAIN=git.example.com`) — no shared base domain |

### Environment Variables

All variables have sensible defaults and can be overridden before running.

| Variable | Default | Description |
|----------|---------|-------------|
| `TRAEFIK_HOME` | `/opt/traefik` | Host directory for all Traefik config and data |
| `TRAEFIK_IMAGE` | `traefik:v3` | Docker image to use |
| `TRAEFIK_DOMAIN` | `traefik.example.com` | Dashboard hostname (only used when `TRAEFIK_DASHBOARD=true`) |
| `TRAEFIK_DASHBOARD` | `false` | Enable the Traefik dashboard |
| `ACME_EMAIL` | `admin@example.com` | Let's Encrypt registration email |
| `ACME_STAGING` | `false` | Use Let's Encrypt staging CA |
| `DNS_PROVIDER` | *(empty)* | DNS challenge provider (e.g. `cloudflare`). Empty = HTTP challenge |
| `CF_DNS_API_TOKEN` | *(empty)* | Cloudflare DNS API token (only when `DNS_PROVIDER=cloudflare`) |
| `TRAEFIK_ADMIN_USER` | `admin` | Basic auth username for dashboard |
| `TRAEFIK_ADMIN_PASS` | *(empty)* | Basic auth password. Empty = auto-generate random 24-char password |
| `PROXY_NETWORK` | `proxy` | Name of the shared Docker network |
| `USE_SOCKET_PROXY` | `true` | Use Docker socket proxy (recommended) |
| `HTTP_PORT` | `80` | Host port for HTTP entry point |
| `HTTPS_PORT` | `443` | Host port for HTTPS entry point |

---

## Pre-Flight Validation

### Happy Path

The script verifies that all prerequisites are met before proceeding:

- Docker Engine is installed and the daemon is running.
- The current user is in the `docker` group (can run `docker` commands without `sudo`).
- `htpasswd` (from `apache2-utils`) is available. If missing, the script installs it via `sudo apt-get install -y apache2-utils`.

The script prints a coloured success message for each check that passes.

### Error Cases

- **Docker not installed:** Print a red error message naming `setup-docker.sh` as the prerequisite and exit 1.
- **Docker daemon not running:** Print a red error message suggesting `sudo systemctl start docker` and exit 1.
- **User not in docker group:** Print a red error message suggesting `sudo usermod -aG docker $USER` and a re-login, then exit 1.
- **`apt-get install apache2-utils` fails:** Print a red error message and exit 1.

---

## Argument Parsing

### Happy Path

The script accepts a `--interactive` flag. When passed, the script enables interactive prompts for destructive actions (e.g., tearing down an existing Traefik installation). Without the flag, the script runs fully non-interactively — no `read -rp` prompts are issued. The flag is parsed before any other logic runs.

### Edge Cases

- Unknown flags are ignored with a yellow warning message (not a fatal error).
- `--interactive` can appear anywhere in the argument list.

---

## Idempotency Handling

### Happy Path — No Existing Installation

If no `traefik` container is running and no `docker-compose.yml` exists at `$TRAEFIK_HOME`, the script proceeds with a fresh installation.

### Happy Path — Existing Installation (Default, Non-Interactive)

If a `traefik` container is already running, the script prints a cyan informational message ("Traefik is already running — skipping setup.") and exits 0. It does **not** tear down or modify the existing installation.

### Happy Path — Existing Installation (`--interactive`)

If `--interactive` is passed and a `traefik` container is already running, the script prints the current container status (image, uptime) in cyan and prompts:

> `Traefik is already running. Tear down and recreate? Data in $TRAEFIK_HOME/letsencrypt will be preserved. [y/N]`

If the user answers `y`, the script runs `docker compose down` on the existing stack and proceeds with a fresh installation. Persistent data (`letsencrypt/acme.json`) is preserved — only the compose stack and config files are recreated.

If the user answers anything else (or just presses Enter), the script prints a yellow "Skipping" message and exits 0.

### Edge Cases

- If `$TRAEFIK_HOME/docker-compose.yml` exists but no container is running (e.g. stack was stopped), the script treats this as a reinstall scenario — same prompt logic applies. In default (non-interactive) mode, it proceeds with the installation since no container is running.

---

## Shared Docker Network Creation

### Happy Path

The script creates a Docker network named by `$PROXY_NETWORK` (default: `proxy`) using `docker network create`. If the network already exists, the script prints a yellow "already exists — skipping" message and continues.

### Error Cases

- **`docker network create` fails for a reason other than "already exists":** Print a red error message and exit 1.

---

## Directory Structure Creation

### Happy Path

The script creates the following directory tree under `$TRAEFIK_HOME` (default: `/opt/traefik`) using `sudo mkdir -p`:

```
$TRAEFIK_HOME/
├── dynamic/
├── letsencrypt/
└── auth/
```

If directories already exist, `mkdir -p` is a no-op. The script prints a green success message after creation.

### Happy Path — acme.json Initialisation

If `$TRAEFIK_HOME/letsencrypt/acme.json` does not exist, the script creates it with `sudo touch` and sets permissions to `600` via `sudo chmod 600`. If it already exists, permissions are verified and corrected if needed, but the file content is never overwritten (it contains issued certificates).

### Error Cases

- **Permission denied creating directories:** Print a red error message and exit 1 (likely means `sudo` is not available or the user lacks sudo privileges).

---

## Credential Generation

### Happy Path

The script generates authentication credentials for the Traefik admin user:

1. If `$TRAEFIK_ADMIN_PASS` is empty, generate a random 24-character password using `openssl rand -base64 18`.
2. Generate a BCrypt hash using `htpasswd -nbB -C 12 "$TRAEFIK_ADMIN_USER" "$TRAEFIK_ADMIN_PASS"`.
3. Write the hash to `$TRAEFIK_HOME/auth/.htpasswd` and set permissions to `600`.

The generated password is stored in a variable for the summary output but is **never written to disk in plaintext** (only the BCrypt hash is persisted).

### Happy Path — Existing .htpasswd

If `$TRAEFIK_HOME/auth/.htpasswd` already exists, it is overwritten with the new credentials. This is intentional — a reinstall should reset credentials to match the current env var configuration.

### Error Cases

- **`htpasswd` command fails:** Print a red error message and exit 1.
- **`openssl` not available for random generation:** Fall back to `/dev/urandom` with `tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24`.

---

## Configuration File Generation

### Happy Path

The script generates the following configuration files using heredocs with variable substitution:

#### `$TRAEFIK_HOME/.env`

Contains `DOMAIN`, `ACME_EMAIL`, and optionally `CF_DNS_API_TOKEN`. Permissions set to `600`.

#### `$TRAEFIK_HOME/traefik.yml` (Static Configuration)

- `api.dashboard`: set to `true` if `$TRAEFIK_DASHBOARD` is `true`, otherwise `false`.
- `api.insecure`: always `false`.
- Entry points: `web` on `$HTTP_PORT` with HTTP→HTTPS redirect, `websecure` on `$HTTPS_PORT`.
- Docker provider: endpoint is `tcp://socket-proxy:2375` (socket proxy enabled by default). `exposedByDefault: false`. Network set to `$PROXY_NETWORK`.
- File provider: watches `/etc/traefik/dynamic`.
- Certificate resolver `letsencrypt`: uses HTTP challenge by default. If `$DNS_PROVIDER` is set, uses DNS challenge instead with `$DNS_PROVIDER` as the provider. If `$ACME_STAGING` is `true`, sets `caServer` to the Let's Encrypt staging URL.
- Logging: `level: INFO`, access log with `bufferingSize: 100`.

Reference: [`docs/traefik-research-result-final.md` §4 Static Configuration](../../../docs/traefik-research-result-final.md#4-static-configuration-traefikyml), [§7 SSL/TLS with Let's Encrypt](../../../docs/traefik-research-result-final.md#7-ssltls-with-lets-encrypt-acme).

#### `$TRAEFIK_HOME/dynamic/middlewares.yml`

Defines reusable middlewares:

- `security-headers`: HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, removes Server/X-Powered-By headers.
- `rate-limit`: 100 avg, 50 burst, period `"1s"`.
- `auth-basic`: references `usersFile: /etc/traefik/auth/.htpasswd`, `removeHeader: true`.
- `ip-allowlist-private`: allows RFC 1918 ranges + loopback, rejects with 403.
- `dashboard-security`: chain of `ip-allowlist-private` + `auth-basic`.
- `compress`: gzip compression.

Reference: [`docs/traefik-research-result-final.md` §5 Dynamic Configuration](../../../docs/traefik-research-result-final.md#5-dynamic-configuration), [§10 Middleware Reference](../../../docs/traefik-research-result-final.md#10-middleware-reference).

#### `$TRAEFIK_HOME/dynamic/tls.yml`

Defines TLS options (dynamic config, not static):

- `default`: TLS 1.2 minimum, `sniStrict: true`, cipher suites include both ECDSA and RSA variants.

Reference: [`docs/traefik-research-result-final.md` §5 Dynamic Configuration — `dynamic/tls.yml`](../../../docs/traefik-research-result-final.md#5-dynamic-configuration), [§12 Security Best Practices — TLS Hardening](../../../docs/traefik-research-result-final.md#12-security-best-practices).

#### `$TRAEFIK_HOME/dynamic/host-services.yml.example`

A commented-out example file showing how to proxy a host-local service via `host.docker.internal`. Not loaded by Traefik (`.example` extension).

Reference: [`docs/traefik-research-result-final.md` §14 Proxying Host-Local Services](../../../docs/traefik-research-result-final.md#14-proxying-host-local-non-docker-services).

### Edge Cases

- All generated YAML files are written atomically — the script writes to a temp file first, then moves it into place. This prevents Traefik from hot-reloading a partially-written file.
- If `$TRAEFIK_DASHBOARD` is `true`, the `traefik.yml` sets `api.dashboard: true` and the dashboard router labels are included in the Docker Compose file. Otherwise both are omitted.

---

## Docker Compose File Generation

### Happy Path

The script generates `$TRAEFIK_HOME/docker-compose.yml` containing:

**Socket proxy service (`socket-proxy`):**

- Image: `ghcr.io/tecnativa/docker-socket-proxy:latest`
- `privileged: true` (required for socket access).
- Environment: `CONTAINERS=1`, `NETWORKS=1`, `EVENTS=1`, `PING=1`, `VERSION=1` — everything else blocked by default.
- Volume: `/var/run/docker.sock:/var/run/docker.sock:ro`
- Network: `socket-net` (internal only).
- Health check: `wget -q --spider http://localhost:2375/_ping`

**Traefik service:**

- Image: `$TRAEFIK_IMAGE` (default: `traefik:v3`).
- `security_opt: [no-new-privileges:true]`
- `depends_on: socket-proxy` with `condition: service_healthy`.
- Ports: `$HTTP_PORT` and `$HTTPS_PORT` with `mode: host` (preserves real client IP behind NAT).
- `extra_hosts: ["host.docker.internal:host-gateway"]` (required on Linux for host-local service proxying).
- Volumes: `traefik.yml`, `dynamic/`, `letsencrypt/`, `auth/` — all mounted read-only except `letsencrypt`.
- Networks: `socket-net` + `proxy`.
- Labels: `traefik.enable=true`, `traefik.docker.network=proxy`.
- If `$TRAEFIK_DASHBOARD` is `true`: additional labels for the dashboard router (`Host`, entrypoints, `service=api@internal`, `tls.certresolver=letsencrypt`, `middlewares=dashboard-security@file`).
- If `$DNS_PROVIDER` is set and DNS challenge credentials exist (e.g. `$CF_DNS_API_TOKEN`): passed as environment variables to the Traefik container.

**Networks:**

- `socket-net`: `internal: true` (no external routing).
- `proxy`: `external: true` (pre-created by the script).

Reference: [`docs/traefik-research-result-final.md` §6 Docker Compose Setup — Pattern A](../../../docs/traefik-research-result-final.md#6-docker-compose-setup), [§13 Docker Socket Proxy](../../../docs/traefik-research-result-final.md#13-docker-socket-proxy-pattern), [§18 NAT Router & Real Client IP](../../../docs/traefik-research-result-final.md#18-nat-router--real-client-ip).

### Edge Cases

- If `$TRAEFIK_DASHBOARD` is `true` but `$TRAEFIK_DOMAIN` is still the default `traefik.example.com`, print a yellow warning that the dashboard domain should be changed for production use.

---

## Stack Startup and Health Check

### Happy Path

The script starts the stack:

1. `docker compose -f $TRAEFIK_HOME/docker-compose.yml pull` — pull latest images.
2. `docker compose -f $TRAEFIK_HOME/docker-compose.yml up -d` — start in detached mode.
3. Wait up to 60 seconds for the Traefik container to become healthy, polling every 5 seconds. Health is confirmed when `docker ps --filter name=traefik --format '{{.Status}}'` shows the container is running.

On success, print a green message: "Traefik is up and running."

### Error Cases

- **`docker compose pull` fails:** Print a red error with the compose log output and exit 1.
- **`docker compose up -d` fails:** Print a red error with the compose log output and exit 1.
- **Health check times out (60s):** Print a yellow warning that Traefik may still be starting, suggest `docker compose logs -f traefik`, and continue (do not exit 1 — the container may just be slow to start).

---

## UFW Firewall Rules

### Happy Path

The script opens the required ports via UFW:

```
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

Each rule prints a coloured informational message. If the rule already exists, UFW prints "Skipping adding existing rule" — the script treats this as success.

### Edge Cases

- **UFW not installed or not active:** Print a yellow warning suggesting manual firewall configuration, but do **not** exit 1. The script continues — firewall setup is best-effort.

---

## Summary Output

### Happy Path

After successful setup, the script prints a coloured summary block containing:

- Traefik version and container status.
- Config directory path (`$TRAEFIK_HOME`).
- Dashboard URL (only if `$TRAEFIK_DASHBOARD` is `true`).
- Admin username and generated password (only if dashboard is enabled).
- ACME mode (production or staging) and challenge type (HTTP or DNS).
- Quick-reference instructions for adding a new app to Traefik (labels + proxy network).
- Quick-reference for applying basic auth middleware to an app.
- Useful commands: logs, stop, start, restart.

### Edge Cases

- If the health check timed out, the summary still prints but includes a yellow warning at the top advising the user to check logs.

---

## Shared Helper Library

### Happy Path

The script creates `lib/helpers.sh` (if it does not already exist) containing two functions:

#### `ensure_proxy_network()`

Checks that the `proxy` Docker network exists. If it does not, prints a red error message telling the user to run `setup-traefik.sh` first and exits 1.

#### `ensure_traefik_running()`

Checks that the `traefik` Docker container is running. If it is not, prints a red error message telling the user to start Traefik first and exits 1.

Both functions use the same colour helpers (`info`, `success`, `warn`, `error`) and are designed to be sourced by other `setup-*.sh` scripts:

```bash
source lib/helpers.sh
ensure_proxy_network
ensure_traefik_running
```

### Edge Cases

- If `lib/helpers.sh` already exists, the script does **not** overwrite it — it may contain user additions or helpers from other features. Instead, the script checks whether the two functions are already defined in the file (via `grep`) and appends them only if missing.

---

## Forgejo Integration Update

### Happy Path

The script `tasks/setup-forgejo.sh` is updated to optionally integrate with Traefik:

- At the top of the script, a new env var `FORGEJO_TRAEFIK` (default: `false`) controls whether Traefik integration is enabled.
- When `FORGEJO_TRAEFIK=true`:
  - The script sources `lib/helpers.sh` and calls `ensure_proxy_network`.
  - The generated `docker-compose.yml` adds the `proxy` network (as `external: true`) to the Forgejo service.
  - Traefik labels are added to the Forgejo service: `traefik.enable=true`, `traefik.docker.network=proxy`, router rule using `` Host(`$FORGEJO_DOMAIN`) ``, `entrypoints=websecure`, `tls.certresolver=letsencrypt`, `loadbalancer.server.port=3000`.
  - The direct host port mapping (`$HTTP_PORT:3000`) is **removed** — traffic flows through Traefik instead.
  - The SSH port mapping (`$SSH_PORT:22`) is preserved — SSH Git access does not go through Traefik.
- When `FORGEJO_TRAEFIK=false` (default): The script behaves exactly as it does today — no changes.

Reference: [`docs/traefik-research-result-final.md` §15 Multi-Stack Architecture](../../../docs/traefik-research-result-final.md#15-multi-stack-architecture), [§8 Domain-Based Routing](../../../docs/traefik-research-result-final.md#8-domain-based-routing).

### Error Cases

- **`FORGEJO_TRAEFIK=true` but proxy network does not exist:** `ensure_proxy_network` prints an error and exits 1.
- **`FORGEJO_DOMAIN` not set when `FORGEJO_TRAEFIK=true`:** Print a red error message stating that `FORGEJO_DOMAIN` is required for Traefik integration and exit 1.

### Edge Cases

- Existing Forgejo installations without Traefik continue to work unchanged — the default is `false`.
- When switching from direct port mapping to Traefik, the user must re-run the script (which tears down and recreates the compose stack). The Forgejo data volume is preserved.
