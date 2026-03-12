# LLM Dev/Server Setup Automation Scripts

## Overview
This repository provides a collection of **Bash automation scripts** to quickly provision a development or production machine for Large Language Model (LLM) workflows on **Ubuntu 24.04**. The scripts handle common tasks such as:
- Installing system dependencies and developer tools.
- Setting up SSH with a custom port.
- Configuring the firewall.
- Installing Docker and optional Kubernetes (k3s).
- forgejo as gitlab/github alternative
- Deploying LM Studio, Open WebUI, Opencode and other LLM-related services.
- Providing helper utilities for SSH tunneling

The goal is to let a developer **run a single entrypoint script** and end up with a fully functional LLM development environment that can be further customized.

---

## Directory Structure
```text
machine_setup_automation/
├── README.md                     # ← This file (documentation)
├── setup_server.sh                # Main entry for server-side setup
├── setup_dev_machine.sh           # Main entry for a developer workstation
├── tasks/                         # Core provisioning scripts (sourced by the entrypoints)
│   ├── configure_firewall.sh      # UFW rules for SSH, LM Studio, OpenWebUI …
│   ├── setup_anydesk.sh           # Install AnyDesk remote desktop (optional)
│   ├── setup_basics.sh            # System packages & basic Python tooling
│   ├── setup_brave.sh             # Install Brave browser (optional)
│   ├── setup_comfy.sh             # Placeholder for ComfyUI install (future work)
│   ├── setup_docker.sh            # Docker Engine + group permissions
│   ├── setup_excalidraw.sh        # Run Excalidraw whiteboard as a Docker container
│   ├── setup_forgejo.sh           # Forgejo (Gitea fork) installation via Docker
│   ├── setup_kubernetes.sh        # k3s cluster + k9s CLI (optional)
│   ├── setup_llama_cpp.sh         # Build and install llama.cpp (NVIDIA/AMD/CPU)
│   ├── setup_planka.sh            # Planka Kanban board via Docker Compose
│   ├── setup_lm_studio.sh         # Download LM Studio AppImage, optional llmster cli
│   ├── setup_nanobot.sh           # Clone, build and onboard the Nanobot MCP gateway
│   ├── setup_opencode_server.sh   # Opencode AI agent server installation and configuration
│   ├── setup_openwebui.sh         # *Deprecated* - see `old/` for historic version
│   ├── setup_pi.sh                # Install the Pi coding agent via npm
│   ├── setup_rocm.sh              # Install ROCm for AMD GPU support (optional)
│   ├── setup_samba.sh             # Install and configure Samba file sharing (optional)
│   ├── setup_ssh_tunnel_user.sh   # Create a restricted tunnel-only SSH user
│   ├── setup_sshd.sh              # OpenSSH server with configurable port
│   ├── setup_vscode.sh            # Install VS Code (optional)
│   └── setup_whispering.sh        # Whispering speech-to-text AppImage setup
├── utilities/                     # Miscellaneous helper tools
│   └── ssh_port_forward.sh        # Simple SSH tunnel wrapper
```

*Only the files under `tasks/`, `utilities/`, and the two top-level entrypoint scripts are required for a minimal LLM workstation.

---

## Directory Structure Principles
- **Modular task scripts** - Each `setup_*.sh` script is self-contained and idempotent; it can be sourced individually from an entrypoint or run on its own.
- **Single-shell execution** - The entrypoint scripts (`setup_server.sh`, `setup_dev_machine.sh`) use `source` so that environment variables defined in earlier tasks are visible to later ones (e.g., custom ports).
- **Configuration via env vars** - All tunable values have sensible defaults and can be overridden by exporting the variable before invoking an entrypoint, making it easy to adapt the automation to different environments.
- **Optional components are commented out** - Features like Kubernetes, Brave or VS Code are included but disabled by default; developers simply uncomment the corresponding `source` line in the entrypoint to enable them.
- **Separate concerns** - Helper utilities (`utilities/`) live outside of `tasks/` to keep the core provisioning flow focused and maintainable.

---

## Core Task Scripts (`tasks/`)
| Script                           | Primary purpose                                                                                                                                                        | Key environment variables                                                                                                                                                                                                                                                                                                |        |                                                                                 |
| ----------------------------------| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| --------| ---------------------------------------------------------------------------------|
| `setup_anydesk.sh`               | Installs AnyDesk remote desktop from the official apt repository.                                                                                                      | None                                                                                                                                                                                                                                                                                                                     |        |                                                                                 |
| `setup_basics.sh`                | Installs common system packages (curl, git, python3, etc.), **uv** Python package manager, and Node.js/npm.                                                            | None                                                                                                                                                                                                                                                                                                                     |        |                                                                                 |
| `setup_brave.sh`                 | Installs the Brave browser from its official apt repository.                                                                                                           | None                                                                                                                                                                                                                                                                                                                     |        |                                                                                 |
| `setup_comfy.sh` *(placeholder)* | Placeholder for future ComfyUI setup.                                                                                                                                  | -                                                                                                                                                                                                                                                                                                                        |        |                                                                                 |
| `setup_docker.sh`                | Installs Docker Engine from the official Docker repository, adds the current user to the `docker` group and verifies the installation.                                 | None                                                                                                                                                                                                                                                                                                                     |        |                                                                                 |
| `setup_excalidraw.sh`            | Pulls and runs the Excalidraw virtual whiteboard as a Docker container with an `always` restart policy.                                                                | `HOST_PORT` (default `5005`)                                                                                                                                                                                                                                                                                             |        |                                                                                 |
| `setup_forgejo.sh`               | Installs Forgejo (a Gitea fork) as a Docker container.                                                                                                                 | None                                                                                                                                                                                                                                                                                                                     |        |                                                                                 |
| `setup_kubernetes.sh`            | Installs a lightweight **k3s** cluster and the `k9s` TUI for Kubernetes management.                                                                                    | `K9S_VERSION` (default `0.50.7`)                                                                                                                                                                                                                                                                                         |        |                                                                                 |
| `setup_lm_studio.sh`             | Downloads the specified LM Studio AppImage, creates a desktop entry, an optional start script, and optionally installs the **llmster** CLI (`lms`).                    | `LM_STUDIO_VERSION` (default `0.4.2-2`), `INSTALL_LLMSTER_ENABLED` (default `true`)                                                                                                                                                                                                                                      |        |                                                                                 |
| `setup_llama_cpp.sh`             | Builds and installs llama.cpp from source with auto or manual GPU backend selection. Skips install if binaries are already present.                                    | `INSTALL_DIR` (default `$HOME/llama.cpp`), `BACKEND` (`nvidia`\                                                                                                                                                                                                                                                          | `amd`\ | `cpu`, auto-detected if empty), `FORCE` (default `0`), `JOBS` (default `nproc`) |
| `setup_nanobot.sh`               | Clones the Nanobot MCP gateway repository, builds the Docker image, and runs the onboarding flow.                                                                      | `NANOBOT_TARGET_REPO_DIRECTORY` (default `$HOME/nanobot`)                                                                                                                                                                                                                                                                |        |                                                                                 |
| `setup_planka.sh`                | Installs Planka, a self-hosted Kanban board, via Docker Compose with PostgreSQL. Auto-generates a secret key and supports interactive or headless admin user creation. | `PLANKA_HOME` (default `/srv/planka`), `PLANKA_IMAGE` (default `ghcr.io/plankanban/planka:latest`), `HTTP_PORT` (default `4444`), `BASE_URL` (default `http://localhost:4444`), `POSTGRES_PASSWORD` (empty = trust auth), `SECRET_KEY` (auto-generated), `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `ADMIN_NAME`, `ADMIN_USERNAME` |        |                                                                                 |
| `setup_opencode_server.sh`       | Installs and configures the Opencode AI coding agent server with systemd integration.                                                                                  | `OPENCODE_PORT` (default 4096), `OPENCODE_HOSTNAME` (default `0.0.0.0`), `OPENCODE_SERVER_USERNAME` (default `opencode`), `OPENCODE_SERVER_PASSWORD` (auto-generated if empty), `OPENCODE_INSTALL_METHOD` (`npm` or `curl`), `GENERATE_PASSWORD` (default `false`)                                                       |        |                                                                                 |
| `setup_pi.sh`                    | Installs the latest Node.js via nvm and the **Pi coding agent** npm package globally.                                                                                  | None                                                                                                                                                                                                                                                                                                                     |        |                                                                                 |
| `setup_rocm.sh`                  | Installs ROCm for AMD GPU acceleration support.                                                                                                                        | None (hardcodes ROCm 7.0 alpha repo)                                                                                                                                                                                                                                                                                     |        |                                                                                 |
| `setup_samba.sh`                 | Installs and configures Samba file sharing.                                                                                                                            | `BASE_SHARE_PATH`, `SAMBA_SHARE_NAME`, `SHARE_PATH`, `SAMBA_USER`, `DEVELOPER_GROUP_NAME`                                                                                                                                                                                                                                |        |                                                                                 |
| `setup_ssh_tunnel_user.sh`       | Creates a locked-down SSH user with no shell access, configured exclusively for port-forwarding tunnels.                                                               | `RESTRICTED_USER` (default `tunneluser`)                                                                                                                                                                                                                                                                                 |        |                                                                                 |
| `setup_sshd.sh`                  | Installs OpenSSH server, ensures it runs on a custom port, adds safe defaults (`PubkeyAuthentication yes`, `PasswordAuthentication no`).                               | `SSHD_PORT` (default 2224)                                                                                                                                                                                                                                                                                               |        |                                                                                 |
| `configure_firewall.sh`          | Sets up **UFW** rules for the ports used by other services.                                                                                                            | `SSHD_PORT`, `LM_STUDIO_PORT` (default 1234), `OPENWEBUI_PORT` (default 3333), `KUBERNETES_API_PORT` (default 6443), `GNOME_REMOTE_PORT` (default 3389), `OPENCODE_PORT` (default 4096)                                                                                                                                  |        |                                                                                 |
| `setup_vscode.sh`                | Installs VS Code from Microsoft's official repository.                                                                                                                 | None                                                                                                                                                                                                                                                                                                                     |        |                                                                                 |
| `setup_whispering.sh`            | Downloads the Whispering speech-to-text AppImage, creates a start script (`~/whispering`) and a desktop shortcut. Backs up any existing binary before downloading.     | `WHISPERING_VERSION` (default `7.11.0`)                                                                                                                                                                                                                                                                                  |        |                                                                                 |

> **How the entrypoints work**: Both `setup_server.sh` and `setup_dev_machine.sh` simply `source` a selected subset of these task scripts, allowing you to run them in order within a single Bash process.

---

## Utility Scripts (`utilities/`)
- **`ssh_port_forward.sh`** - A tiny wrapper that creates an SSH tunnel forwarding a local port to a remote host/port. Usage:
  ```bash
  ./ssh_port_forward.sh <local_port> <remote_host> <remote_port> <ssh_user> [ssh_port]
  # Example: forward localhost:3333 to 192.168.0.3:3333 via user "myuser" on port 2224
  ./ssh_port_forward.sh 3333 192.168.0.3 3333 myuser 2224
  ```
  The script prints colour-coded status messages and keeps the tunnel alive until you interrupt it with **Ctrl+C**.

Useful tunnel commands:
   ```bash
   REMOTE_HOST=myserver.example.com
   REMOTE_USER="myuser"
   PORT="2224"

   # lmstudio
   ./ssh_port_forward.sh 1234 "$REMOTE_HOST" 1234 "$REMOTE_USER" "$PORT"

   # openwebui
   ./ssh_port_forward.sh 3333 "$REMOTE_HOST" 3333 "$REMOTE_USER" "$PORT"

   # opencode
   ./ssh_port_forward.sh 4096 "$REMOTE_HOST" 4096 "$REMOTE_USER" "$PORT"
   ```

---

## Quick Start (Minimal LLM Workstation)
1. **Clone the repository** (or download a zip) and `cd` into it:
   ```bash
   git clone https://github.com/your-org/machine_setup_automation.git
   cd machine_setup_automation
   ```
2. **Make sure you have sudo rights** - all scripts call `sudo` where required.
3. **Run the desired entrypoint**:
   - For a *server* (headless VM, cloud instance):
```bash
      ./setup_server.sh    # sources basics → sshd → docker → lm-studio → firewall → opencode …
      ```
   - For a *development workstation* (your laptop/desktop):
     ```bash
     ./setup_dev_machine.sh
     ```
4. **Follow the on-screen prompts** - most scripts are non-interactive; they print progress and final status messages.
5. After the script finishes you should have:
   - Docker ready (run `docker run hello-world` to double-check).
   - SSH listening on the custom port (`sshd` service is enabled).
   - LM Studio binary at `$HOME/lmstudio_bin` with a start shortcut at `$HOME/lmstudio`.
   - UFW firewall allowing SSH, LM Studio (and optionally OpenWebUI and Opencode) ports.

---

## Customization & Environment Variables
The scripts are deliberately **parameterised via environment variables** that you can override before invoking the entrypoint. Two common ways to customise:
1. **Export variables in your shell session** before running the script:
   ```bash
   export SSHD_PORT=2222
   export LM_STUDIO_PORT=1240
   export OPENWEBUI_PORT=3344
   ./setup_dev_machine.sh
   ```
2. **Edit the default values directly** at the top of each task script (e.g., change `LM_STUDIO_VERSION="0.4.0-18"` in `setup_lm_studio.sh`). This is handy for a permanent change across all runs.

### Frequently overridden variables
| Variable | Default | Where it's used |
|----------|---------|-----------------|
| `SSHD_PORT` | `2224` | `setup_sshd.sh`, `configure_firewall.sh` |
| `LM_STUDIO_PORT` | `1234` | `configure_firewall.sh` (firewall rule), optional OpenWebUI integration |
| `OPENWEBUI_PORT` | `3333` | `configure_firewall.sh` |
| `KUBERNETES_API_PORT` | `6443` | `configure_firewall.sh` |
| `GNOME_REMOTE_PORT` | `3389` | `configure_firewall.sh` |
| `OPENCODE_PORT` | `4096` | `setup_opencode_server.sh`, `configure_firewall.sh` |
| `LM_STUDIO_VERSION` | `0.4.2-2` | `setup_lm_studio.sh` |
| `INSTALL_LLMSTER_ENABLED` | `true` | `setup_lm_studio.sh` |
| `K9S_VERSION` | `0.50.7` | `setup_kubernetes.sh` |

---

## Optional / Advanced Components
- **Kubernetes (k3s)** – Uncomment the line `# source tasks/setup_kubernetes.sh` in either entrypoint if you need a local cluster. The script will install k3s and the `k9s` CLI.
- **Brave Browser** – Uncomment `# source tasks/setup_brave.sh` to add Brave to the setup.
- **VS Code** – Uncomment `# source tasks/setup_vscode.sh` to install VS Code from Microsoft's official repository.
- **ROCm** – Uncomment `# source tasks/setup_rocm.sh` for AMD GPU acceleration support (requires compatible AMD hardware).
- **Samba file sharing** – Uncomment `# source tasks/setup_samba.sh` to enable network file sharing.
- **OpenWebUI** – The original script lives in `old/`. If you wish to re-enable it, copy it into `tasks/` and source it from the entrypoint. It currently builds a Docker Compose stack that connects OpenWebUI to LM Studio.
- **Opencode Server** – Uncomment `# source tasks/setup_opencode_server.sh` to install and configure the Opencode AI coding agent server with systemd integration.
- **AnyDesk** – Uncomment `# source tasks/setup_anydesk.sh` to install the AnyDesk remote desktop client.
- **Excalidraw** – Uncomment `# source tasks/setup_excalidraw.sh` to spin up a self-hosted Excalidraw whiteboard (Docker required). Accessible at `http://localhost:5005` by default.
- **Nanobot** – Uncomment `# source tasks/setup_nanobot.sh` to clone, build, and onboard the Nanobot agent gateway (Docker required).
- **Pi coding agent** – Uncomment `# source tasks/setup_pi.sh` to install the Pi AI coding assistant globally via npm (requires nvm).
- **SSH Tunnel User** – Uncomment `# source tasks/setup_ssh_tunnel_user.sh` to create a locked-down SSH user for secure port-forwarding tunnels. Set `RESTRICTED_USER` to choose the username.
- **Planka** – Uncomment `# source tasks/setup_planka.sh` to deploy a self-hosted Planka Kanban board (Docker required). Accessible at `http://localhost:4444` by default. Set `ADMIN_EMAIL` and `ADMIN_PASSWORD` for a fully non-interactive setup.
- **llama.cpp** – Uncomment `# source tasks/setup_llama_cpp.sh` to build and install llama.cpp from source. The script auto-detects your GPU (NVIDIA CUDA, AMD Vulkan, or CPU-only) and skips the build if binaries are already present. Pass `--nvidia`, `--amd`, or `--cpu` to force a specific backend.
- **Whispering** – Uncomment `# source tasks/setup_whispering.sh` to install the Whispering speech-to-text AppImage. A start script is placed at `~/whispering` and a desktop shortcut at `~/Desktop/Whispering.desktop`. Override `WHISPERING_VERSION` to select a specific release.

---

## Troubleshooting & FAQ
1. **`sudo: command not found`** - Ensure you run the scripts on a system where `sudo` is installed (Ubuntu default). You must have a user with sudo privileges.
2. **Docker fails to start** - After `setup_docker.sh`, verify group membership:
   ```bash
   groups $USER | grep docker && echo "User is in docker group"
   # If not, log out/in or run: newgrp docker
   ```
3. **Port conflicts** - If a port (e.g., `2224`) is already used, export a different value before running the scripts.
4. **LM Studio AppImage does not launch** - Ensure the file at `$HOME/lmstudio_bin` has execute permission (`chmod +x`). The start script `$HOME/lmstudio` runs `./lmstudio_bin --no-sandbox`; you can add additional flags there.
5. **UFW refuses to enable** - Check if another firewall manager (e.g., `firewalld`) is active; disable it or stick with UFW for this automation.
6. **k3s installation fails** - The script uses the official get.k3s.io installer which requires a clean system without conflicting container runtimes. Remove any existing Docker/Kubernetes installations before re-running, or run k3s on a separate VM.

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
