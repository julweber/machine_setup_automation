# LLM Dev/Server Setup Automation Scripts

Bash automation scripts to provision development and production machines for Large Language Model (LLM) workflows on **Ubuntu 24.04**.

---

## Quick Start with an AI Agent

This repository ships an [Agent Skills](https://agentskills.io)-compatible skill that gives any compatible AI agent (Claude Code, pi, etc.) full context about the available automations, how to configure them, and how to run them.

Point your agent at the skill file:
```
Read and execute the instructions in skills/machine-setup-automation-assistant/SKILL.md
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
3. **Copy the example configuration** and edit it to enable the services you want:
   ```bash
   cp machine-config.yml.example machine-config.yml
   ```
   The orchestrator reads `machine-config.yml` by default (or pass `--config <file>` to use a different one).
   Open `machine-config.yml` and set `enabled: true` for the scripts you'd like to install. See the [Configuration](#configuration) section below for the YAML format.
4. **Run the orchestrator**:
   ```bash
   ./run-setup.sh status   # preview what's enabled
   ./run-setup.sh apply    # install all enabled services
   ```
   Run without arguments to see usage instructions.
5. **Follow the on-screen prompts** - most scripts are non-interactive; they print progress and final status messages.
6. After the script finishes you should have:
   - Docker ready (run `docker run hello-world` to double-check).
   - SSH listening on the custom port (`sshd` service is enabled).
   - UFW firewall allowing SSH and other service ports.

---

## How It Works
- **Orchestrator** - `run-setup.sh` reads a YAML configuration file to determine which services to install, then runs them in order. Use `./run-setup.sh status` to preview and `./run-setup.sh apply` to execute. The default config file is `machine-config.yml` in the repository root, or pass a different file with `--config`.
- **Modular task scripts** - Each `tasks/setup-*.sh` script is self-contained and idempotent; it can be run individually or through the orchestrator.
- **Configuration via YAML** - `machine-config.yml` declares which scripts to run, their environment variables, and command-line arguments. All tunable values have sensible defaults and can be overridden.

## Configuration

The orchestrator reads `machine-config.yml` to determine which setup scripts to run. A fresh copy is provided as `machine-config.yml.example` — copy it to `machine-config.yml` before running `run-setup.sh apply`:

```bash
cp machine-config.yml.example machine-config.yml
```

A pre-configured inference stack is also available as `machine-config-inference.yml.example`,
which enables the scripts needed for local LLM inference (llama.cpp, llama-swap, Open WebUI, vLLM, etc.).

### YAML Format

```yaml
version: 1

scripts:
  setup-llama-cpp:
    enabled: true
    description: Build and install llama.cpp with CUDA/Metal support
    env:
      LLAMA_CPP_CUDA: 'true'
      LLAMA_CPP_BUILD_TESTS: 'false'
    args:
      - --force
      - --jobs 8
  setup-openwebui:
    enabled: false
    env: {}
    args: []
```

**Top-level structure:**
- `version` — config format version (currently `1`)
- `scripts` — a map of script name → configuration

**Script configuration:**
- `enabled` — set to `true` to run this script, `false` to skip it
- `description` — human-readable description (informational)
- `env` — key-value pairs passed as environment variables to the script
- `args` — command-line arguments passed to the script

All scripts are **disabled by default** — enable only the ones you need.

### Running the Orchestrator

```bash
./run-setup.sh status   # Show which scripts are enabled/disabled
./run-setup.sh apply    # Install or update all enabled services
./run-setup.sh --config path/to/other-config.yml apply  # Use a custom config file
```

**Options:**
- `--config <file>` / `-c <file>` — Path to a YAML configuration file (default: `machine-config.yml` in the repository root)

When run without any arguments, `run-setup.sh` prints usage instructions.

---

## Service Setup Scripts (`tasks/`)

All service setup scripts are located in the `tasks/` directory. Below is a complete list of available services organized by category.

### System & Infrastructure

#### `setup-basics.sh`
Installs common system packages (curl, git, python3, etc.), **uv** Python package manager, **herdr** CLI tool, Node.js/npm, and the **huggingface-cli**.

**Environment variables:** None

#### `setup-docker.sh`
Installs Docker Engine from the official Docker repository, adds the current user to the `docker` group and verifies the installation.

**Environment variables:** None

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

#### `setup-llama-swap.sh`
Deploys llama-swap, a multi-model LLM proxy with hot-swap support, as a native systemd service. Downloads the Go binary from GitHub releases and generates a comprehensive `config.yaml` with all available options documented.

**Environment variables:** `LLAMA_SWAP_PORT` (default `9292`), `LLAMA_SWAP_DIR` (default `/srv/llama-swap`), `LLAMA_SWAP_HEALTH_TIMEOUT` (default `500`), `LLAMA_SWAP_LOG_LEVEL` (default `info`), `LLAMA_SWAP_START_PORT` (default `10001`), `LLAMA_SWAP_GLOBAL_TTL` (default `0`), `LLAMA_SWAP_LISTEN_ADDR` (default `0.0.0.0:9292`), `LLAMA_SWAP_USER` (default `root`), `LLAMA_SWAP_BIN_PATH` (default `/usr/local/bin/llama-swap`), `LLAMA_SWAP_VERSION` (default `latest`)

**Features:**
- Hot-swap between multiple LLM models without restarting
- OpenAI-compatible API at `/v1/chat/completions`
- Web UI at `/ui`
- Health check endpoint at `/health`
- Comprehensive config with all options documented

#### `setup-colqwen.sh`
Generates a ColQwen2.5 embedding-service Docker project (FastAPI + colpali-engine on an NVIDIA NGC PyTorch base image). Serves multi-vector embeddings (dim 128) for document images and text queries — the retrieval side of visual document RAG. The script only generates the project; build and start it yourself. Models are mounted read-only from the HF cache at the identical path (adapter `base_model_name_or_path` entries resolve) and are never downloaded (fully offline: `HF_HUB_OFFLINE=1`).

**Environment variables:** `PROJECT_DIR` (default `/srv/colqwen`), `COLQWEN_MODEL_DIR` (default `~/.cache/huggingface`), `COLQWEN_MODEL` (default `vidore/colqwen2.5-v0.2`), `COLPALI_VERSION` (default `0.3.13`), `NGC_PYTORCH_TAG` (default `25.10-py3`), `COLQWEN_PORT` (default `8100`)

**Features:**
- `POST /embed/queries` and `POST /embed/images` (multi-vector, one embedding per input, in order)
- `GET /health` readiness probe (200 only after the model is loaded)
- Fails loudly instead of serving wrong data: build aborts if pip replaced the NGC CUDA torch; startup aborts if LoRA adapter weights were silently dropped
- Generated `./test.sh` smoke test (health, embeddings incl. dim check, error cases)
- Tested combination for CUDA 13.0 / driver 580.x hosts (e.g. DGX Spark): NGC `25.10-py3` + colpali-engine `0.3.13` — see comments in the generated `.env` before changing versions

#### `setup-vllm.sh`
Deploys vLLM as a Docker-based OpenAI-compatible inference server. Supports NVIDIA (CUDA), AMD (ROCm), and CPU backends with auto-detection. Mounts the HuggingFace cache directory so models downloaded via `huggingface-cli` are automatically available.

**Environment variables:** `PROJECT_DIR` (default `/srv/vllm`), `HF_CACHE_DIR` (default `~/.cache/huggingface`), `VLLM_PORT` (default `8000`), `VLLM_MODEL`, `HF_TOKEN`, `VLLM_GPU_UTIL` (default `0.90`), `VLLM_EXTRA_ARGS`, `VLLM_TENSOR_PARALLEL` (default `1`), `VLLM_MAX_MODEL_LEN`, `VLLM_DTYPE` (default `auto`), `VLLM_SHM_SIZE` (default `8g`), `VLLM_TRAEFIK` (default `false`), `VLLM_DOMAIN`, `PROXY_NETWORK` (default `proxy`)

**Features:**
- Auto-detects GPU backend (NVIDIA, AMD, or CPU fallback)
- Multi-GPU tensor parallelism support
- LM Studio models directory auto-mount
- Optional Traefik reverse-proxy integration
- Input validation for all configuration values
- Supports `--nvidia`, `--amd`, `--cpu`, `--force`, `--check` flags

#### `setup-vllm-omni.sh`
Deploys **vLLM-Omni** — the official vLLM sub-project for omni-modality serving (TTS/speech, diffusion, image/video generation, any-to-any models like Qwen3-Omni / Cosmos3) — as a Docker-based, OpenAI-compatible server. Uses prebuilt Docker Hub images (no local build), auto-detects the GPU backend, and serves via `vllm serve <model> --omni`. Runs alongside `setup-vllm.sh` on its own port and directory.

**Environment variables:** `PROJECT_DIR` (default `/srv/vllm-omni`), `HF_CACHE_DIR`, `VLLM_OMNI_VERSION` (default `latest`), `VLLM_OMNI_PORT` (default `8091`), `VLLM_OMNI_MODEL`, `HF_TOKEN`, `VLLM_OMNI_GPU_UTIL` (default `0.90`), `VLLM_OMNI_TENSOR_PARALLEL` (default `1`), `VLLM_OMNI_MAX_MODEL_LEN`, `VLLM_OMNI_SHM_SIZE` (default `8g`), `VLLM_OMNI_EXTRA_ARGS`, `VLLM_OMNI_TRAEFIK` (default `false`), `VLLM_OMNI_DOMAIN`, `PROXY_NETWORK` (default `proxy`)

**Features:**
- Prebuilt images: `vllm/vllm-omni` (NVIDIA, amd64/arm64) and `vllm/vllm-omni-rocm` (AMD)
- Auto-detects NVIDIA / AMD / CPU backend (CPU is impractical for generative models)
- Model-agnostic: without `VLLM_OMNI_MODEL` the container is not started (prints next steps)
- Optional Traefik reverse-proxy integration
- Idempotent; supports `--force` and `--check`

#### `setup-omnigent.sh`
Deploys Omnigent — an open-source meta-harness providing a common orchestration layer over multiple AI coding agents (Claude Code, Codex, Cursor, Pi, etc.) — via Docker Compose with Postgres + FastAPI. Also installs the runner CLI (`omnigent`) on the host for local agent execution.

**Environment variables:** `OMNIGENT_HOME` (default `/srv/omnigent`), `OMNIGENT_IMAGE` (default `ghcr.io/omnigent-ai/omnigent-server`), `OMNIGENT_IMAGE_TAG` (default `latest`), `OMNIGENT_PORT` (default `8008`), `OMNIGENT_TRAEFIK` (default `false`), `OMNIGENT_DOMAIN` (required when Traefik enabled), `PROXY_NETWORK` (default `proxy`), `OMNIGENT_AUTH_ENABLED` (default `1`), `OMNIGENT_AUTH_PROVIDER` (`accounts`, `oidc`, or `header`), `OMNIGENT_ACCOUNTS_BASE_URL`, `OMNIGENT_ACCOUNTS_AUTO_OPEN` (default `0`), `OMNIGENT_ACCOUNTS_INIT_ADMIN_USERNAME` (default `admin`), `OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD`, `POSTGRES_USER` (default `omnigent`), `POSTGRES_DB` (default `omnigent`)

**Features:**
- Docker Compose deployment with Postgres backend
- Runner CLI installed on host for local agent execution
- Optional Traefik reverse-proxy integration
- Auto-generated secure secrets in `.env` file
- Health check polling (up to 120s)
- UFW firewall rule configuration (direct mode)

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

#### `setup-whispering.sh`
Downloads the Whispering speech-to-text AppImage, creates a start script (`~/whispering`) and a desktop shortcut. Backs up any existing binary before downloading.

**Environment variables:** `WHISPERING_VERSION` (default `7.11.0`)

---

### Project Management & Collaboration

#### `setup-forgejo.sh`
Installs Forgejo (a Gitea fork) as a Docker container. Supports optional Traefik reverse-proxy integration via `FORGEJO_TRAEFIK_ENABLED`.

**Environment variables:** `FORGEJO_TRAEFIK_ENABLED` (default `false`), `FORGEJO_DOMAIN`, `FORGEJO_HTTP_PORT` (default `3000`), `FORGEJO_SSH_PORT` (default `222`), `PROXY_NETWORK` (default `proxy`)

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

---

### Remote Access & Desktop

#### `setup-anydesk.sh`
Installs AnyDesk remote desktop from the official apt repository.

**Environment variables:** None

#### `setup-brave.sh`
Installs the Brave browser from its official apt repository.

**Environment variables:** None

---

### Development Tools

#### `setup-neovim.sh`
Installs Neovim directly on the host machine (Ubuntu/Debian) with lazy.nvim plugin manager, LSP support via nvim-lspconfig, and essential productivity plugins. Installed via official PPA for latest stable version.

**Environment variables:** `NEOVIM_VERSION` (default `stable`)

**Features:**
- lazy.nvim fast plugin manager with on-demand loading
- nvim-lspconfig for Language Server Protocol support
- telescope.nvim fuzzy finder
- nvim-cmp intelligent code completion
- treesitter advanced syntax highlighting
- gitsigns git integration
- oil.nvim modern file explorer

#### `setup-zed.sh`
Installs the Zed editor on Linux using the official installation script. Supports both stable and preview channels.

**Environment variables:** `ZED_CHANNEL` (default `stable`, also supports `preview`)

**Usage:**
```bash
./setup-zed.sh              # Install stable version
./setup-zed.sh --force      # Reinstall
ZED_CHANNEL=preview ./setup-zed.sh  # Install preview version
```

---

### Virtualization

#### `setup-virtualization.sh`
Installs or updates libvirt (virtualization API) and virt-manager (graphical VM manager) on Debian/Ubuntu-based systems. Configures the libvirt daemon, default networks, and adds the user to the libvirt group.

**Environment variables:** `VIRT_USERNAME` (default: current user)

**Features:**
- Installs QEMU/KVM, libvirt-daemon, bridge-utils
- Graphical virt-manager VM management
- Automatic default network configuration
- User permission setup for libvirt access
- Supports both fresh install and update modes

---

### SSH Utilities

#### `setup-ssh-tunnel-user.sh`
Creates a locked-down SSH user with no shell access, configured exclusively for port-forwarding tunnels.

**Environment variables:** `RESTRICTED_USER` (default `tunneluser`)

> **Note:** See `utilities/ssh-port-forward.sh` for SSH tunneling utilities.

---

### Monitoring & Observability

#### `setup-monitoring.sh`
Deploys a containerized observability stack (Prometheus, Grafana, Node Exporter, cAdvisor) via Docker Compose. Prometheus auto-discovers containers labeled `prometheus.scrape=true` (and `prometheus.port=<port>`) via Docker service discovery and exposes a hot-reloadable Lifecycle API. **cAdvisor** provides per-container CPU/memory/disk/network metrics. Grafana is pre-provisioned with a Node Exporter and a cAdvisor dashboard (no manual import). Data is persisted under `/srv/monitoring` and re-runs never destroy existing state (no `down -v`).

**Exposure modes:**
- **Direct** (default): Grafana at `http://<server-ip>:3100` (published on `0.0.0.0`, reachable from the local network) and the Prometheus UI at `http://127.0.0.1:9090` (loopback only, since the Prometheus UI has **no authentication**). Only the Grafana port gets an UFW allow rule; if you publish Prometheus beyond loopback (`PROMETHEUS_BIND_ADDRESS`), restrict it manually (e.g. `ufw allow from <subnet> to any port 9090 proto tcp`).
- **Traefik** (`GRAFANA_TRAEFIK=true`): Grafana routed via the shared proxy network at `https://GRAFANA_DOMAIN`; Prometheus stays internal. Requires `GRAFANA_DOMAIN` and a running Traefik stack with the shared `proxy` network.

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `MONITORING_HOME` | `/srv` | Base data directory (compose + config live under `$MONITORING_HOME/monitoring`) |
| `MONITORING_DOCKER_NETWORK` | `monitoring-net` | Internal monitoring Docker network |
| `PROXY_NETWORK` | `proxy` | Traefik external network (Traefik mode) |
| `GRAFANA_TRAEFIK` | `false` | Set to `true` to route Grafana via Traefik |
| `GRAFANA_PORT` | `3100` | Host port for Grafana (direct mode) |
| `PROMETHEUS_PORT` | `9090` | Host port for the Prometheus UI (direct mode) |
| `GRAFANA_BIND_ADDRESS` | `0.0.0.0` | Interface to publish the Grafana port on (direct mode; `127.0.0.1` = loopback only) |
| `PROMETHEUS_BIND_ADDRESS` | `127.0.0.1` | Interface to publish the Prometheus UI port on (direct mode; the UI is unauthenticated, so keep it loopback unless you restrict it with UFW) |
| `GRAFANA_DOMAIN` | — | Grafana domain (required when `GRAFANA_TRAEFIK=true`) |
| `GRAFANA_ADMIN_USER` | `admin` | Grafana admin username |
| `GRAFANA_ADMIN_PASSWORD` | auto-generated | Grafana admin password (random if unset, stored in a mode-600 `.env`) |
| `PROMETHEUS_IMAGE_VERSION` | `prom/prometheus:v3.13.2` | Prometheus image tag |
| `GRAFANA_IMAGE_VERSION` | `grafana/grafana:13.1.1` | Grafana image tag |
| `NODE_EXPORTER_IMAGE_VERSION` | `quay.io/prometheus/node-exporter:v1.12.1` | Node Exporter image tag |
| `CADVISOR_IMAGE_VERSION` | `ghcr.io/google/cadvisor:v0.60.5` | cAdvisor image tag |
| `MONITORING_FORCE` | `false` | Set to `true` to re-create an existing stack (data preserved) |

**Usage examples:**
```bash
# Direct mode (default): Grafana on the LAN (0.0.0.0), Prometheus on 127.0.0.1
./tasks/setup-monitoring.sh

# Direct mode with everything on loopback
GRAFANA_BIND_ADDRESS=127.0.0.1 ./tasks/setup-monitoring.sh

# Traefik mode
GRAFANA_TRAEFIK=true GRAFANA_DOMAIN=grafana.example.com ./tasks/setup-monitoring.sh
```

> **Note:** To monitor a service, label its container `prometheus.scrape=true` and `prometheus.port=<port>`. The Grafana admin password is stored in `/srv/monitoring/grafana/.env` (mode 600). Reload Prometheus config without a restart: `docker compose -f /srv/monitoring/docker-compose.yml exec prometheus wget -q --post-data='' http://localhost:9090/-/reload`.

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

There are two ways to customize the setup:

1. **Edit `machine-config.yml`** — Set environment variables and command-line arguments for each script in the configuration file. This is the recommended way for declarative, reproducible setups.
2. **Edit default values directly** in each task script (e.g., change `LM_STUDIO_VERSION="0.4.0-18"` in `setup-lm-studio.sh`). This is handy for a permanent change across all runs.

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
- **[README_MANAGING_MODELS.md](README_MANAGING_MODELS.md)** - Guide for managing models via huggingface cli
- **[tests/README.md](tests/README.md)** - Test suite documentation and usage guide
---

## Contributing
Feel free to fork this repository and add new task scripts (e.g., for additional AI tools) or improve existing ones. When adding a script:
- Place it under `tasks/` if it is part of the core provisioning flow, otherwise put it in an appropriate sub-folder.
- Document any environment variables at the top of the file.
- Update this README (or add a new section) describing the purpose and usage.

---

## License & Disclaimer
This project is provided **as-is** without warranty. Use at your own risk, especially when opening ports or running services on publicly reachable machines.
