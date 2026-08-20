# Domain Concepts

## Key Entities

### Entrypoint
A top-level Bash script in the repository root (`setup-server.sh`, `setup-dev-machine.sh`) that sources a selected subset of task scripts to provision a specific type of machine. Each entrypoint targets a different use case (headless server vs. desktop workstation).

### Task Script
A self-contained Bash script in `tasks/` that installs and configures a single component. Task scripts are sourced by entrypoints and execute within the same shell process, sharing environment variables. Every task script must be **idempotent**.

### Utility Script
A standalone helper script in `utilities/` that is not part of the provisioning flow. Utilities are run independently by the user after setup (e.g., SSH tunnel helper).

### Component
An application or service that runs on the provisioned machine (e.g., Docker, LM Studio, Forgejo, Samba). Each component is installed and configured by its corresponding task script.

### Environment Variable (Env Var)
The configuration mechanism for the project. All tunable values (ports, versions, feature flags) are exposed as environment variables with sensible defaults. Users override them by exporting values before running an entrypoint.

## Terminology

| Term | Definition |
|------|-----------|
| **Provisioning** | The process of setting up a machine from a base Ubuntu install to a fully configured LLM development or server environment. |
| **Idempotency** | The requirement that every task script can be executed repeatedly without destroying already-made configurations or causing errors. Scripts use guard checks (e.g., `command -v`, `dpkg -l`, file existence tests) to skip work that has already been done. |
| **Sourcing** | Bash `source` command used by entrypoints to run task scripts in the same shell process, so environment variables set by earlier scripts are visible to later ones. |

## Relationships

- An **entrypoint** sources one or more **task scripts**.
- Each **task script** installs and configures exactly one **component**.
- **Task scripts** communicate via **env vars** set earlier in the sourcing chain.
- **Utility scripts** are independent of the provisioning flow and operate on an already-provisioned machine.
