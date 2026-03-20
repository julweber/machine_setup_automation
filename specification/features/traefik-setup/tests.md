# Tests — traefik-setup

## Test Approach

All behaviors are verified manually on a live Ubuntu 24.04 machine. Automated testing is limited to static analysis (ShellCheck), consistent with the project's current test strategy.

---

## Automated Tests

### T-01: ShellCheck — `tasks/setup-traefik.sh`

- Run `shellcheck tasks/setup-traefik.sh`
- **Pass:** No errors or warnings.

### T-02: ShellCheck — `lib/helpers.sh`

- Run `shellcheck lib/helpers.sh`
- **Pass:** No errors or warnings.

### T-03: ShellCheck — `tasks/setup-forgejo.sh` (updated)

- Run `shellcheck tasks/setup-forgejo.sh`
- **Pass:** No errors or warnings after Traefik integration changes.

---

## Manual Verification

All remaining behaviors (pre-flight validation, argument parsing, idempotency handling, network creation, directory structure, credential generation, configuration file generation, Docker Compose generation, stack startup & health check, UFW firewall rules, summary output, shared helper library, and Forgejo integration) are verified manually on a live Ubuntu 24.04 machine.
