# Conventions

## Code Style

- All Bash scripts must start with `#!/usr/bin/env bash` and `set -eu`.
- Scripts must pass **ShellCheck** (`shellcheck <script>`) with no errors or warnings before being committed.
- Follow general Bash best practices:
  - Always quote variables: `"$VAR"`, not `$VAR`.
  - Use `[[ ]]` for conditionals instead of `[ ]`.
  - Prefer `$(command)` over backticks for command substitution.

## Naming Conventions

- No strict naming conventions enforced at this time.
- Task scripts follow the pattern `setup_<component>.sh` or `configure_<component>.sh` in `tasks/`.
- Environment variables use `UPPER_SNAKE_CASE`.

## Architectural Patterns

- **Idempotency** — Every task script must be safe to run repeatedly. Use guard checks (`command -v`, `dpkg -l`, file existence) to skip already-completed work.
- **Non-interactive by default** — Scripts must not prompt the user for input during normal execution. Interactive behaviour is only allowed when the script is explicitly invoked with a `--interactive` flag.
- **Help and Usage instructions** - All shell scripts have a `--help` parameter to display usage and configuration information
- **Env var configuration** — All tunable values must be exposed as environment variables with sensible defaults defined at the top of each script.
- **Single-process sourcing** — Task scripts are sourced (not executed as subprocesses) so that env vars flow between scripts.

## Output and Logging

- Scripts should produce **colourful, expressive output** so users can see the most important information at a glance.
- Use colour-coded messages to distinguish status levels (e.g., green for success, yellow for warnings/skipped steps, red for errors, blue/cyan for informational progress).
- Clearly indicate what is being installed, what was skipped (already present), and what completed successfully.

## Libraries and Utilities

- **Firewall:** Always use `ufw`. Never use `iptables` directly.

## Anti-Patterns

- **No interactive prompts** unless `--interactive` is explicitly passed.
- **No unquoted variables** — always quote to prevent word splitting and globbing.
- **No ShellCheck violations** — all scripts must be clean before merge.
