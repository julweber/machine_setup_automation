# machine_setup_automation — Test Suite

## Overview

Docker-based integration tests for the machine setup scripts. Every test runs inside a disposable Ubuntu 24.04 container with systemd — **zero impact on your host system**.

## Prerequisites

- Docker installed and running on the host
- Access to `ubuntu:24.04` image (`docker pull ubuntu:24.04`)
- The repo cloned locally

## Quick Start

```bash
# Run everything (static + unit + integration)
./tests/run-all.sh

# Run only integration tests
./tests/run-all.sh integration

# Run a single test
./tests/run-integration.sh test-docker

# Run only unit tests
./tests/run-all.sh unit
```

## Architecture

```
tests/
├── lib/
│   ├── container-manager.sh   # Container lifecycle (create, exec, destroy)
│   └── test-helpers.sh        # Assertion functions
├── unit/
│   └── test-helpers.bats      # BATS unit tests for helpers.sh
└── integration/
    ├── test-basics.sh         # setup-basics.sh
    ├── test-docker.sh         # setup-docker.sh
    ├── test-sshd.sh           # setup-sshd.sh
    └── test-firewall.sh       # configure-firewall.sh
```

## How It Works

1. **Container creation** — Each test spins up a fresh `ubuntu:24.04` container with systemd (`/sbin/init`), giving real service management.
2. **Repo injection** — The automation repo is copied into the container via `docker cp`.
3. **User setup** — A test user is created with passwordless sudo.
4. **Script execution** — Setup scripts run inside the container as the test user.
5. **Assertions** — Commands check package installation, service state, config files, and user permissions.
6. **Cleanup** — Container is destroyed regardless of pass/fail.

## Writing New Tests

Copy an existing test from `integration/` and modify:
- `CONTAINER_NAME` — unique name (include `$$` for PID uniqueness)
- `SCRIPT_PATH` — path to the setup script inside the container
- `ENV_VARS` — any environment variables to set
- `assert_*` calls — your verification checks

## Notes

- Tests use `--privileged` containers for full systemd support. If your environment doesn't support this, see `container-manager.sh` for the `fake-systemd` fallback.
- Each test takes ~60-120s (container + systemd start + script execution).
- Network access is inherited from the host for package downloads and Docker key fetching.
