# Concourse CI Setup - Behaviors

## 1. Pre-flight Checks

### Description
Before attempting any setup, the script validates that required dependencies are installed and configured correctly.

### Happy Path
- Docker is installed and the daemon is running
- OpenSSL is available for password and key generation
- curl is available for health checks
- The specified web port (default 8089) is available or Traefik integration is enabled
- All checks pass and setup proceeds

### Error Cases
- **Docker not installed**: Script exits with error message directing user to run `setup-docker.sh` first
- **Docker daemon not running**: Script exits with error message instructing user to start Docker
- **OpenSSL missing**: Script exits with error since OpenSSL is required for cryptographic operations
- **curl missing**: Script exits with error since curl is needed for health check polling

### Edge Cases
- When `CONCOURSE_TRAEFIK=true`:
  - The script sources the helper library and verifies the proxy network exists
  - If `CONCOURSE_DOMAIN` is not set, the script exits with an error
- When `CONCOURSE_TRAEFIK=false`:
  - If the web port is already in use, the user is warned and prompted to confirm whether to proceed

---

## 2. Idempotency Detection

### Description
The script checks if a Concourse deployment already exists and prompts the user before taking destructive action.

### Happy Path
- No existing `docker-compose.yml` found at the target directory
- Setup proceeds with fresh installation

### Error Cases
- **Existing deployment detected**: User is shown a warning with the path to the existing configuration file
  - If user confirms re-creation: Old stack is stopped and removed, but key directories and data are preserved
  - If user declines: Script exits gracefully without modifying anything

### Edge Cases
- When re-creating an existing deployment:
  - RSA keys in `keys/` directory are preserved to maintain session continuity
  - PostgreSQL data in the named volume persists across re-deployments
  - The `.env` file is regenerated with new passwords (existing credentials are lost)

---

## 3. Directory Creation

### Description
Creates the necessary directory structure for Concourse configuration and cryptographic keys.

### Happy Path
- Target directory (`CONCOURSE_HOME`, default `/srv/concourse`) is created if it doesn't exist
- Subdirectories `keys/web` and `keys/worker` are created
- All directories are accessible by the Docker daemon

### Error Cases
- **Permission denied**: If the script cannot create directories under `CONCOURSE_HOME`, it exits with an error
- **File exists where directory expected**: If a file (not a directory) exists at the target path, the script fails

### Edge Cases
- The keys directories are created fresh on each run to ensure clean state
- If the script is re-running after failure mid-way through, existing key files are preserved during key generation phase

---

## 4. RSA Key Generation

### Description
Generates three pairs of RSA keys required for Concourse's TSA (Transport Layer Security Agent) authentication system.

### Happy Path
- **TSA host key pair**: Used by the web node to identify itself to workers
- **Session signing key pair**: Used to sign user session JWT tokens (browser + fly CLI)
- **Worker key pair**: Used by the worker to authenticate itself to TSA during registration

All keys are generated with empty passphrases (Concourse doesn't support passphrase-protected keys).

### Error Cases
- **OpenSSL unavailable**: Script exits if OpenSSL is not installed or accessible
- **Permission denied on key files**: If generated keys cannot be written, script fails

### Edge Cases
- **Idempotent generation**: Keys are only created if they don't already exist
  - This preserves session continuity when re-running the setup
  - Existing authorized_worker_keys file is preserved
- **Key permissions**: After generation, `chmod -R 700` is applied to the keys directory for security

---

## 5. Environment File Generation

### Description
Creates a `.env` file containing all configuration values and auto-generated secrets.

### Happy Path
- PostgreSQL database password is generated using `openssl rand -base64 32`
- Admin user password is generated using `openssl rand -base64 32`
- External URL is auto-detected from the host's LAN IP address
- All variables are written to `.env` file with appropriate permissions (chmod 600)

### Error Cases
- **Password generation failure**: If OpenSSL random generation fails, script exits
- **File permission error**: If `.env` cannot be made private (600), script fails

### Edge Cases
- User-provided values take precedence over auto-generated ones:
  - `CONCOURSE_ADMIN_PASSWORD`: Only generated if empty
  - `CONCOURSE_DB_PASSWORD`: Only generated if empty
  - `CONCOURSE_EXTERNAL_URL`: Auto-detected unless explicitly set
  - `CONCOURSE_WEB_PORT`, `CONCOURSE_CLUSTER_NAME`, etc.: Use defaults or user overrides

---

## 6. Docker Compose Generation

### Description
Dynamically generates a `docker-compose.yml` file with all three Concourse services (web, worker, PostgreSQL).

### Happy Path
- PostgreSQL service is configured with health check and volume persistence
- Web node service includes:
  - Dependencies on database health
  - All required environment variables for authentication and cryptography
  - Port mapping for web UI and TSA
  - Volume mounts for keys directory
- Worker service includes:
  - `privileged: true` (required for nested container spawning)
  - TSA configuration pointing to web node
  - Graceful shutdown with SIGUSR2 signal

### Error Cases
- **Template generation failure**: If the compose file cannot be written, script exits
- **YAML syntax error in generated file**: Detected by Docker Compose on `up` command

### Edge Cases
- **Traefik integration**: When `CONCOURSE_TRAEFIK=true`:
  - Traefik network is added to compose networks
  - Service labels are added for Traefik routing
  - Web UI port is not exposed to host (only internal)
- **Port availability check skipped**: When using Traefik, the script skips checking if the web port is in use on the host

---

## 7. Image Pull & Stack Start

### Description
Pulls Docker images and starts the Concourse stack in detached mode.

### Happy Path
- All three images (`postgres:15`, `concourse/concourse:latest`) are successfully pulled
- Services start in correct order (database first due to dependencies)
- Stack runs in detached mode (`docker compose up -d`)

### Error Cases
- **Image pull failure**: Network issues or Docker Hub unavailability cause script to exit
- **Service startup failure**: If any container fails to start, logs are displayed

### Edge Cases
- Pulling images before starting helps detect connectivity issues early
- Health check on PostgreSQL ensures web node doesn't start until database is ready

---

## 8. Health Check Loop

### Description
Polls the Concourse web UI API endpoint to verify the service is fully operational.

### Happy Path
- Script polls `/api/v1/info` endpoint every 5 seconds
- HTTP 200, 302, or 303 response indicates successful startup
- Script continues once Concourse becomes available (within max wait of 120s)

### Error Cases
- **Timeout reached**: If Concourse doesn't respond within 120 seconds:
  - User is warned that Concourse may still be starting
  - Logs are suggested for troubleshooting

### Edge Cases
- When using Traefik, health check uses `docker exec` to reach the web container internally
- The loop handles transient connection refused errors gracefully
- Successful detection works whether accessing via direct IP:port or through Traefik

---

## 9. Fly CLI Installation

### Description
Downloads and installs the `fly` CLI tool on the host machine if not already present.

### Happy Path
- Architecture is detected (x86_64 → amd64, aarch64 → arm64)
- Fly binary is downloaded from Concourse web UI API endpoint
- Binary is verified as valid ELF 64-bit executable
- System-wide installation to `/usr/local/bin/fly`

### Error Cases
- **Unsupported architecture**: Script exits with error for unrecognized CPU architectures
- **Invalid download**: If the downloaded file is not a valid binary (e.g., HTML error page), script fails
- **Installation permission denied**: If `sudo install` fails, script exits

### Edge Cases
- **Idempotent installation**: If `fly` is already in PATH, installation is skipped
- **Version matching**: Since fly is downloaded directly from the running Concourse instance, versions always match
- **ARM64 support**: Explicit handling for ARM devices (Raspberry Pi, Apple Silicon)

---

## 10. Fly Target Configuration

### Description
Configures a named target in `~/.flyrc` for authenticated access to the Concourse instance.

### Happy Path
- `fly login` command executes non-interactively with admin credentials
- Authentication token is saved to `~/.flyrc`
- Login succeeds and target is configured

### Error Cases
- **Login failure**: If authentication fails, script exits with error
- **Network timeout**: If Concourse is not yet fully responsive, login may fail

### Edge Cases
- Credentials used are the auto-generated values from `.env` file
- Target name is configurable via `CONCOURSE_FLY_TARGET` (default: "concourse")
- The target URL matches `CONCOURSE_EXTERNAL_URL` exactly to prevent OAuth callback errors

---

## 11. Summary Output

### Description
After successful setup, displays a summary of deployment information and useful commands.

### Happy Path
- Web UI URL is shown
- Admin credentials are displayed (admin username + auto-generated password)
- Data directory location is shown
- Docker Compose file path is shown
- Fly target name is shown
- Useful management commands are printed

### Edge Cases
- When using Traefik, output reflects that access is via Traefik rather than direct IP:port
- All important information is formatted for easy copying (credentials clearly marked)
