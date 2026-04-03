# LLM Dev/Server Setup Automation Scripts

Bash automation scripts to provision development and production machines for Large Language Model (LLM) workflows on **Ubuntu 24.04**.

---

## Quick Start with an AI Agent

This repository ships an [Agent Skills](https://agentskills.io)-compatible skill that gives any compatible AI agent (Claude Code, pi, etc.) full context about the available automations, how to configure them, and how to run them.

Point your agent at the skill file:
```
skills/machine-setup-automation-assistant/SKILL.md
```

The agent will read the README and discover available scripts on its own, then guide you interactively through choosing, configuring, and running the right setup for your machine.

---

## Quick Start
1. **Clone the repository** (or download a zip) and `cd` into it:
   ```bash
   git clone https://github.com/your-org/machine_setup_automation.git
   cd machine_setup_automation
   ```
2. **Make sure you have sudo rights** - all scripts call `sudo` where required.
3. **Run the desired entrypoint**:
   - For a *server* (headless VM, cloud instance):
    ```bash
    ./setup-server.sh    # sources basics → sshd → docker → lm-studio → firewall → opencode …
    ```
   - For a *development workstation* (your laptop/desktop):
    ```bash
    ./setup-dev-machine.sh
    ```
4. **Follow the on-screen prompts** - most scripts are non-interactive; they print progress and final status messages.
5. After the script finishes you should have:
   - Docker ready (run `docker run hello-world` to double-check).
   - SSH listening on the custom port (`sshd` service is enabled).
   - LM Studio binary at `$HOME/lmstudio_bin` with a start shortcut at `$HOME/lmstudio`.
   - UFW firewall allowing SSH, LM Studio (and optionally OpenWebUI and Opencode) ports.

---

## How It Works
- **Modular task scripts** - Each `setup_*.sh` script is self-contained and idempotent; it can be sourced individually from an entrypoint or run on its own.
- **Single-shell execution** - The entrypoint scripts (`setup-server.sh`, `setup-dev-machine.sh`) use `source` so that environment variables defined in earlier tasks are visible to later ones (e.g., custom ports).
- **Configuration via env vars** - All tunable values have sensible defaults and can be overridden by exporting the variable before invoking an entrypoint, making it easy to adapt the automation to different environments.
- **Optional components are commented out** - Features like Kubernetes, Brave or VS Code are included but disabled by default; developers simply uncomment the corresponding `source` line in the entrypoint to enable them.

---

## Service Setup Scripts (`tasks/`)

All service setup scripts are located in the `tasks/` directory. Below is a complete list of available services organized by category.

### System & Infrastructure

#### `setup-basics.sh`
Installs common system packages (curl, git, python3, etc.), **uv** Python package manager, and Node.js/npm.

**Environment variables:** None

#### `setup-docker.sh`
Installs Docker Engine from the official Docker repository, adds the current user to the `docker` group and verifies the installation.

**Environment variables:** None

#### `setup-kubernetes.sh`
Installs a lightweight **k3s** cluster and the `k9s` TUI for Kubernetes management.

**Environment variables:** `K9S_VERSION` (default `0.50.7`)

#### `setup-traefik.sh`
Deploys production-ready Traefik v3 reverse proxy with Docker Compose, TLS via Let's Encrypt, security headers, rate limiting, and optional protected dashboard.

**Environment variables:** `TRAEFIK_HOME`, `TRAEFIK_DOMAIN`, `TRAEFIK_DASHBOARD`, `ACME_EMAIL` (**required**), `ACME_STAGING`, `DNS_PROVIDER`, `CF_DNS_API_TOKEN`, `TRAEFIK_ADMIN_USER`, `TRAEFIK_ADMIN_PASS`, `PROXY_NETWORK`, `HTTP_PORT`, `HTTPS_PORT`, `USE_SOCKET_PROXY`

**See also:** [README_TRAEFIK.md](README_TRAEFIK.md) for full documentation

#### `setup-upstream-kernel.sh`
Prepares the Zabbly mainline kernel apt repository on Ubuntu 22.04/24.04 LTS, providing access to the latest stable Linux kernels.

**Environment variables:** None (uses defaults from Zabbly repository)

**Notes:**
- Requires Secure Boot to be disabled in BIOS/UEFI
- May require DKMS rebuild for NVIDIA proprietary drivers
- Officially supports Ubuntu Noble (24.04) and Jammy (22.04)

#### `setup-sshd.sh`
Installs OpenSSH server, ensures it runs on a custom port, adds safe defaults (`PubkeyAuthentication yes`, `PasswordAuthentication no`).

**Environment variables:** `SSHD_PORT` (default 2224)

#### `configure-firewall.sh`
Sets up **UFW** rules for the ports used by other services.

**Environment variables:** `SSHD_PORT`, `LM_STUDIO_PORT` (default 1234), `OPENWEBUI_PORT` (default 3333), `KUBERNETES_API_PORT` (default 6443), `GNOME_REMOTE_PORT` (default 3389), `OPENCODE_PORT` (default 4096)

---

### AI & LLM Services

#### `setup-lm-studio.sh`
Downloads the specified LM Studio AppImage, creates a desktop entry, an optional start script, and optionally installs the **llmster** CLI (`lms`).

**Environment variables:** `LM_STUDIO_VERSION` (default `0.4.2-2`), `INSTALL_LLMSTER_ENABLED` (default `true`)

#### `setup-llama-cpp.sh`
Builds and installs llama.cpp from source with auto or manual GPU backend selection. Skips install if binaries are already present.

**Environment variables:** `INSTALL_DIR` (default `$HOME/llama.cpp`), `BACKEND` (`nvidia`, `amd`, `cpu`, auto-detected if empty), `FORCE` (default `0`), `JOBS` (default `nproc`)

#### `setup-openwebui.sh`
Deploys Open WebUI using Docker Compose, connecting to an external LM Studio instance for AI model inference. Supports both direct access mode and Traefik reverse-proxy integration.

**Environment variables:** `OPENWEBUI_PORT` (default 3333), `LM_STUDIO_PORT` (default 1234), `PROJECT_DIR` (default `$HOME/open-webui`), `WEBUI_SECRET_KEY` (auto-generated if not set), `OPENWEBUI_TRAEFIK` (default `false`), `OPENWEBUI_DOMAIN` (required when Traefik enabled), `PROXY_NETWORK` (default `proxy`)

**Features:**
- Direct mode: Accessible at `http://localhost:3333`
- Traefik mode: Accessible via custom domain with TLS
- Auto-generates secure secret key stored in `.env` file
- Creates convenience start script

#### `setup-opencode-server.sh`
Installs and configures the Opencode AI coding agent server with systemd integration.

**Environment variables:** `OPENCODE_PORT` (default 4096), `OPENCODE_HOSTNAME` (default `0.0.0.0`), `OPENCODE_SERVER_USERNAME` (default `opencode`), `OPENCODE_SERVER_PASSWORD` (auto-generated if empty), `OPENCODE_INSTALL_METHOD` (`npm` or `curl`), `GENERATE_PASSWORD` (default `false`)

#### `setup-agent-docker-runner.sh`
Installs the Agent Docker Runner (ADR) CLI, a tool that runs coding agents inside isolated Docker containers with a single command. Supports multiple agents: pi, opencode, claude, codex.

**Environment variables:** `ADR_REPO_URL` (default official repo), `ADR_INSTALL_DIR` (default `$HOME/tools/agent-docker-runner`), `ADR_BUILD_AGENTS` (default `pi,opencode,claude,codex`)

**Features:**
- Runs any supported agent in isolated Docker containers
- Single CLI command: `adr run <agent> -- <args>`
- Auto-builds container images for all agents
- Configuration examples included
- Supports pi, opencode, claude code, and GitHub Copilot Workspace (codex)

#### `setup-nanobot.sh`
Clones the Nanobot agent repository, builds the Docker image, and runs the onboarding flow.

**Environment variables:** `NANOBOT_TARGET_REPO_DIRECTORY` (default `$HOME/nanobot`)


#### `setup-hermes.sh`
Sets up the Hermes Agent environment using the official prebuilt Docker image. Creates configuration files and provides convenience scripts for management.

**Environment variables:** `HERMES_TARGET_REPO_DIRECTORY` (default `/srv/hermes`), `BUILD_ONLY` flag via command line (`--build-only`)

**Features:**
- Official Hermes Agent MCP gateway
- Prebuilt Docker image from nousresearch
- Setup wizard for initial configuration
- Hermes Gateway and Chat services
- Data persistence in `.hermes` directory

#### `setup-pi.sh`
Installs the latest Node.js via nvm and the **Pi coding agent** npm package globally.

**Environment variables:** None

---

### Speech & Dictation

#### `setup-hyprwhspr.sh`
Installs **hyprwhspr** — native Wayland speech-to-text dictation for Linux. Handles ydotool 1.0+ backport (Ubuntu ships a broken 0.1.x), clones the repo, and runs the automated setup wizard.

**Environment variables:** `HYPRWHSPR_INSTALL_DIR` (default `~/hyprwhspr`), `HYPRWHSPR_BACKEND` (`nvidia`, `vulkan`, `cpu`, `onnx-asr`, auto-detected), `HYPRWHSPR_MODEL`, `HYPRWHSPR_WAYBAR` (default `false`), `HYPRWHSPR_MIC_OSD` (default `true`), `HYPRWHSPR_SYSTEMD` (default `true`), `HYPRWHSPR_HYPR_BINDINGS` (default `false`), `HYPRWHSPR_SKIP_DEPS` (default `false`)

#### `setup-whispering.sh`
Downloads the Whispering speech-to-text AppImage, creates a start script (`~/whispering`) and a desktop shortcut. Backs up any existing binary before downloading.

**Environment variables:** `WHISPERING_VERSION` (default `7.11.0`)

---

### Project Management & Collaboration

#### `setup-forgejo.sh`
Installs Forgejo (a Gitea fork) as a Docker container. Supports optional Traefik reverse-proxy integration via `FORGEJO_TRAEFIK_ENABLED`.

**Environment variables:** `FORGEJO_TRAEFIK_ENABLED` (default `false`), `FORGEJO_DOMAIN`, `FORGEJO_HTTP_PORT` (default `3000`), `FORGEJO_SSH_PORT` (default `222`), `PROXY_NETWORK` (default `proxy`)

#### `setup-concourse.sh`
Deploys Concourse CI, a continuous integration platform, using Docker Compose. Includes TSA key generation, PostgreSQL database, web UI (ATC), and worker node configuration. Also installs the fly CLI on the host machine.

**Environment variables:** `CONCOURSE_HOME` (default `/srv/concourse`), `CONCOURSE_WEB_PORT` (default 8089), `CONCOURSE_ADMIN_USER` (default `admin`), `CONCOURSE_ADMIN_PASSWORD` (auto-generated), `CONCOURSE_DB_PASSWORD` (auto-generated), `CONCOURSE_CLUSTER_NAME` (default `denkfabrik`), `CONCOURSE_DNS_SERVER` (default `8.8.8.8`), `CONCOURSE_EXTERNAL_URL` (auto-detected), `CONCOURSE_FLY_TARGET` (default `concourse`), `CONCOURSE_TRAEFIK` (default `false`), `CONCOURSE_DOMAIN`, `PROXY_NETWORK`

**Features:**
- Complete CI/CD pipeline platform with web UI
- PostgreSQL database for persistence
- Worker node for job execution
- TSA key generation for secure worker registration
- fly CLI installation and auto-configuration
- Optional Traefik reverse-proxy integration
- Auto-generates admin password and database credentials

#### `setup-planka.sh`
Installs Planka, a self-hosted Kanban board, via Docker Compose with PostgreSQL. Auto-generates a secret key and supports interactive or headless admin user creation.

**Environment variables:** `PLANKA_HOME` (default `/srv/planka`), `PLANKA_IMAGE` (default `ghcr.io/plankanban/planka:latest`), `HTTP_PORT` (default `4444`), `BASE_URL` (default `http://localhost:4444`), `POSTGRES_PASSWORD`, `SECRET_KEY` (auto-generated), `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `ADMIN_NAME`, `ADMIN_USERNAME`

---

### Storage & File Sharing

#### `setup-nextcloud.sh`
Deploys NextCloud cloud storage platform via Docker Compose with MariaDB backend. Provides file syncing, sharing, and collaboration features.

**Environment variables:** `NEXTCLOUD_HOME` (default `/srv/nextcloud`), `HTTP_PORT` (default `4600`), `BASE_URL`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `NEXTCLOUD_VERSION`

#### `setup-n8n.sh`
Deploys n8n, a workflow automation platform, via Docker Compose with PostgreSQL backend. Supports optional Traefik reverse-proxy integration for secure HTTPS access.

**Environment variables:** `N8N_DIR` (default `/srv/n8n`), `TRAEFIK_ENABLED` (default `false`), `DOMAIN_NAME`, `SUBDOMAIN`, `N8N_PORT` (default 5678), `GENERIC_TIMEZONE`, `SSL_EMAIL`

**Features:**
- Visual workflow builder with 200+ integrations
- Self-hosted with full data control
- Supports webhooks, schedules, and triggers
- PostgreSQL backend for persistence
- Optional Traefik reverse-proxy integration

#### `setup-samba.sh`
Installs and configures Samba file sharing.

**Environment variables:** `BASE_SHARE_PATH`, `SAMBA_SHARE_NAME`, `SHARE_PATH`, `SAMBA_USER`, `DEVELOPER_GROUP_NAME`

---

### Graphics & Whiteboarding

#### `setup-excalidraw.sh`
Pulls and runs the Excalidraw virtual whiteboard as a Docker container with an `always` restart policy.

**Environment variables:** `HOST_PORT` (default `5005`)

#### `setup-comfy.sh` *(placeholder)*
Placeholder for future ComfyUI setup.

**Environment variables:** None

---

### Remote Access & Desktop

#### `setup-anydesk.sh`
Installs AnyDesk remote desktop from the official apt repository.

**Environment variables:** None

#### `setup-brave.sh`
Installs the Brave browser from its official apt repository.

**Environment variables:** None

#### `setup-vscode.sh`
Installs VS Code from Microsoft's official repository.

**Environment variables:** None

---

### Hardware & GPU

#### `setup-rocm.sh`
Installs ROCm for AMD GPU acceleration support.

**Environment variables:** None (hardcodes ROCm 7.0 alpha repo)

---

### SSH Utilities

#### `setup-ssh-tunnel-user.sh`
Creates a locked-down SSH user with no shell access, configured exclusively for port-forwarding tunnels.

**Environment variables:** `RESTRICTED_USER` (default `tunneluser`)

> **Note:** See `utilities/ssh-port-forward.sh` for SSH tunneling utilities.

---

## Utility Scripts (`utilities/`)

### `run-llama-server.sh`
A generalized launcher for llama.cpp's llama-server with sensible defaults based on your manual configuration. Automatically enables flash attention, GPU layers, and KV cache settings. When run without `--model`, it lists all available `.gguf` models in `$HOME/.lmstudio/models/`.

**Key features:**
- Uses your default parameters (temperature, context size, GPU layers, etc.)
- Automatically enables `--no-mmap`, `--kv-unified`, and `--flash-attn`
- Lists models on `$HOME/.lmstudio/models/` when `--model` is omitted
- All parameters can be overridden via arguments or environment variables

**Default parameters:**
| Parameter | Default |
|-----------|---------|
| HOST | `0.0.0.0` |
| PORT | `1236` |
| TEMPERATURE | `0.6` |
| TOP_K | `40` |
| TOP_P | `0.95` |
| REPEAT_PENALTY | `1.00` |
| PRESENCE_PENALTY | `0.00` |
| PARALLEL | `1` |
| THREADS_COUNT | `14` |
| PRIO | `1` |
| CONTEXT_SIZE | `100000` |
| BATCH_SIZE | `512` |
| FLASH_ATTENTION | `on` |
| GPU_LAYERS | `all` |
| KV_CACHE_TYPE | `q4_0` |

**Usage examples:**
```bash
# List all available .gguf models in ~/.lmstudio/models/ and exit
./utilities/run-llama-server.sh

# Start server with your default model and parameters
./utilities/run-llama-server.sh

# Start server with a specific model (uses all defaults)
./utilities/run-llama-server.sh --model ~/models/Qwen2.5-7B-Instruct.gguf

# Custom port and host
./utilities/run-llama-server.sh --model ~/models/model.gguf --port 1236 --host 0.0.0.0

# Override specific parameters
./utilities/run-llama-server.sh --model model.gguf --temperature 0.8 --ctx-size 50000

# Disable flash attention (override default)
./utilities/run-llama-server.sh --model model.gguf -fa off

# Set environment variables for customization
export PORT=1237
export TEMPERATURE=0.7
./utilities/run-llama-server.sh --model model.gguf
```

**Environment variables (all optional):**
- `MODEL_PATH` - Default model path
- `HOST`, `PORT` - Server binding
- `TEMPERATURE`, `TOP_K`, `TOP_P`, `REPEAT_PENALTY`, `PRESENCE_PENALTY`, `PARALLEL` - Generation parameters
- `THREADS_COUNT`, `PRIO`, `CONTEXT_SIZE`, `BATCH_SIZE`, `FLASH_ATTENTION`, `GPU_LAYERS`, `KV_CACHE_TYPE` - Performance parameters
- `KV_UNIFIED` - Enable unified KV cache (default: true)

### `ssh-port-forward.sh`
Simple SSH tunnel wrapper for creating secure port forwards from a local machine to a remote server.

**Usage:**
```bash
./ssh-port-forward.sh <local_port> <remote_host> <remote_port> <ssh_user> [ssh_port]
```

**Parameters:**
- `local_port` - Local port to forward from
- `remote_host` - Remote server hostname or IP
- `remote_port` - Port on the remote server to forward to
- `ssh_user` - SSH username for the remote server
- `ssh_port` - SSH port on the remote server (optional, defaults to 22)

**Example:**
```bash
# Forward local port 3333 to remote server 192.168.0.3 port 3333
./ssh-port-forward.sh 3333 192.168.0.3 3333 myuser 2224
```

This creates an SSH tunnel that forwards connections from `localhost:3333` through the SSH connection to `192.168.0.3:3333`. The tunnel remains active until you press Ctrl+C.

---

## Customization & Environment Variables
The scripts are deliberately **parameterised via environment variables** that you can override before invoking the entrypoint. Two common ways to customise:
1. **Export variables in your shell session** before running the script:
   ```bash
   export SSHD_PORT=2222
   export LM_STUDIO_PORT=1240
   export OPENWEBUI_PORT=3344
   ./setup-dev-machine.sh
   ```
2. **Edit the default values directly** at the top of each task script (e.g., change `LM_STUDIO_VERSION="0.4.0-18"` in `setup-lm-studio.sh`). This is handy for a permanent change across all runs.

---

## Troubleshooting & FAQ
1. **`sudo: command not found`** - Ensure you run the scripts on a system where `sudo` is installed (Ubuntu default). You must have a user with sudo privileges.
2. **Docker fails to start** - After `setup-docker.sh`, verify group membership:
   ```bash
   groups $USER | grep docker && echo "User is in docker group"
   # If not, log out/in or run: newgrp docker
   ```
3. **Port conflicts** - If a port (e.g., `2224`) is already used, export a different value before running the scripts.
4. **LM Studio AppImage does not launch** - Ensure the file at `$HOME/lmstudio_bin` has execute permission (`chmod +x`). The start script `$HOME/lmstudio` runs `./lmstudio_bin --no-sandbox`; you can add additional flags there.
5. **UFW refuses to enable** - Check if another firewall manager (e.g., `firewalld`) is active; disable it or stick with UFW for this automation.
6. **k3s installation fails** - The script uses the official get.k3s.io installer which requires a clean system without conflicting container runtimes. Remove any existing Docker/Kubernetes installations before re-running, or run k3s on a separate VM.

---

## Additional Documentation
- **[README_TRAEFIK.md](README_TRAEFIK.md)** - Complete guide for the Traefik v3 reverse proxy setup script (`setup-traefik.sh`)

---

## Agentic Engineering & Specification

This project uses the **[spec-framework](https://github.com/julweber/spec-framework)** for agentic engineering - a structured approach to defining, reviewing, and implementing features through AI-assisted workflows.

The full project specification (description, architecture, concepts, conventions, feature specs, and tasks) can be found in the **`specification/`** directory.

---

## Contributing
Feel free to fork this repository and add new task scripts (e.g., for additional AI tools) or improve existing ones. When adding a script:
- Place it under `tasks/` if it is part of the core provisioning flow, otherwise put it in an appropriate sub-folder.
- Document any environment variables at the top of the file.
- Update this README (or add a new section) describing the purpose and usage.

---

## License & Disclaimer
This project is provided **as-is** without warranty. Use at your own risk, especially when opening ports or running services on publicly reachable machines.
