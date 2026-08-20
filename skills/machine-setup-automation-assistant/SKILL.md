---
name: machine-setup-automation-assistant
description: Assistant for the machine_setup_automation repository. Guides users through the YAML-configured orchestrator (run-setup.sh) to provision machines for LLM workflows. Helps select services, configure machine-config.yml, and run setups. Use when someone asks how to set up a machine, which service to install, or how to configure any task in this repo.
Invoke this skill when the users asks for usage instructions or repository introduction.
---

# Machine Setup Automation Assistant

On activation, orient yourself immediately:

```bash
cat README.md
ls tasks/ utilities/
```

## Core Concept

This repo uses a **single orchestrator** (`run-setup.sh`) driven by a **YAML configuration file** (`machine-config.yml`). There are no separate server/dev-machine entrypoints — the same orchestrator works for any machine. Users declare which services they want in YAML, then run one command.

## Workflow

### 1. Understand the User's Goal

Ask (or infer from context):
- **What kind of machine?** (server, dev workstation, laptop, cloud VM) — this influences which services to enable, not which script to run
- **Which services are needed?** — helps you recommend which entries to set `enabled: true` in the config

### 2. Bootstrap the Configuration

Guide the user through these steps:

```bash
# Step 1: Copy the example config
cp machine-config.yml.example machine-config.yml

# Or use the pre-configured inference stack:
# cp machine-config-inference.yml.example machine-config.yml

# Step 2: Preview what's available
./run-setup.sh status
```

Explain the output: it shows every script, whether it's enabled, and any configured env vars/args.

### 3. Help Select & Configure Services

Edit `machine-config.yml` to enable the services the user needs. The YAML format:

```yaml
version: 1

scripts:
  setup-docker:
    enabled: true
    env: {}
    args: []
  setup-llama-cpp:
    enabled: true
    env:
      BACKEND: 'nvidia'
      FORCE: '1'
      JOBS: '8'
    args: []
  setup-traefik:
    enabled: true
    env:
      ACME_EMAIL: user@example.com
      TRAEFIK_DOMAIN: myserver.example.com
    args: []
```

**Key rules to communicate:**
- `version` is the config format version — always set to `1`
- All scripts are **disabled by default** — enable only what you need
- `setup-basics` should almost always be enabled first (installs `yq`, `git`, `curl`, etc.)
- `description` is optional and informational — shown in `./run-setup.sh status` output
- `env` values are strings — use quotes for numbers/booleans: `'true'`, `'8080'`
- `args` are passed as CLI flags to the script
- Use `./run-setup.sh status` after editing to verify before applying

### 4. Preview and Apply

```bash
# Preview what will run
./run-setup.sh status

# Execute all enabled scripts
./run-setup.sh apply
```

The orchestrator runs scripts alphabetically. It continues executing all remaining scripts even if one fails. A summary of successes, failures, and skips is printed at the end (exit code 1 if any failed).

### 5. Custom Config File (optional)

```bash
./run-setup.sh --config path/to/other-config.yml status
./run-setup.sh -c path/to/other-config.yml apply
```

## Running Individual Scripts

Every task script is standalone and idempotent — safe to run directly:

```bash
bash tasks/setup-docker.sh
bash tasks/setup-traefik.sh
```

This is useful for:
- Testing a single service before adding it to the config
- Re-running a failed script after fixing configuration
- Adding a service that's not yet in `machine-config.yml`

## Discovering Available Scripts

Always discover dynamically — never assume what's in the repo:

```bash
# See all task scripts
ls tasks/

# Read README for service descriptions and env vars
cat README.md

# Inspect a specific script for its env vars
head -60 tasks/setup-<name>.sh
```

## Service Categories (from README.md)

When recommending services, group them logically:

| Category | Typical Scripts |
|----------|----------------|
| **System & Infra** | setup-basics, setup-docker, setup-sshd, configure-firewall, setup-traefik, setup-fail2ban, setup-upstream-kernel, setup-ssh-tunnel-user |
| **AI / LLM** | setup-llama-cpp, setup-llama-swap, setup-vllm, setup-vllm-omni, setup-lm-studio, setup-openwebui |
| **AI Agents** | setup-omnigent, setup-opencode-server, setup-nanobot, setup-hermes, setup-pi, setup-agent-docker-runner |
| **Dev Tools** | setup-neovim, setup-zed |
| **Project Mgmt** | setup-forgejo, setup-planka |
| **Storage / Files** | setup-nextcloud, setup-samba, setup-obsidian-livesync |
| **Automation** | setup-n8n |
| **CI/CD** | setup-concourse |
| **Remote Access** | setup-anydesk, setup-virtualization |
| **Speech** | setup-whispering |
| **Browser** | setup-brave |
| **Whiteboarding** | setup-excalidraw |

## Utility Scripts

Located in `utilities/`:

- **`utilities/run-llama-server.sh`** — Launch llama-server with auto flash-attention. Run without `--model` to list available `.gguf` models in `~/.lmstudio/models/`.
- **`utilities/ssh-port-forward.sh`** — SSH tunnel wrapper: `./ssh-port-forward.sh <local_port> <remote_host> <remote_port> <ssh_user> [ssh_port]`
- **`utilities/sync-server-files.sh`** — Incrementally sync a directory from the AI server to a local machine via rsync/SSH (e.g. repos, hermes workspaces). Config via `SYNC_REMOTE_USER`, `SYNC_REMOTE_HOST`, `SYNC_SSH_PORT` (default 2224), `SYNC_DELETE`, `SYNC_SUDO`; options `--source-directory`, `--target-directory`, `--dry-run`, `--verbose`, `--sudo`. See README.md "Utility Scripts" for full docs.

## Common Recommendations by Use Case

### Minimal LLM Server
Enable: `setup-basics`, `setup-docker`, `setup-sshd`, `configure-firewall`, `setup-llama-cpp`

### Full LLM Dev Station
Enable: `setup-basics`, `setup-docker`, `setup-sshd`, `configure-firewall`, `setup-llama-cpp`, `setup-lm-studio`, `setup-openwebui`, `setup-neovim`, `setup-pi`

### Self-Hosted Service Stack
Enable: `setup-basics`, `setup-docker`, `setup-sshd`, `configure-firewall`, `setup-traefik`, `setup-forgejo`, `setup-nextcloud`, `setup-n8n`

## Troubleshooting Tips

- **`yq not found`**: Run `setup-basics` first — it installs `yq`
- **Config file not found**: Copy `machine-config.yml.example` to `machine-config.yml`
- **Docker group not active after install**: Run `newgrp docker` or log out/in
- **Port conflict**: Change the port in `machine-config.yml` env vars for the affected service
- **Traefik TLS not working**: Ensure `ACME_EMAIL` is set and ports 80/443 are open in UFW and your cloud firewall
- **llama-server not found**: Enable `setup-llama-cpp` in the config and run `./run-setup.sh apply`
- **Script fails mid-run**: The orchestrator continues; check the summary. Re-run with `./run-setup.sh apply` — scripts are idempotent
- **Secure Boot blocks kernel modules**: Disable Secure Boot in BIOS/UEFI (affects upstream kernel, NVIDIA drivers)
