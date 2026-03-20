# Architecture

## Tech Stack

- **Language:** Bash (primary)
- **Configuration formats:** Environment variables (primary), with YAML, JSON, or `.env` files where individual components require them
- **Target OS:** Ubuntu 24.04

## System Structure

```text
repository root
├── setup-server.sh          # Entrypoint: headless/cloud server
├── setup-dev-machine.sh     # Entrypoint: developer workstation
├── tasks/                   # Task scripts (one per component)
│   ├── setup-basics.sh
│   ├── setup-sshd.sh
│   ├── setup-docker.sh
│   ├── setup-lm-studio.sh
│   ├── configure-firewall.sh
│   └── ...
└── utilities/               # Standalone helper scripts
    └── ssh-port-forward.sh
```

The architecture follows a simple **linear sourcing model**:

1. The user runs an **entrypoint** script.
2. The entrypoint `source`s **task scripts** sequentially in a defined order.
3. All task scripts execute within a single Bash process, sharing the environment.
4. **Utility scripts** are independent and run separately by the user after provisioning.

## Components

### Entrypoints
- Thin orchestration layers that define which task scripts to source and in what order.
- Two variants: server (headless) and dev machine (desktop).

### Task Scripts
- Each script is responsible for exactly one component.
- Scripts are idempotent — they guard against re-execution using checks like `command -v`, `dpkg -l`, or file existence tests.
- Scripts communicate exclusively through environment variables.

### Utility Scripts
- Post-provisioning helpers that are not part of the setup flow.
- Run independently by the user as needed.

## External Integrations

Task scripts pull from external sources during provisioning:

| Source | Examples |
|--------|----------|
| **OS package repos** | `apt` for system packages |
| **Vendor apt repos** | Docker, Brave, VS Code, ROCm |
| **GitHub releases** | k3s, k9s |
| **Direct downloads** | LM Studio AppImage |
| **Install scripts** | k3s (`get.k3s.io`), Node.js |
| **Docker images** | Forgejo, OpenWebUI, Excalidraw |

Download URLs and versions are currently hardcoded with env var overrides. A future iteration may centralise these in a YAML configuration file.

## Deployment

The repository is cloned directly onto the target machine and executed locally:

```bash
git clone <repo-url>
cd machine_setup_automation
./setup-server.sh   # or ./setup-dev-machine.sh
```

There is no remote execution, CI/CD pipeline, or container wrapping the scripts themselves.
