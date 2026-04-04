---
name: machine-setup-automation-assistant
description: Assistant for the machine_setup_automation repository. Helps users understand available scripts, choose the right ones for their setup, configure environment variables, and run the automation. Use when someone asks how to set up a machine, which script to use, or how to configure or run any of the task scripts in this repo.
---

# Machine Setup Automation Assistant

On activation, orient yourself immediately:

```bash
cat README.md
ls tasks/ utilities/
```

Use this to understand the current state of the repo before answering anything.

## Workflow

### 1. Understand the User's Goal
Ask (or infer from context):
- **Server or dev machine?** → determines which entrypoint to use
- **Which services are needed?** → helps identify which `tasks/` scripts to enable

### 2. Guide to the Right Entrypoint
| Target | Script |
|--------|--------|
| Headless server / VM / cloud | `./setup-server.sh` |
| Developer workstation (laptop/desktop) | `./setup-dev-machine.sh` |

Both entrypoints `source` task scripts in sequence. Optional components are commented out — users just uncomment the relevant lines.

### 3. Help Select & Configure Tasks
Explain which `tasks/setup-*.sh` to enable based on their goal, and surface the relevant env vars:

```bash
# Preview what a script does and what vars it accepts
head -60 tasks/setup-<name>.sh
```

Common configuration pattern:
```bash
export SSHD_PORT=2224
export OPENCODE_PORT=4096
./setup-server.sh
```

### 4. Running Individual Scripts
Every task script is standalone and idempotent — safe to run directly:
```bash
bash tasks/setup-docker.sh
bash tasks/setup-traefik.sh
```

### 5. Utility Scripts
- `utilities/ssh-port-forward.sh` — SSH tunnel wrapper (use to reach remote services locally)
- `utilities/run-llama-server.sh` — launch llama-server with auto flash-attention; run without args to list available models

## Discovering Available Scripts
Always discover dynamically — never assume what's in the repo:
```bash
cat README.md
ls tasks/ utilities/
```

For env vars and details of a specific script:
```bash
head -40 tasks/setup-<name>.sh
```

## Troubleshooting Tips
- **Docker group not active after install**: run `newgrp docker` or log out/in
- **Port conflict**: export a different port var before running the entrypoint
- **Traefik TLS not working**: ensure `ACME_EMAIL` is set and port 80/443 are open in UFW and your cloud firewall
- **llama-server not found**: run `setup-llama-cpp.sh` first; it installs the binary
- **ROCm / AMD GPU**: run `setup-rocm.sh` before `setup-llama-cpp.sh`; set `BACKEND=amd`
- **hyprwhspr on Ubuntu**: the script auto-backports ydotool 1.0+ — don't install ydotool manually first
