# Test Strategy

## Test Types

### Currently Implemented
- **Static analysis (ShellCheck)** — All scripts must pass `shellcheck` with no errors or warnings. This is the primary quality gate for now.

### Planned (Future)
- **Integration tests (VM-based)** — Spin up a fresh Ubuntu VM, run entrypoints, and verify scripts complete without errors. Will use KVM/libvirt for local VM automation.
- **Idempotency tests** — Run each entrypoint twice on the same VM and verify the second run produces no errors or unintended side effects.
- **Unit tests (bats)** — Explore using [bats (Bash Automated Testing System)](https://github.com/bats-core/bats-core) for testing individual script functions in isolation.

## What Gets Tested

- **Every script** must pass ShellCheck before being committed.
- Integration and idempotency tests will initially focus on the core provisioning flow (entrypoints and their sourced task scripts).
- Pragmatic coverage — not every edge case needs a test, but the main happy path for each entrypoint must be verified.

## Coverage Expectations

- Pragmatic, not exhaustive. The goal is confidence that provisioning works correctly on a clean Ubuntu machine and that re-running scripts is safe.
- No numeric coverage target.

## Frameworks and Tools

| Tool | Purpose | Status |
|------|---------|--------|
| **ShellCheck** | Static analysis / linting for Bash | Active |
| **KVM / libvirt** | Local VM automation for integration tests | Planned |
| **bats** | Bash unit testing framework | Planned (to evaluate) |

## Test Execution

- **Currently:** ShellCheck runs locally before committing changes.
- **Near-term:** Integration tests run locally using KVM/libvirt to spin up disposable Ubuntu VMs.
- **Future:** CI/CD pipeline (e.g., GitHub Actions) to automate test execution on push/PR.

## Quality Check Definition

A change is considered ready to merge when:
1. All scripts pass `shellcheck` with no errors or warnings.
2. (Future) Integration tests pass on a clean Ubuntu VM.
3. (Future) Idempotency tests pass — second run produces no errors.
