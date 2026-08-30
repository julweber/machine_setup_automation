# Changelog

## [2026-07-01] setup-omnigent.sh — Deploy Omnigent Meta-Harness

### Added
- **`tasks/setup-omnigent.sh`** (740 lines) — Full setup script for deploying Omnigent, an open-source meta-harness that provides a common orchestration layer over multiple AI coding agents (Claude Code, Codex, Cursor, Pi, etc.)
  - **Preflight checks** — Docker, daemon, openssl, curl via `run_preflight_checks()` from `lib/helpers.sh`
  - **Dual-mode deployment** — Traefik (opt-in via `OMNIGENT_TRAEFIK=true`) or direct mode
  - **Idempotent .env generation** — Auto-generates `POSTGRES_PASSWORD`, `OMNIGENT_ACCOUNTS_COOKIE_SECRET`, `OMNIGENT_OIDC_COOKIE_SECRET` using `set_or_replace_kv` pattern from upstream `bootstrap.sh`
  - **Section-based compose generation** — No template file; conditional sections assembled via variables (`SECTION_NETWORKS`, `SECTION_SERVER_ENV`, `SECTION_SERVER_PORTS`, `SECTION_SERVER_LABELS`, etc.)
  - **Health check** — 120s polling (direct) or container check (Traefik)
  - **Runner CLI installation** — uv, omnigent CLI via `uv tool install`, PATH wiring
  - **Prerequisites** — tmux, bubblewrap (Linux), Node.js 22+ (with `worker_threads.markAsUncloneable` probe)
  - **Host registration** — `omnigent login` + `omnigent host` (direct) or command printing (Traefik)
  - **UFW rule** — Port 8000/tcp in direct mode via `ufw_add_rule()`
  - **Cleanup trap** — Tears down partial failures, disabled on success
  - **--help flag** — Prints available environment variables and defaults

### Pattern References
- `lib/helpers.sh` — shared logging, preflight checks, UFW helpers, proxy network detection
- `tasks/setup-forgejo.sh` — section-based compose generation, dual-mode (Traefik/direct), port mapping
- `tasks/setup-openwebui.sh` — .env secret generation, health check with timeout, cleanup trap, Traefik label injection
- `tasks/setup-hermes.sh` — template-based config (not used here — plan explicitly says "no template file")
- `deploy/docker/bootstrap.sh` — idempotent `set_or_replace_kv` pattern
- `scripts/install_oss.sh` — prerequisite detection (Node.js 22+ via symbol probing, tmux, bubblewrap, uv, PATH wiring)
- `deploy/docker/docker-compose.yaml` — source compose to adapt (postgres + omnigent services, auth env vars)

### Validation
- ✅ `shellcheck tasks/setup-omnigent.sh` passes (0 errors)
- ✅ `bash -n tasks/setup-omnigent.sh` syntax OK
- ✅ Sources `lib/helpers.sh` and uses shared functions
- ✅ Compose file generation uses section variables (no template file)
- ✅ .env generation uses `set_or_replace_kv` pattern
- ✅ Cleanup trap present and functional
- ✅ Health check with timeout (120s)
- ✅ Traefik mode: proxy network check, Traefik running check, domain validation
- ✅ Direct mode: port conflict check, UFW rule
- ✅ Runner CLI installation with uv, PATH wiring, verification
- ✅ Prerequisites check (tmux, bubblewrap, Node.js 22+)
- ✅ Host registration (direct mode) or command printing (Traefik mode)
- ✅ Summary output with access info and useful commands
- ✅ Idempotent: re-running doesn't destroy data
- ✅ `--help` flag implemented

### Configuration Defaults
| Variable | Default |
|----------|---------|
| `OMNIGENT_HOME` | `/srv/omnigent` |
| `OMNIGENT_IMAGE` | `ghcr.io/omnigent-ai/omnigent-server` |
| `OMNIGENT_IMAGE_TAG` | `latest` |
| `OMNIGENT_PORT` | `8000` |
| `OMNIGENT_TRAEFIK` | `false` |
| `OMNIGENT_DOMAIN` | *(empty)* |
| `PROXY_NETWORK` | `proxy` |
| `OMNIGENT_AUTH_PROVIDER` | *(empty)* |
| `OMNIGENT_ACCOUNTS_BASE_URL` | *(empty)* |
| `OMNIGENT_ACCOUNTS_AUTO_OPEN` | `0` |

## $(date -Iseconds) - reviewer

### Findings
- [x] Section-based compose generation follows setup-forgejo.sh pattern correctly
- [x] Idempotent .env generation matches upstream bootstrap.sh pattern
- [x] Cleanup trap present and functional
- [x] Health check with 120s timeout implemented
- [x] Traefik mode: proxy network check, Traefik running check, domain validation
- [x] Direct mode: port conflict check, UFW rule
- [x] Runner CLI installation with uv, PATH wiring, verification
- [x] Prerequisites check (tmux, bubblewrap, Node.js 22+)
- [x] Host registration (direct mode) or command printing (Traefik mode)
- [x] Summary output with access info and useful commands
- [x] Idempotent: re-running doesn't destroy data
- [x] --help flag implemented (but placed after main logic)
- [ ] **BUG: --help flag placed after main logic** — script runs all pre-flight checks before checking for --help; should be at top of script
- [ ] **WARNING: Traefik mode health check skips container verification** — sets READY=true immediately without checking if omnigent container is running
- [x] No new files in templates/ or lib/ — scope adherence confirmed
- [x] shellcheck passes with 0 errors
- [x] Sources lib/helpers.sh and uses shared functions
- [x] Compose file generation produces valid YAML

## $(date -Iseconds) - reviewer

### Findings
- [x] **BUG FIXED: Missing `POSTGRES_USER` and `POSTGRES_DB` in .env** — Added `set_or_replace_kv` calls for `POSTGRES_USER` and `POSTGRES_DB` after the derived values section. The compose file's `DATABASE_URL` references these variables (with defaults `omnigent`), but the .env file now explicitly sets them, matching the upstream `bootstrap.sh` pattern and operator expectations.
- [x] Fix follows existing `set_or_replace_kv` pattern and idempotency conventions
- [x] No other issues found

## 2026-08-02T10:30:00 - worker

### Implemented: Monitoring stack (Prometheus + Grafana + Node Exporter)

- [x] `tasks/setup-monitoring.sh` (new, executable) — idempotent deployment script. Sources `lib/helpers.sh`, `set -euo pipefail`, cleanup trap. Pre-flight: run_preflight_checks, Compose v2 check, GRAFANA_DOMAIN required, ensure_proxy_network, Traefik-running warning. Docker socket gotcha handled via `group_add` using detected docker GID (`getent group docker`). Guarded dir creation via `sudo install -d -o -g` (never chown -R existing data). Grafana admin creds generated via `openssl rand`, stored in `/srv/grafana/.env` mode 600, reused on re-run. Renders templates via `envsubst`. Idempotent re-run: prompts/skips on existing compose file, `MONITORING_FORCE=true` to force; never `down -v`. Health checks Prometheus and Grafana with bounded timeout. Summary output with access URL, creds location, management commands.
- [x] `templates/monitoring/docker-compose.yml` (new) — Compose v2 (no top-level version, `name: monitoring`). 3 services on shared `monitoring-net`; Grafana also joins external `proxy` network with Traefik labels (router rule Host(${GRAFANA_DOMAIN}), websecure, letsencrypt, port 3000). Prometheus mounts docker.sock:ro + `group_add`. Node Exporter pid:host, rootfs mounts, NOT network_mode host.
- [x] `templates/monitoring/prometheus.yml` (new) — docker_sd_configs over docker.sock; relabel keeps only `prometheus.scrape=true` containers and applies `prometheus.port`.
- [x] `templates/monitoring/grafana-datasource.yml` (new) — Prometheus datasource provider at `http://prometheus:9090`.
- [x] `templates/monitoring/grafana-provisioning.yml` (new) — dashboard provider (type: file, path /var/lib/grafana/dashboards), replaces stock provisioning tree.
- [x] `templates/monitoring/grafana-dashboard.json` (new) — Node Exporter host overview dashboard (CPU, memory, root FS, uptime, network, disk I/O). Valid JSON.
- [x] `machine-config.yml` (edited, gitignored) — added `setup-monitoring` entry, `enabled: false`, GRAFANA_DOMAIN env.
- [x] `machine-config.yml.example` (edited) — added same `setup-monitoring` entry, `enabled: false`.

### Validation
- [x] shellcheck tasks/setup-monitoring.sh: 0 errors (fixed SC2168 `local` outside functions)
- [x] yamllint on all new .yml templates: warnings only (missing `---`, consistent with repo convention), exit 0
- [x] jq empty templates/monitoring/grafana-dashboard.json: valid
- [x] `docker compose config` on rendered compose: valid (verified with temp env file + temp data dir)

### Notes / assumptions
- No ticket file with frontmatter exists in the repo; changes documented in changelog only.
- Traefik integration treated as always-on for Grafana (plan names no explicit flag).
- GRAFANA_DOMAIN is required (no opt-out) per plan.

## 2026-08-02T17:30:20+02:00 - worker (review fixes)

### Changes
- [x] Fixed prometheus.yml port relabel to use canonical __address__ + port label pattern
- [x] Added uid: prometheus to grafana-datasource.yml

### Validation
- [x] jq valid
- [x] yamllint passes
- [x] docker compose config validates

## 2026-08-22T01:20:00+02:00 - worker

### Implemented: NetBird setup task (self-hosted mesh VPN)

- [x] `tasks/setup-netbird.sh` (new, executable) — deploys the NetBird combined server (management + signal + relay + embedded STUN + embedded IdP, `netbirdio/netbird-server:0.77.1`) plus dashboard (`netbirdio/dashboard:v2.91.1`) under `${NETBIRD_HOME}` (default `/srv/netbird`). Sources `lib/helpers.sh` (reuses `run_preflight_checks`, `ensure_proxy_network`, `ufw_firewall_section`, logging). Two modes: direct (default, host ports 8081/8080 + STUN udp/3478 + UFW rules) and traefik (`NETBIRD_TRAEFIK=true`, label-discovered on `${PROXY_NETWORK}`; gRPC router with mandatory `h2c` backend service + backend router for /relay, /ws-proxy/, /api, /oauth2; dashboard catch-all priority 1). Optional profile-gated `netbird-client` routing peer (`NETBIRD_CLIENT_ENABLED=true` + `NETBIRD_SETUP_KEY`) with host IP forwarding. Idempotency: `.env` (generated `openssl rand` authSecret + store encryptionKey, mode 600) created once and never overwritten; compose file + envsubst-rendered `config.yaml` (mode 600) copied/rendered only if missing; no interactive prompts. Optional bootstrap owner via `NETBIRD_ADMIN_EMAIL/PASSWORD`.
- [x] `templates/netbird/docker-compose.traefik.yml` (new) — Traefik-mode compose: canonical six-label pattern (omnigent template + forgejo/openwebui) extended with dual backend services (http + `scheme=h2c`) and dual priority-100 routers; STUN udp published on host; STUN is never proxied.
- [x] `templates/netbird/docker-compose.direct.yml` (new) — direct-mode compose: web ports published, no Traefik labels/network.
- [x] `templates/netbird/config.yaml.template` (new) — NetBird combined-server config (listen :80, exposedAddress, stunPorts, embedded IdP issuer + redirect URIs, sqlite store, owner bootstrap block).
- [x] `machine-config.yml` / `machine-config.yml.example` (edited) — `setup-netbird` entry added after `setup-traefik`, `enabled: false`.
- [x] `README.md` (edited) — `setup-netbird` listed under Remote Access & Desktop.
- [x] `CONTEXT.md` (edited) — `netbird` term added to Services.

### Validation
- [x] `shellcheck tasks/setup-netbird.sh`: 0 findings
- [x] `bash -n tasks/setup-netbird.sh`: OK
- [x] `yamllint templates/netbird/*.yml`: clean
- [x] Direct-mode smoke test: both containers start; OIDC discovery endpoint returns 200; re-run leaves `.env`/`config.yaml`/`docker-compose.yml` byte-identical and preserves the `netbird-data` volume
- [x] Traefik-mode test: `docker compose config` resolves all vars; container labels match plan (3 routers, h2c service, priorities 1/100); container attached to `proxy` network
- [x] Error paths: empty `NETBIRD_DOMAIN` (traefik) and missing `NETBIRD_SETUP_KEY` (client) exit non-zero with clear messages
- [x] `./run-setup.sh status` lists `setup-netbird` (disabled)

## 2026-08-29T16:02:44+02:00 - worker (ticket 01)

### Implemented: split terminal errors from reporting in `lib/helpers.sh`; make `detect_arch` recoverable (ticket `01-lib-helpers-error-semantics`)

- [x] `lib/helpers.sh` — added `err_msg()` (report to stderr, `return 1`, no exit) and `die()` (report + `exit 1`, identical semantics to `error()`), both `declare -F`-guarded like the existing helpers. Added a comment block stating the rule: `error`/`die` terminate — never call them inside a `||`-guarded command substitution; use `err_msg` + `return` in recoverable helpers. `error()` behaviour is unchanged (~300 call sites keep working).
- [x] `lib/helpers.sh` — `detect_arch [fallback]` no longer exits: on an unsupported arch it prints the error to stderr via `err_msg`, prints `[fallback]` first if given, and returns 1, so callers decide. Header comment documents the `set -euo pipefail` assignment-with-return shape (`ARCH="$(detect_arch)" || exit 1`) and warns against `|| <fallback>` guards.
- [x] `tasks/setup-whispering.sh` — removed the silent `ARCH="$(detect_arch || echo amd64)"`. Now: on unsupported arch the task fails loudly, unless the operator sets `WHISPERING_ARCH_FALLBACK=amd64` (then a visible `warn` is printed and amd64 artifacts are used). `--help` gained an "Environment variables" section documenting `WHISPERING_ARCH_FALLBACK`.
- [x] `lib/helpers.sh` — `mktempfile` now auto-removes its files on script exit without breaking caller EXIT traps. Files are recorded in a per-process tracking file (`$TMPDIR/msa-mktempfile-tracker.$$`) and the `_mktemp_cleanup` EXIT trap is *chained* onto any existing caller trap (armed at source time and re-checked on direct non-subshell calls; re-arm is a no-op while the cleanup is already part of the trap, so repeated calls never re-wrap it). Existing `mktemp -t "<name>.XXXXXX"` naming and `tmp.XXXXXX` fallback kept.
- [x] `tasks/setup-llama-swap.sh` — one-line lint fix: `# shellcheck disable=SC2119` + comment at the `detect_arch` call (info-level finding introduced by the new optional `[fallback]` parameter; passing `"$@"` would be semantically wrong there — the task must fail loudly on unsupported arch).
- [x] Anti-pattern audit (step 5 grep for `$(detect_arch|ufw_active|ufw_rule_exists|is_apt_package_installed ... ||`): the only hit was `tasks/setup-whispering.sh:34`, now fixed; grep returns nothing.

### Deviation from the ticket's reference implementation (documented in code)
- The ticket's reference tracked temp files in a shell array and armed the EXIT trap *inside `mktempfile`*. That cannot work for the actual call shape `INSTALL_SCRIPT=$(mktempfile ...)` (setup-zed.sh:110): the command substitution runs in a subshell, so the array update and the trap never reach the parent, and the subshell's own EXIT trap fires at the end of the substitution — deleting the file before the caller has used it (verified empirically: with the reference logic the zed install script is gone right after the assignment, so `curl -o` would recreate it untracked and the leak named in the ticket would remain). Verified bash semantics: `$( )` subshells do not inherit parent self-set EXIT traps; traps set inside `$( )` fire at substitution end with their stdout captured into the variable; `BASH_SUBSHELL` is 0 top-level / ≥1 in `$( )`.
- Therefore: tracking via a per-process tracking *file* (survives the subshell boundary), cleanup trap armed in the parent at source time + on direct (non-subshell) calls, with the ticket's `trap -p` extraction and the documented single-quote limitation of trap chaining.

### Validation
- [x] Ticket verification 1: `detect_arch` on fake `sparc64` — `PASS: parent alive, rc=1` (no exit of the sourcing script)
- [x] Ticket verification 2: `error boom` — rc=1, `UNREACHABLE` not printed (backwards compatible)
- [x] Ticket verification 4: `shellcheck -x lib/helpers.sh tasks/setup-whispering.sh tasks/setup-zed.sh` exit 0; `bash -n` clean on all touched files
- [x] Ticket verification 5: `tasks/setup-llama-swap.sh --help` OK (both `detect_arch` consumers behave)
- [x] Scenario matrix (all pass): zed-style `$( )` call without caller trap → file usable mid-run, removed at exit, tracker file removed; 5-task-script style (caller trap installed after source, no mktempfile use) → caller trap runs, no empty tracker leak; caller trap present at source time → chained, both run, file removed at exit; repeated `mktempfile` calls → trap not re-wrapped; double-sourcing `lib/helpers.sh` → no-op (same tracker path, single trap, function definitions stable)
- [x] whispering on fake `sparc64` host: without env var → `err_msg` + `error "Unsupported host architecture..."`, rc=1 (loud); with `WHISPERING_ARCH_FALLBACK=amd64` → visible `WARN` + continues with amd64
- [x] Regression: `shellcheck -x` on all 5 EXIT-trap task scripts, `run-setup.sh` and all 3 utilities passes with the changed library

### Notes / assumptions
- Ticket verification 3 (synthetic): `source lib; trap '...' EXIT; f=$(mktempfile probe.sh)` — with any design, the caller's plain `trap ... EXIT` installed *after* sourcing replaces the chained trap (EXIT is a single-valued slot and no parent-side hook runs afterwards), so the file leaks in that specific case. No current task script combines that pattern with `mktempfile` usage; the limitation is documented in the `mktempfile` header comment (a future script doing both must include `_mktemp_cleanup` in its own trap). All real call sites behave correctly (see scenario matrix). The reference implementation fails this same test 3 in the other direction (`test -e "$f"` aborts, file deleted at substitution end) and leaves the zed leak unfixed.
- `error()` exit behaviour intentionally unchanged (300-call-site migration is out of scope per the ticket).

## 2026-08-29T17:09:15+02:00 - worker (ticket 02)

### Implemented: harden UFW helpers — anchor rules on direction, fail on unreadable status (ticket `02-lib-ufw-helper-hardening`)

- [x] `lib/helpers.sh` — new `ufw_status_text()`: prints `ufw status` output with a three-valued return (0 = readable active/inactive, 1 = present but unreadable [sudo denied / error], 2 = not installed). Runs `sudo -n ufw status` first (never prompts), falls back to a possibly-interactive `sudo` only when the failure was not a password requirement; success additionally requires a `Status:` line in the output. Result cached in `_UFW_STATUS`/`_UFW_STATUS_RC` for the shell lifetime; cache init guarded so re-sourcing is a no-op and a warm cache survives re-source.
- [x] `lib/helpers.sh` — new `_ufw_invalidate_status_cache()`; called after every successful `ufw allow` (in `ufw_add_rule`) and `ufw delete` (in `ufw_delete_rule`) so readers never see stale state.
- [x] `lib/helpers.sh` — `ufw_active()` now returns 0 = active, 1 = inactive-but-known, 2 = unknown (could not read), built on `ufw_status_text`.
- [x] `lib/helpers.sh` — `ufw_rule_exists <port> [proto] [direction]`: anchored, direction-aware grep (default `IN`), tolerant of the numbered `[  1]` verbose prefix. An `ALLOW OUT` rule can no longer satisfy an inbound lookup; unreadable status returns 1 (absent, not present).
- [x] `lib/helpers.sh` — `ufw_add_rule()`: refuses to assume rules are present when status is unreadable — `err_msg` ×2 naming the remedy (passwordless sudo for ufw / manual `sudo ufw allow`), `return 1`; success message now says "Inbound rule … already exists"; invalidates the cache after a successful allow.
- [x] `lib/helpers.sh` — `ufw_firewall_section()`: unreadable status (`ufw_active` rc 2) is now a hard `error` exit (a service task must not silently skip protection); genuinely absent UFW still only warns (rc 0, unchanged); inactive UFW now only warns and the rules are still added (previously the section skipped entirely).
- [x] `lib/helpers.sh` — `ufw_delete_rule()`: one-line comment recording that only the inbound rule is deleted (outbound rules untouched, deliberately), plus cache invalidation.
- [x] IPv6 note added to the UFW section header (v6 lines render differently; out of scope per ticket).

### Call-site review (per ticket: every direct `ufw_active` use reviewed by hand; no task script needed editing)
- `tasks/setup-traefik.sh:677` `if ufw_available && ufw_active; then` — only direct `ufw_active` consumer. New rc 2 (unreadable) is falsy exactly like the old rc 1, so the skip+warn behaviour is byte-for-byte unchanged; no failure swallowed. Left as-is (it does not call `ufw_firewall_section`; converting it to a hard failure is outside this ticket's scope).
- All other consumers (`setup-netbird.sh` ×2 `ufw_firewall_section`, `setup-omnigent.sh` / `setup-monitoring.sh` / `configure-firewall.sh` `ufw_add_rule`, `setup-opencode-server.sh` ×2 `ufw_rule_exists`+`ufw_add_rule`) are plain statements under `set -euo pipefail`, so the new non-zero returns hard-fail the task loudly instead of being swallowed. **No task script modified.**

### Validation
- [x] Ticket verification (direction mock): `ufw_rule_exists 443 tcp` → `PASS: ALLOW OUT not matched`; `ufw_rule_exists 22 tcp` → `PASS: ALLOW IN matched`
- [x] Ticket verification (password sudo mock): `ufw_firewall_section "probe" 8080 tcp "PROBE"` exits rc=1 with message naming the remedy ("Fix sudo access to ufw (passwordless 'sudo ufw status') and re-run.")
- [x] Ticket verification (counter mock, 3 rules): `status reads: 4` — small constant within the expected 1–4, no per-rule growth (1 in `ufw_active` subshell + 1 per rule after post-allow invalidation)
- [x] `443/tcp ALLOW IN` present → `ufw_add_rule` skips and logs "Inbound rule for 443/tcp already exists, skipping."
- [x] ufw absent → `ufw_firewall_section` warns only, rc 0 (unchanged); `Status: inactive` → warns only and still adds the rule, rc 0
- [x] Direct `ufw_add_rule` with unreadable status under `set -euo pipefail`: both remedy lines printed, rc=1 (err_msg calls are `|| true`-guarded so the first failure cannot swallow the remedy line)
- [x] Numbered verbose format (`[  1] 22/tcp ALLOW IN …`) matches; explicit `OUT` direction works; OUT never satisfies an IN lookup
- [x] Sourcing `lib/helpers.sh` twice is a no-op (all 9 ufw function definitions stable, warm cache preserved); all `declare -F` guards preserved
- [x] `shellcheck -x lib/helpers.sh` + `bash -n` clean; regression sweep `shellcheck -x` on all 6 ufw-consuming task scripts passes
- [x] `./run-setup.sh status` smoke test rc=0 (33 scripts listed)
- [x] Real-environment check on this dev box (ufw present, password sudo): `ufw_status_text` returns rc=1 quickly — no prompt, no hang (the `-n`-first design)
- [x] Ticket-01 regression: `detect_arch`/`err_msg`/`mktempfile` behaviour unchanged in the same file

### Notes / assumptions
- `$(ufw_status_text)` subshell reads (from `ufw_active`/`ufw_rule_exists`) cannot populate the parent cache — command substitutions run in subshells (same boundary as ticket 01). The design keeps that to at most one redundant read per section: the first parent-side `ufw_status_text` call inside `ufw_add_rule` (run in the current shell, not `$( )`) populates the parent cache, which the subshell then inherits; the counter mock proves total reads stay a small constant.
- Wording deviation: the section's hard-failure message is self-contained ("Fix sudo access to ufw (passwordless 'sudo ufw status') and re-run.") instead of the ticket's "(see message above)", because nothing prints a preceding message in that flow — the acceptance criterion ("message naming the remedy") is met by the message itself.
- `ufw_enable`/`ufw_show_status` intentionally untouched (not in the ticket's implementation list); `ufw_enable` still reads status directly, which stays correct because the cache is invalidated after the preceding `ufw allow` calls in `configure-firewall.sh`.
- `ufw_delete_rule` keeps its `|| true` (never fails) semantics — only the comment + cache invalidation were added, per the ticket's step 6 scope.
- New `ufw_status_text` stderr-file handling uses a bare `mktemp` (consistent with the repo's existing bare-mktemp sites; converting them is out of scope per ticket 01).

## 2026-08-29T18:18:39+02:00 - worker (ticket 03)

### Implemented:
- [x] `tasks/setup-fail2ban.sh` — render fix (root cause H-1): envsubst now runs as the **unprivileged** user against an `mktemp` file (all `FAIL2BAN_*` + `GENERATED_DATE` are exported; envsubst reads the environment, and `sudo`'s default `env_reset` would have stripped them), then `sudo install -m 644 -o root -g root` moves it into `/etc/fail2ban/jail.local` atomically — same pattern as `setup-traefik.sh`. `sudo cat | sudo envsubst | sudo tee` is gone; the now-unneeded `# shellcheck disable=SC2034` above `GENERATED_DATE` is removed (it is used via the envsubst list).
- [x] `tasks/setup-fail2ban.sh` — blank-render guard: a rendered line `port = ,` / `maxretry = ` / `bantime = ` / `findtime = ` in the temp file aborts (`error`) **before** anything is written to `${JAIL_LOCAL}`.
- [x] `templates/fail2ban/jail.local` + `tasks/setup-fail2ban.sh` — journal backend: new `FAIL2BAN_BACKEND` (default `systemd`) and `FAIL2BAN_LOGPATH` (default `/dev/log`) env vars, both in the header comment and `--help`; all three jails get `backend = ${FAIL2BAN_BACKEND}` / `logpath = ${FAIL2BAN_LOGPATH}` (was hardcoded `/var/log/auth.log`, which only exists with rsyslog — on a default Ubuntu install the jails pointed at a file that never receives auth events). Template comment explains the journald reasoning. `backend=file` requires rsyslog (installed if missing) and a readable `${FAIL2BAN_LOGPATH}` (hard error otherwise); `backend=systemd` gets a non-fatal `journalctl -n1 -u ssh` sanity warning before rendering.
- [x] `tasks/setup-fail2ban.sh` — config validation before rendering: `FAIL2BAN_MAXRETRY`/`BANTIME`/`FINDTIME` must be non-negative integers, `FAIL2BAN_SSHD_PORT` must be a port 1–65535 (fail fast instead of writing a config fail2ban rejects).
- [x] `tasks/setup-fail2ban.sh` — upstream repo is best-effort: GPG-key fetch or `apt-get update` failure → `warn "Using fail2ban from the Ubuntu archive (upstream repo unreachable)."` and the sources-list entry is removed; a failed fetch can no longer leave `/etc/apt/sources.list.d/fail2ban.list` behind (previously: key fetch failed → empty keyring → `apt update` broken forever).
- [x] `tasks/setup-fail2ban.sh` — verification is fatal: `error` if the rendered file lacks `port = ${FAIL2BAN_SSHD_PORT},ssh` or contains any blank value; `fail2ban-client status sshd` gets a 6×2 s retry window, then on failure the script dumps `fail2ban-client status` + `tail -n 40 /var/log/fail2ban.log` and exits non-zero (previously: `[WARN] Could not verify jail status` + exit 0). Summary block now prints the effective backend/logpath.

### Validation
- [x] Ticket verification (render-only proof): rendered `jail.local` contains `port = 2200,ssh`, `maxretry = 7`, `bantime = 1200`, `findtime = 300` (and the new `backend = systemd` / `logpath = /dev/log` lines); empty-value grep count is 0
- [x] Ticket verification (INI): `python3 configparser` parses the rendered template cleanly — sections `sshd`, `sshd-ddos`, `sshd-aggressive`
- [x] Empty-value guard (extracted real code path, `FAIL2BAN_MAXRETRY=""`): exits rc=1 with "Rendered jail.local contains empty values — template substitution failed." and the `install` step is never reached; with all vars set the install step does run
- [x] Fatal verification (extracted real code path): stub `fail2ban-client status sshd` always failing → rc=1 ("fail2ban sshd jail is not active — check backend …"); succeeding on the 2nd attempt → "SSHD jail is active", rc=0
- [x] Repo-fallback (extracted real code path, op-logging stubs): key fetch fails → no sources list written, warn, continue; key OK + `apt-get update` fails → sources list written then removed, warn, continue
- [x] `shellcheck tasks/setup-fail2ban.sh` clean (SC2016 suppressed per-line with the repo's standard "envsubst expects the literal variable list" comment; SC2015 avoided by using an explicit `if` for the port range check), `bash -n` clean
- [x] `tests/run-vm-tests.sh --scripts setup-fail2ban` → **PASS (3/3)**: precheck + integration (30 s) + idempotency (1 s) on a fresh Ubuntu 26.04 VM (`SSHD_PORT=22` per test config); integration log line 439 and idempotency log line 20 both contain "SSHD jail is active"; idempotency phase took the "already installed" path (render → reload, no reinstall/restart, bans preserved); report: `tests/reports/vmtest-20260829-181057/report.md`

### Notes / assumptions
- **VM finding (recorded per ticket instruction):** the live VM run could not reach the upstream repo — `repo.fail2ban.org` does not resolve from this network (DNS failure, confirmed from the dev host too). The run therefore exercised the new fallback path end-to-end exactly as designed: key-fetch fail → no sources list → Ubuntu-archive fail2ban 1.1.0 → `backend = systemd` jail came up active (so Ubuntu's fail2ban 1.1.0 does support the journald backend — the ticket's default is right). When the network can resolve the domain, the upstream path runs instead; both branches are stub-tested.
- The ticket's port check snippet used `A && B || C`; shellcheck SC2015 flags that idiom, so it was rewritten as the equivalent explicit `if ! … || …; then error; fi` (same semantics, verified: `FAIL2BAN_SSHD_PORT=abc` and `=70000` both fail, `=2224` passes).
- `FAIL2BAN_BACKEND=file` + missing log file is a hard error (ticket's exact message). `backend=systemd` + empty journal is only a warning (the jail may still work; ssh unit entries exist on the test VM — no warning was printed there).
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01/02 were closed.
- VM test artifacts (`tests/reports/vmtest-20260829-181057/`) are gitignored like `.tickets/` — on disk only.

## 2026-08-30T03:10:00+02:00 - worker (ticket 04)

### Implemented: close both remote-lockout paths — sshd drop-in + key check, UFW pre-flight + self-rollback (ticket `04-ssh-firewall-lockout-guards`)

- [x] `tasks/setup-sshd.sh` — rewritten around a managed drop-in `/etc/ssh/sshd_config.d/99-machine-setup.conf` (the main `sshd_config` is never modified; the old first-match-wins append loop and `SSHD_CONFIG_LINES` are gone):
  - **A1 key check first**: `PasswordAuthentication no` is only written when a usable public key (ssh-rsa/ed25519, ecdsa-sha2-nistp*, sk-ssh-/sk-ecdsa-ssh-ed25519, optional `@host` restriction) exists in `~/.ssh/authorized_keys`; otherwise `SSHD_ALLOW_PASSWORDAUTH=yes` keeps password auth on (warn) or the script exits non-zero with the remedy. `~/.ssh` is prepared 700/600 before anything else.
  - **A2 drop-in + port move safety**: new port plus `SSHD_LEGACY_PORT` or the live session port (from `SSH_CONNECTION`) all in one `Port` set, so the live session survives the restart. Idempotent render via temp + `sudo cmp -s`: an unchanged drop-in is logged as "unchanged" and **skips the restart**; otherwise `sudo install -m 600 -o root -g root`.
  - **A3 UFW before restart**: `ufw_add_rule <new port>` with no `|| true` (ticket 02: unreadable status fails loudly; inactive UFW only warns).
  - **A4 validate → restart with revert**: `sudo sshd -t` on the whole tree; on failure the drop-in is removed, the config re-validated (a broken pre-existing config is not blamed on this script), and sshd is NOT restarted.
  - **A5 prove the effective config**: `sudo sshd -T` after the restart — fatal if `PasswordAuthentication no` is not actually effective (an earlier Include wins) or if the target port is not listening; the "keep this session open, test in a second terminal" warning is printed BEFORE the restart.
  - **A6**: header + `--help` document `SSHD_ALLOW_PASSWORDAUTH`, `SSHD_LEGACY_PORT`; `SSHD_PORT`/`SSHD_LEGACY_PORT` validated 1–65535 up front (fail fast before any sudo).
  - **NEW (found while VM-testing, not in the ticket)**: socket-activated sshd handling. Ubuntu 24.04+/26.04 (the harness target `resolute`) ships sshd socket-activated (`ssh.socket` owns the port), and a socket-activated sshd does **not** bind extra `Port` lines — a port move silently kept listening only on the socket's port (the A5 check caught this on a real VM: rc=1, drop-in reverted path available, no false success). The script now keeps the socket only when it serves exactly the single configured port; otherwise it disables it (`systemctl disable --now ssh.socket`) so the service binds all configured ports. Socket port set read via `systemctl show -p Listen --value ssh.socket` (`ListenStream` is not exposed on systemd 259).
- [x] `tasks/configure-firewall.sh` — lockout guards (Parts B1–B4):
  - **B1 pre-flight**: session port from `SSH_CONNECTION` (fallback `SSH_CLIENT`); refuses (non-zero, naming the remedy) to enable UFW while `SSHD_PORT` ≠ live session port — override `FIREWALL_ALLOW_SSH_MISMATCH=true`; warns about every sshd listen port (`sudo ss -Htlnp`) that the new rule set would NOT allow (the "sshd on 22, you allow 2224" case even when the session matches); local/console runs skip the check with a visible info line.
  - **B2 self-rollback**: a first enable from a remote session arms the transient unit `machine-setup-ufw-rollback` (`systemd-run --on-active=${FIREWALL_ROLLBACK_MINUTES:-10}min /usr/sbin/ufw disable`); a non-first enable never re-arms; the timer is deliberately NOT cancelled by the script (confirmation must come from a NEW connection) — stated in the output and README; `FIREWALL_ARM_ROLLBACK=false` is the documented headless-CI opt-out (warns on first remote enable); manual recovery hints (`sudo ufw allow <port>/tcp`, `sudo ufw disable`) + console/IPMI reminder printed.
  - **B3 (L-8) no speculative rules**: the `LM_STUDIO`/`OPENCODE` `ufw_add_rule` calls are gone (each service script opens its own port); new `FIREWALL_EXTRA_PORTS="1234/tcp,4096/tcp"` operator list (bare port = tcp; protocol validated tcp|udp; each entry `validate_port`ed). `LM_STUDIO_PORT`/`OPENCODE_PORT`/`OPENWEBUI_PORT`/`KUBERNETES_API_PORT`/`GNOME_REMOTE_PORT` are displayed only — all documented in header + `--help`.
  - **B4**: unreachable `exit 1` after `error` in the local `validate_port` removed.
- [x] `lib/helpers.sh` — `ufw_status_text` now reads `ufw status verbose`. Required for these guards: ufw ≥ 0.36 (this dev box: 0.36.2) omits the direction column in plain status output (`22/tcp ALLOW Anywhere`), which silently breaks the direction-anchored `ufw_rule_exists` from ticket 02 (always "absent" → re-adds rules / can't prove them). Verified on the VM: `ufw status verbose` shows `22/tcp ALLOW IN Anywhere` and the "already exists, skipping" path works.
- [x] `machine-config.yml.example` — `setup-sshd` moved BEFORE `configure-firewall` with a comment block stating the required order and why (sshd moves the port → firewall allows it); both stay `enabled: false`.
- [x] `tests/machine-config.test.yml` — harness keeps `SSHD_PORT: "22"` for configure-firewall/setup-sshd/setup-fail2ban, adds `FIREWALL_ARM_ROLLBACK: "false"` (harness must not arm a rollback timer) and `SSHD_ALLOW_PASSWORDAUTH: "yes"` (no operator key in the VM); lock-out-avoidance comment extended.
- [x] `README.md` — orchestrator section: setup-sshd-before-configure-firewall ordering note; new "SSH / firewall lock-out protection (escape hatches)" subsection documenting the three env escape hatches, the `machine-setup-ufw-rollback` unit name, and how to stop the timer; `setup-sshd.sh` / `configure-firewall.sh` entries rewritten (drop-in, guards, socket handling, new env vars).

### Deviations from the ticket's reference implementation (documented in code)
- **Timer cancel command**: the ticket's `systemctl cancel <unit>` only accepts numeric job IDs (verified on the VM: `systemctl cancel machine-setup-ufw-rollback` → "Failed to parse job id"). The working operator remedy for a transient on-active timer is `sudo systemctl stop machine-setup-ufw-rollback.timer` — script warning, `--help` and README use that.
- **Socket-activation handling** (above) is a real bug the reference implementation would hit on the target distro: without it, the ticket's own acceptance criterion "moving from 22 → 2224 leaves both ports listening" fails on Ubuntu 26.04.
- **A5 `sshd -T` read is guarded** (`if ! _effective="$(...)"; then error …; fi`): unguarded, a failing `sshd -T` (stderr redirected) would kill the script silently under `set -euo pipefail` — against the ticket's "fail loudly with the remedy" goal.
- The A1 key regex matches real key types (`ecdsa-sha2-nistp[0-9]+`, `sk-ssh-ed25519`, `sk-ecdsa-ssh-ed25519`) instead of the broader `ecdsa-[a-z0-9-]+`, and tolerates an optional `@hostname` restriction suffix.
- The `FIREWALL_EXTRA_PORTS` parser additionally validates the protocol (tcp|udp) with a named error.

### Validation
- [x] `shellcheck -x tasks/setup-sshd.sh tasks/configure-firewall.sh lib/helpers.sh` exit 0; `bash -n` clean on both scripts
- [x] `yamllint machine-config.yml.example tests/machine-config.test.yml` exit 0 (only the two pre-existing `comments-indentation` warnings, present in HEAD too)
- [x] `./run-setup.sh -c machine-config.yml.example status` rc=0 (33 scripts); `yq` order check: setup-sshd (3rd) before configure-firewall (4th)
- [x] `--help` of both scripts reviewed (all new env vars documented)
- [x] Stub-based logic tests (69 assertions; sudo/ufw/sshd/ss/systemctl/systemd-run faked, no root): pre-flight refusal names the override + no state change; override proceeds and arms the timer exactly once with the right args; non-first enable does not re-arm; extra-listen-port warn; EXTRA_PORTS parsing (tcp/udp/default) + invalid proto/port rejection; console run skips the session check and arms nothing; empty-key refusal (rc≠0, no drop-in, no restart, no UFW rule); allow-passwordauth path; key → `PasswordAuthentication no`; effective-config mismatch fatal; `sshd -T` unreadable → loud error; `sshd -t` invalid → drop-in reverted + no restart; legacy-port both-ports + warning; socket move → socket disabled; socket same-port → socket kept. All pass.
- [x] Fresh full VM suite (`tests/run-vm-tests.sh --scripts setup-docker,setup-sshd,configure-firewall,setup-fail2ban --keep-vm`, Ubuntu 26.04 `resolute`): **8/9 PASS** — precheck + integration + idempotency of configure-firewall, setup-sshd, setup-fail2ban all green; harness (port 22) never cut off even though UFW went active mid-run. Only failure: `setup-docker [integration]` — the pre-existing `usermod`→`docker run` group-membership flake on the harness's long-lived SSH session (same signature in the 8/27 TIMEOUT and 8/29 permission-denied runs; idempotency phase passes; setup-docker.sh untouched by this ticket)
- [x] On-VM acceptance checks (first on the previous attempt's kept VM, then re-verified on the fresh suite VM):
  - AC1: empty `authorized_keys` + no `SSHD_ALLOW_PASSWORDAUTH` → rc=1 refusal message, drop-in md5 unchanged, `ActiveEnterTimestamp` unchanged, 0 "Restarting SSH service" occurrences
  - main `/etc/ssh/sshd_config` stock (only commented `#Port`/`#PasswordAuthentication` lines) — never written
  - effective config after run: `port 22`, `passwordauthentication no`, `pubkeyauthentication yes` (harness key injected); drop-in `-rw------- root:root`
  - pre-flight: session 22 + default `SSHD_PORT=2224` → rc=1 naming `FIREWALL_ALLOW_SSH_MISMATCH`; with the override → rc=0 and rule added
  - first enable over SSH armed `machine-setup-ufw-rollback.timer` (`systemctl list-timers` showed it, ~10 min); non-first enable did not re-arm; operator stop of the timer verified
  - port move 22→2224 on the fresh socket-activated VM: rc=0, legacy/live-port warning, drop-in `Port 2224` + `Port 22`, **UFW 2224 rule added before the restart**, socket disabled, both ports listening (v4+v6), and `ssh -p 2224` from the host in a second shell → "key-auth works on 2224" while the port-22 session stayed connected
  - same-port run on a socket-activated VM → "keeping socket activation", socket left active
  - idempotent re-run → "unchanged — sshd will NOT be restarted", 0 restart occurrences
  - `sudo ufw status verbose`: only the SSH port(s) allowed — no speculative `LM_STUDIO`/`OPENCODE` rules

### Notes / assumptions
- The VM harness injects `VM_SSH_KEY`, so on the test VMs the key check passes and the drop-in gets `PasswordAuthentication no` (the harness reconnects with the same key — verified: every post-setup-sshd SSH call in the suite worked). `SSHD_ALLOW_PASSWORDAUTH=yes` in the test config is the belt-and-braces for a missing key, per the ticket.
- Disabling `ssh.socket` during a port move briefly un-listens the socket's port (milliseconds, until the service restart); established sessions survive (both are outside the restarted unit), and the new port's UFW rule exists before the restart, so no reconnect path is cut.
- `systemd-run` unit name collisions on a re-arm are impossible by design (non-first enables skip arming); if the timer unit somehow existed already, `systemd-run` fails and the script warns ("verify access before leaving this session") instead of failing the run.
- The `setup-docker` integration flake is tracked here as a known environmental artifact, not fixed in this ticket (out of scope).
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–03 were closed.

## 2026-08-30T05:33:34+02:00 - worker (ticket 05)

### Implemented: Planka secret lifecycle — `.env` (600) with reuse-first re-runs, secrets out of compose; Nextcloud read-before-write (ticket `05-planka-secrets-env-file`)

- [x] `lib/helpers.sh` — new shared secret env-file primitives, both `declare -F`-guarded: `env_file_get <file> <KEY>` (prints the value, last occurrence wins, read literally, returns 1 on missing file) and `env_file_write <file>` (stdin installed with mode 600, mktemp + install, owner = invoking user with root fallback). Section header documents the repo secret pattern and the "never `source` an env file" rule.
- [x] `tasks/setup-planka.sh` — Planka now implements the repo secret pattern (both halves H-4 was missing):
  - **Reuse-first secret block** (before the existing-stack check, so reuse/drift-check run even when the script exits early): reads `SECRET_KEY`/`POSTGRES_PASSWORD` from `${PLANKA_HOME}/.env` via `env_file_get`, generates only what is missing (`openssl rand -hex 64` / `-hex 24`).
  - **The "empty = trust auth" dev default is gone**: a `POSTGRES_PASSWORD` is now always stored and `PG_AUTH_METHOD=md5` always set (safe for existing trust-mode installs — trust accepts any password — per the ticket's recorded decision). Noted in `--help` and header.
  - **Drift guard (review fix 3)**: if `POSTGRES_PASSWORD` was supplied via the environment *and* differs from the stored value *and* `${PLANKA_HOME}/postgres` is non-empty → non-zero exit with an `ALTER USER` instruction instead of a silently broken stack. `POSTGRES_PASSWORD_SUPPLIED` is captured before any `.env` reuse.
  - **`.env` write (mode 600)**: `printf`-built (no heredoc), back up to `.env.bak` only on actual content change (`cmp -s`), installed via `sudo install -m 600 -o "$(id -un)" -g "$(id -gn)"`. `DATABASE_URL` is derived once and lives only in the `.env`.
  - **Compose file holds no secret values**: `envsubst` lists reduced to layout values only (`PLANKA_IMAGE`, `CONTAINER_NAME`, `PLANKA_HOME`, `BASE_URL`, `HTTP_PORT`, `_planka_lan_suffix`, `PROXY_NETWORK`, `PLANKA_DOMAIN`, `POSTGRES_DB`, `POSTGRES_USER`); `SECRET_KEY`/`POSTGRES_PASSWORD`/`DATABASE_URL`/`PG_AUTH_METHOD`/`ADMIN_EMAIL` are no longer substituted and stay `${VAR}`-literal, resolved at runtime from the `.env`.
  - **Every compose invocation carries `--env-file "$ENV_FILE"`** (14/14 lines: teardown `down`, `pull`, `up -d`, admin `run`, and all warn/summary hint strings — verified by grep).
- [x] `templates/planka/docker-compose*.yml` (4 files) — all four variants now carry the full postgres block (`POSTGRES_DB`/`POSTGRES_USER`/`POSTGRES_HOST_AUTH_METHOD`/`POSTGRES_PASSWORD`, all `${...}`-literal). The `.password` variants are now content-identical to the base ones and are **not** deleted (ticket 19 consolidates); they carry a `# NOTE: SUPERSEDED … ticket 19` header. Selection logic left as-is (always picks `.password` now that a password is always set).
- [x] `tasks/setup-nextcloud.sh` — read-before-write (Part B of H-4):
  - The four `VAR="${VAR:-$(_gen_password)}"` lines are replaced by reuse-first `_env_reuse` (explicit env wins → value from the existing `${NEXTCLOUD_HOME}/.env` → fresh `openssl rand`), applied to `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `POSTGRES_PASSWORD`, `NEXTCLOUD_ADMIN_PASSWORD`. The root-owned `.env` is read once via `sudo cat` and parsed with plain `grep -m1`/`cut` (never sourced) — the ticket's "second form", since this script only conditionally sources `lib/helpers.sh`.
  - `.env` write rewritten: complete content built in a `mktemp` with `printf`, `sudo cmp -s` against the existing file, `.env.bak` only on actual content change (a no-op re-run no longer clobbers a good backup), atomic `sudo install -m 600`.
  - `--help` + header updated for the four variables: "auto-generated on first run, reused from <path>/.env on re-runs; set explicitly to override".
- [x] `AGENTS.md` — new **bash Script Specifications → Secrets and templating** section with the ticket's four-bullet rule (secrets never substituted / layout values may be envsubsted / secrets read back before regeneration / render unprivileged into mktemp + `sudo install`, never `sudo envsubst`) plus a pointer to the new helpers.
- [x] `specification/project/conventions.md` — new **Secrets and templating** section cross-referencing the rule and pointing to `AGENTS.md` and `lib/helpers.sh`.

### Deviations from the ticket's reference implementation (documented in code + ticket file)
- **Planka `.env` owned by the invoking user, mode 600** (not `root:root`, per the ticket's anticipated fallback): `docker compose --env-file` runs as the invoking user and cannot read a root-owned 600 file — the reference's ownership would fail every compose call on a uid-1000 install.
- **No `# Generated:` timestamp line in either `.env`**: the ticket's own acceptance criterion (sha256-identical `.env` across re-runs) is impossible with a per-run timestamp; the backup-on-change `cmp` relies on deterministic content. Nextcloud's first new-script run against an old `.env` (which has the line) does a one-time backup + rewrite, then is stable.
- **Planka writes the `.env` before the existing-stack check** (with a `sudo mkdir -p` guard): required so the teardown `down` can also carry `--env-file` — on a pre-ticket install no `.env` exists yet at that point and `--env-file <missing>` is a hard error. Side effect: pre-ticket installs gain their `.env` even on a run that then exits at the stack check (safe: trust-mode clusters accept any password).
- **Drift-guard condition fixed**: the reference's `[[ -n "${POSTGRES_PASSWORD_SUPPLIED:-}" ]]` is always true once the variable is pre-initialised to `0` ("0" is non-empty) — verified live (no-supply re-run against a populated cluster was refused). Now `[[ "${POSTGRES_PASSWORD_SUPPLIED}" == "1" ]]`.
- **Drift error uses the static container name** (`${CONTAINER_NAME}-postgres`) instead of a live `docker compose ps -q` lookup embedded in the error text (the stack may be down there).
- **Nextcloud: `COLOURS & HELPERS` + `USAGE`/arg-parsing moved above `CONFIGURATION`**: with the ticket's placement, `--help` on an installed machine ran `sudo cat` before argument parsing and exited non-zero without printing help when sudo needs a password/TTY (verified live). The reuse-first block itself is unchanged; help text uses `${NEXTCLOUD_HOME:-/srv/nextcloud}` since the var is unset that early.

### Validation
- [x] `shellcheck lib/helpers.sh tasks/setup-planka.sh tasks/setup-nextcloud.sh` exit 0; `bash -n` clean on all three
- [x] `yamllint -c templates/.yamllint templates/planka/` exit 0 (only the pre-existing `document-start` warnings, repo convention for templates)
- [x] `env_file_get` unit tests: basic/last-occurrence/`=`-in-value/absent-key/missing-file (rc 1)/whitespace-prefixed — all pass; `env_file_write`: mode 600, owner = invoking user, content intact
- [x] Planka two-phase stub run (docker/curl/sudo stubbed, `PLANKA_HOME=/tmp/planka-home`):
  - fresh run → `.env` mode 600 with all six keys; rendered compose: `SECRET_KEY`/`POSTGRES_PASSWORD`/`DATABASE_URL` occur **only** as `${VAR}` literals, zero leaked values (direct mode and Traefik mode both verified; Traefik layout values `Host(planka.test)`/`network=proxy` substituted correctly)
  - re-run (`--interactive`, answer y) → `sha256sum` of `.env` **identical** before/after, no `.env.bak` created, reaches "Planka is up and responding!", rc=0
  - deliberate `POSTGRES_PASSWORD=other` + populated `postgres/` dir → **rc=1** with the `ALTER USER` instruction, `.env` not touched, failure happens before the write step
  - no-supply re-run against a populated cluster → no false drift positive (this is the case that exposed the reference's `-n`/`0` guard bug)
  - pre-ticket install (compose exists, no `.env`) → `.env` created before teardown, full run rc=0, subsequent re-run stable
  - `grep -n 'docker compose' tasks/setup-planka.sh` → all 14 lines carry `--env-file`
- [x] Nextcloud stub runs (`NEXTCLOUD_HOME=/tmp/nc-home`, mariadb + postgres paths):
  - fresh → `.env` mode 600, compose contains only `${VAR}` literals (2× `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}` in the postgres variant)
  - no-op re-run → `.env` byte-identical, **no `.env.bak`**, rc=0
  - explicit `NEXTCLOUD_ADMIN_PASSWORD` override → override wins, `.env.bak` created holding the pre-change content
  - no-op after the change → `.env` and `.env.bak` both unchanged
- [x] `--help` of both scripts exits 0 and describes reuse behaviour + new defaults; Nextcloud `--help` verified in a non-TTY with a real root-owned `/srv/nextcloud/.env` present (no sudo involvement, rc=0 — the regression the restructure fixes)
- [x] Ticket file `.tickets/improvements-2/05-*.md` updated with an "Implementation notes (worker)" section recording the deviations
- [x] Two-phase *live* VM run (`tests/run-vm-tests.sh --scripts setup-docker,setup-traefik,setup-planka --keep-vm`): **not executed** — Planka/Nextcloud are not enabled in `tests/machine-config.test.yml` and standing up a fresh VM for this ticket was out of capacity for this pass; the stub-based two-phase runs above cover the same code paths. Flagged for the branch's final validation.

### Notes / assumptions
- The duplicate `success "Directories ready."` print in `tasks/setup-planka.sh` (pre-existing) was left untouched per surgical-change discipline — candidate for a trivial follow-up.
- The dev box has an actual pre-ticket Planka install at `/srv/planka` (trust-mode, Aug 23). One exploratory test run initially wrote its `.env` there by accident (a test-harness mistake, not a script bug); the file was removed and `/srv/planka` verified back to its exact pre-test state. Its old world-readable compose (inlined `SECRET_KEY`/`DATABASE_URL`) is replaced by the new script on the next real run — that is the ticket's migration path.
- `env_file_get` on an existing-but-unreadable `.env` would yield empty values (sed failure swallowed by the pipeline) → regeneration. Unreachable in the supported cases (the file is always owned by the invoking user / root-readable), accepted as per the ticket's reference behaviour.
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–04 were closed.

## 2026-08-30T06:18:36+02:00 - worker (ticket 06)

### Implemented: Open WebUI secret lifecycle — `WEBUI_SECRET_KEY` out of `docker-compose.yml`, no rotation on re-run, contradictory docs fixed (ticket `06-openwebui-secret-lifecycle`)

- [x] `tasks/setup-openwebui.sh` — reuse-first key block: before generation, `WEBUI_SECRET_KEY` is read from `${PROJECT_DIR}/.env` via `env_file_get` (ticket 05 helper) when the env var is unset; a key is generated only on a genuine first run or when the operator sets it explicitly. `ENV_FILE=` assignment moved up, duplicate deleted.
- [x] `tasks/setup-openwebui.sh` — `lib/helpers.sh` now sourced unconditionally (previously only inside the Traefik pre-flight) so `env_file_get` is available; sourced after this script's colour/logging definitions so those are kept (lib definitions are `declare -F`-guarded).
- [x] `tasks/setup-openwebui.sh` — `_generate_env_file` renders to `mktemp` and creates `.env.bak` ONLY on actual content change (`cmp -s`); a no-op re-run logs ".env unchanged" and no longer clobbers a good `.env.bak`; mode 600 kept. The `sudo cp` is gone (project dir is user-owned; the ticket's reference).
- [x] `tasks/setup-openwebui.sh` — `WEBUI_SECRET_KEY` removed from the compose `export`/`envsubst` lists, so `docker-compose.yml` carries only the literal `${WEBUI_SECRET_KEY}` placeholder; Compose resolves it from the project `.env` at runtime.
- [x] `tasks/setup-openwebui.sh` — `docker compose pull` / `up -d` now carry explicit `--env-file "$ENV_FILE"`; the summary "Useful commands" block shows the explicit `--env-file` form (down/restart/logs + an `up -d` alternative next to `./start_openwebui.sh`), consistent with the ticket-05 Planka summary convention.
- [x] `tasks/setup-openwebui.sh` — secret out of the run log: the generation success message no longer prints the first 8 characters of the key (only that a key was generated).
- [x] `templates/openwebui/docker-compose.direct.yml` + `docker-compose.traefik.yml` — header comment now states `WEBUI_SECRET_KEY` is resolved at runtime from `${PROJECT_DIR}/.env` (mode 600) and intentionally left as a literal `${VAR}` token; the inline env-line comment fixed to match ("resolved from the project .env at runtime").
- [x] `tasks/setup-openwebui.sh` — summary/Note/Security-Notice lines now state the real paths and that the compose file carries only a placeholder (the "not docker-compose.yml" statements are now verifiably true); the "First-time setup" line says the key is generated on first run and reused on re-runs.
- [x] `tasks/setup-openwebui.sh` — `--help` + header comment document the reuse behaviour for `WEBUI_SECRET_KEY` (generated on first run, stored in `.env` mode 600, reused on re-runs — never rotated; explicit env wins).
- [x] `README.md` — Open WebUI entry updated (env-var semantics + Features bullet) plus the ticket's upgrade note: pre-change installs that carried the key in `docker-compose.yml` get a fresh key on first run of the updated script (sessions invalidated, data preserved).

### Validation
- [x] `shellcheck tasks/setup-openwebui.sh` exit 0; `bash -n` clean
- [x] `yamllint -c templates/.yamllint templates/openwebui/` — only the pre-existing `document-start` warnings (repo convention for templates)
- [x] Ticket render-level proof: rendered direct + traefik compose both contain `- WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}` literal; `grep -c '[0-9a-f]\{32\}'` → 0 on both
- [x] Real-docker `docker compose config` on the rendered file: with `.env` present → exactly one `WEBUI_SECRET_KEY: <64-hex>`; without `.env` → `WEBUI_SECRET_KEY: ""` (no 32-hex secret leaks)
- [x] Stub-based two-phase runs (docker/curl/ss stubbed, `PROJECT_DIR=/tmp/…`; dev-box `/srv/openwebui` untouched):
  - fresh run → `.env` mode 600 with 64-hex key; compose holds only the literal placeholder; the key **and its first 8 chars appear nowhere** in the run log
  - no-op re-run (`--interactive`, y) → `.env` `sha256` **identical**, **no `.env.bak` created**, "Reusing WEBUI_SECRET_KEY …" + ".env unchanged" logged, rc=0
  - explicit `WEBUI_SECRET_KEY` override → wins over the persisted value, written to `.env`, `.env.bak` holds the previous key (both mode 600), override value absent from the log
  - edge case: pre-existing `.env` with **no** key → fresh key generated (the `[[ ]] && info` reuse guard does not trip `set -euo pipefail`), old content backed up
- [x] `--help` exits 0 and documents the reuse behaviour (the `${PROJECT_DIR}` in the help text expands to the effective default)

### Notes / assumptions
- The ticket's reference line `info "Using WEBUI_SECRET_KEY from environment variable."` is kept verbatim; on a `.env`-reuse run the immediately preceding "Reusing WEBUI_SECRET_KEY from …" line is the accurate one, so provenance is explicit either way.
- `templates/openwebui/start_openwebui.sh` intentionally untouched (its SC2046/SC2164 findings belong to ticket `20-lint-gate-and-ci.md`, per the ticket).
- The non-`--interactive` existing-stack refusal (`:222-243`) is out of scope (ticket `12-existing-stack-rerun-policy.md`); image pinning likewise (ticket `17-supply-chain-pinning.md`).
- Live VM run (`tests/run-vm-tests.sh --scripts setup-docker,setup-traefik,setup-openwebui --keep-vm`) not executed in this pass (capacity); the stub-based two-phase runs cover the same code paths and the render-level + real-`docker compose config` proofs cover the template side. Flagged for the branch's final validation, same as ticket 05.
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–05 were closed.

## 2026-08-30T08:40:00+02:00 - worker (ticket 07)

### Implemented: drop `privileged` from the traefik socket-proxy templates, pin the image to tag + digest, prove routing on a VM (ticket `07-socket-proxy-drop-privileged`)

- [x] `templates/traefik/docker-compose.socket.{dash,plain}.{dns,nodns}.yml` (4 files) — `socket-proxy` block rewritten per the ticket: `privileged: true` gone; now `security_opt: no-new-privileges:true`, `cap_drop: [ALL]`, `tmpfs: /tmp`, image `${SOCKET_PROXY_IMAGE}`; the `CONTAINERS/NETWORKS/EVENTS/PING/VERSION` allow-list, the `:ro` socket mount, `socket-net` and the healthcheck are untouched. Header comment explains the hardening and why `read_only` is NOT set (see deviation below). Comment wording deliberately avoids the literal `privileged` token so the ticket's own greps stay green (the ticket's suggested comment contained `privileged: true` and would have failed its own acceptance grep).
- [x] `tasks/setup-traefik.sh` — new `SOCKET_PROXY_IMAGE` env var with pinned default `ghcr.io/tecnativa/docker-socket-proxy:v0.5.0@sha256:1f5038b54f06c3e18422902cf00ba21803d1c97805aae032e5e6673d532d3459` (`latest` == `v0.5.0` at pin time; multi-arch index digest so every platform resolves), with the ticket's "update deliberately" comment; exported and added to the compose envsubst list so all four socket variants render the pinned value; documented in `--help` and the header comment. `nosocket` variants untouched (verified: empty diff).
- [x] `tasks/setup-traefik.sh` — **pre-existing bug fixed (found during the VM run, blocks goal 4)**: the `traefik.yml` envsubst call listed `HTTP_PORT`/`HTTPS_PORT`/`PROXY_NETWORK`/`ACME_EMAIL` but never exported them, so every fresh render got `entryPoints.*.address: ":"` (Go address `:` = random port) — host 80/443 were forwarded to a port Traefik never listened on, and no HTTP routing was possible on any fresh install. The export line now covers every variable in the envsubst list, with a comment recording the failure signature. (The dev box's working install pre-dates the H-2 envsubst refactor and had correct values, which is why this went unnoticed.)
- [x] `tests/lint.sh` (new, executable) — the ticket's §4 regression guards, ahead of ticket 20's full lint gate (same file will be extended in place): (1) no `privileged:` in `templates/` outside a documented allowlist — the concourse worker is the one exception (it runs a containerd runtime inside the container, which requires privileged mode; removing it would break Concourse, so it is out of this ticket's scope); (2) no floating `image: …:latest` in `templates/traefik/` (the remaining non-traefik `:latest` images are ticket 17's scope).
- [x] `tests/machine-config.test.yml` — `setup-traefik` gets `ACME_EMAIL: "vmtest@example.com"`: the script hard-fails on the default `admin@example.com`, so without this the ticket's `--scripts setup-docker,setup-traefik` VM run can never pass (the `--scripts` config generation preserves test-config env).
- [x] `README.md` — `SOCKET_PROXY_IMAGE` added to the setup-traefik env-var list.
- [x] `.tickets/improvements-2/07-*.md` — "Implementation notes (worker)" section: pinned tag + digest, the read_only degradation evidence, and the required **E2E routing record** (see Validation below).

### Deviations from the ticket's reference implementation (documented in code + ticket file)
- **`read_only: true` is dropped** (the ticket's own fallback path): verified locally and on the VM — v0.5.0 is haproxy-based and the haproxy master writes `/run/haproxy.pid` at startup (`ALERT: Cannot create pidfile /run/haproxy.pid` → exit). Shipped: `cap_drop: ALL` + `no-new-privileges:true` + `tmpfs: /tmp` without `read_only`; reason documented in the template comment. A `tmpfs` on `/run` would restore `read_only` (noted in the template comment + ticket notes).
- **Acceptance criterion "`grep -rn 'privileged: true' templates/` → no output" is met for the ticket's scope (all traefik templates)**; the repo-wide grep still shows the two concourse-worker lines, which are a functional requirement (containerd inside the worker container) and out of scope — the new lint guard encodes exactly this allowlist. Anyone reading the raw grep should look at `tests/lint.sh` for the rule's intent.

### Validation
- [x] Local docker proof of the hardened spec (dev box, throwaway container on an internal net): `Up (healthy)` with the exact healthcheck; `Privileged=false CapDrop=[ALL]`; `_ping` OK; `/version`+`/networks`+`/containers/json` return JSON via the proxy; `/images/json` → **403 Forbidden** (allow-list enforced); a client container on the same net reaches `…:2375` by name. With `--read-only` added: container crashes with the pidfile ALERT (documented basis for the deviation)
- [x] Pinned digest verified: `docker buildx imagetools inspect` — `latest` and `v0.5.0` both resolve to `sha256:1f5038…d3459` (ghcr tag list checked: `v0.5.0` is the newest release tag)
- [x] `docker compose config` on all **8** rendered variants (4 socket + 4 nosocket) exits 0 (env exported per the script; `.dns` variants get a `.env` like a real install)
- [x] `shellcheck tasks/setup-traefik.sh tests/lint.sh` + `bash -n`: 0 findings; `yamllint -c templates/.yamllint templates/traefik/`: 0 errors (pre-existing `document-start` warnings only); `./tests/lint.sh` PASS; `grep -rn "privileged" templates/traefik/` → empty; `git diff --stat -- templates/traefik/docker-compose.nosocket.*.yml` → empty
- [x] Live VM run (fresh Ubuntu 26.04 `resolute`, `tests/run-vm-tests.sh --scripts setup-docker,setup-traefik --keep-vm` + manual runs on the kept VM — the harness's setup-docker/setup-traefik phases hit the **known** usermod→docker group-membership artifact on its long-lived SSH session, same signature as the ticket-04 run; all checks below then pass from a fresh login session on the same VM):
  - `docker ps --filter name=traefik-socket-proxy` → `Up … (healthy)`; `docker inspect … --format '{{.HostConfig.Privileged}} {{.HostConfig.CapDrop}} {{.HostConfig.ReadonlyRootfs}}'` → `false [ALL] false`
  - `docker logs traefik` → `Starting provider *docker.Provider` (endpoint `tcp://socket-proxy:2375`); no provider errors
  - `docker exec traefik-socket-proxy wget -qO- http://localhost:2375/_ping` → `OK`; `docker exec traefik wget -qO- http://traefik-socket-proxy:2375/networks` → JSON; `…/containers/json` → JSON; `…/images/json` → 403
  - `docker network inspect traefik_socket-net` → members: `traefik-socket-proxy traefik` only
  - rendered `/opt/traefik/docker-compose.yml` on the VM carries `ghcr.io/tecnativa/docker-socket-proxy:v0.5.0@sha256:1f50…` and no privilege line
  - **E2E (recorded in the ticket file):** `e2e-probe` (nginx:alpine, standard labels, `websecure` router + file-provider self-signed cert) → `curl -k https://e2e.vmtest/` = **HTTP 200** (HTTP/2, nginx upstream page) through Traefik; `setup-planka` with `PLANKA_TRAEFIK=true PLANKA_DOMAIN=planka.vmtest` → containers `Up (healthy)`, router+server created via the docker provider through the proxy (`Adding route for planka.vmtest … routerName=planka@docker`, `Creating server URL=http://<ip>:1337`), ACME issuance attempted and failing only for environmental reasons (non-public domain; LE rejects the `@example.com` test contact). Note: the `web` entrypoint is a max-priority 301→websecure redirector, so HTTP-only routers can never serve — the probe uses `websecure`. Traefik 3.7.12 logs router/server creation at DEBUG (`Creating server`), not INF `Adding server`
  - idempotent re-run of `setup-traefik.sh` → `Traefik is already running — skipping setup.` rc=0, stack untouched
- [x] VM torn down after verification (`vm-destroy mas-vmtest-20260830-072051`)

### Notes / assumptions
- Concourse's `privileged: true` (worker) was left in place deliberately — see deviation above; if a future ticket wants it gone, the containerd-in-container runtime is the constraint to solve first.
- `EVENTS: 1` kept as-is (consolidation ticket's call, per the ticket).
- `validate_image "$SOCKET_PROXY_IMAGE" …` intentionally not added yet — the helper lands in ticket `15-lib-validation-helpers.md`, per the ticket.
- VM test report: `tests/reports/vmtest-20260830-072051/` (gitignored, on disk only).
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–06 were closed.

## 2026-08-30T11:00:13+02:00 - worker (ticket 08)

### Implemented: verify every deployed stack — `wait_for_healthy()` in `lib/helpers.sh` + a health gate after every `docker compose up -d` (ticket `08-compose-health-verification`)

- [x] `lib/helpers.sh` — new `wait_for_healthy <timeout_s> <container-id...>` (`declare -F`-guarded, built on ticket 01's `err_msg`): polls `docker inspect` (one `sudo docker` fallback per query for the `sudo compose` tasks) until every container is running and — when it defines a healthcheck — healthy; `exited`/`dead`/`restarting`/uninspectable are immediate failures (crash loop), `created`/`starting` keep waiting; returns 1 (never exits) with the offending container names, a `docker ps -a` status table, and inspect/logs pointers; an empty id list fails loudly (no vacuous pass).
- [x] Health gate after every **real** `up -d` in 14 scripts (13 files — colqwen excluded, see notes): planka, openwebui, concourse, forgejo, hermes, monitoring, n8n, netbird (main stack + `--profile client`), nextcloud, omnigent, opencode-server, traefik, vllm, vllm-omni. Each call passes `--env-file`/`-f` (and `sudo`, where used) exactly as the surrounding `up -d`, collects `docker compose ps -q` via `mapfile`, and calls `wait_for_healthy … || error "<service> stack did not come up — see the status output above"` so a crash-looping stack can never be reported as success. The premature `success "Stack started."` lines were replaced by the gate's own success message (per the ticket's "never before the gate" note); existing HTTP/status polls (planka, openwebui, concourse, forgejo, netbird, omnigent, monitoring, vllm, opencode) are kept and now run **after** the container gate.
- [x] `tasks/setup-concourse.sh` — the inline `ps --filter "status=exited"` check (the only such check in the repo) is gone; the helper is the single implementation (covers crash loops, not just already-exited containers; `sudo docker` prefix kept).
- [x] `tasks/setup-nextcloud.sh` — `lib/helpers.sh` is now sourced unconditionally (previously only in the Traefik pre-flight; the lib is fully `declare -F`-guarded and the script's own colour/logging functions defined earlier take precedence — same pattern as ticket 06's openwebui change), so the gate works in direct mode too.
- [x] `tasks/setup-hermes.sh` — the update-path `up -d hermes-gateway` (best-effort branch) is now followed by a name-based `wait_for_healthy … hermes-gateway || error …` (the container name is fixed by the template and already assumed by the script's own greps), so a failed/crash-looping gateway can no longer end in "Hermes Agent updated!".
- [x] Timeouts: `WAIT_TIMEOUT` (default 180 s) in the 12 scripts above; `setup-vllm.sh` reuses its existing `VLLM_HEALTH_TIMEOUT` (900 s GPU / 120 s CPU) for the gate per the ticket's "script's own existing naming convention"; `setup-vllm-omni.sh` gets new `VLLM_OMNI_HEALTH_TIMEOUT` (default 300 s — inference stacks). Every touched script's `--help` documents it (verified: all 14 `--help` runs exit 0 and show the variable); nextcloud's header comment too.
- [x] Docs: `specification/project/conventions.md` gains a **Stack health verification** section (the ticket's contract wording + usage rules); `AGENTS.md` gains a **Stack health verification** bullet under *bash Script Specifications* pointing at it.
- [x] `tests/machine-config.test.yml` — `setup-planka` and `setup-monitoring` entries added (`enabled: false`, for `--scripts` runs; monitoring gets `GRAFANA_DOMAIN=monitoring.vmtest` — required by the script — and `MONITORING_FORCE=true` so the idempotency phase exercises the full start+gate path instead of hitting the non-interactive existing-stack refusal).
- [x] `tasks/setup-monitoring.sh` — **two pre-existing bugs fixed (found by this ticket's mandatory VM run, blocking goal 4)**:
  - `install -d -o 472 -g 472` failed on any fresh system (`install` rejects numeric ids with no host user; `invalid user: '472'`) → now `mkdir -p` + numeric `chown -R 472:472` on the three mounted grafana trees (no-op on re-runs; matches grafana's own docs remedy).
  - The direct-mode port-conflict check ran in pre-flight, **before** the `MONITORING_FORCE`/`--interactive` teardown — so any re-create of a running stack died with "Port 3100 is already in use" (its own stack). The check now runs after the idempotency/teardown section; foreign-service conflicts still fail loudly with the same message.

### Deviations from the ticket's reference implementation (documented in code)
- **`health == "running"` → `health == "healthy"`**: the reference compared the healthcheck status against `"running"`, but Docker's values are `starting|healthy|unhealthy` — with the reference as written, a running+healthy container (planka/concourse/omnigent postgres, traefik socket-proxy) could **never** pass and the ticket's own mock test (`PASS_OK`) was unsatisfiable (verified empirically: first implementation timed out on the ticket's healthy mock).
- **True immediate failure**: the reference still slept one 5 s cycle after detecting `exited`/`restarting` before bailing (the ticket mock failed in 5.01 s, not "well under 5 s" as its acceptance criterion requires). The loop now breaks without the sleep on any hard-fail state (verified: 0.008 s).
- Cosmetic/robustness: `rest`/`name` declared `local` (the reference leaked them into the caller's namespace — `name` is a common variable); unhealthy containers are reported once (the reference appended both `name(unhealthy)` and `name(running/unhealthy)`); the three trailing `err_msg` lines are `|| true`-guarded so all diagnostics print even on a plain (unguarded) `set -e` call; the timeout message distinguishes "failed state (crash loop?)" from "not healthy after Ns".

### Validation
- [x] Ticket mock test (fake `docker` on `PATH`, no daemon): healthy id → `PASS_OK` on first poll; crashed id → fails in **0.008 s** (well under 5 s) with `/planka-postgres(exited)` named + status table + inspect/logs pointers
- [x] Extra mock edge cases: empty id list → loud failure (no vacuous pass); `created` state → waits to the timeout then fails; `starting→healthy` transition → passes; `running+unhealthy` → single report, timeout fail; mixed good+restarting → immediate fail naming only the bad one; bare (unguarded) `set -e` call → all three diagnostic lines printed, rc=1, nothing after the call runs
- [x] Real-docker proof (dev box, throwaway stop/start of the running `/srv/planka` container): 2-container project passes; stopped container → immediate fail naming `/planka(exited)`; restarted → passes again
- [x] Coverage: every non-help `up -d` in the 15 scripts is followed by `wait_for_healthy` within 25 lines (the only no-wait `up -d` occurrences left are `--help`/summary strings, incl. colqwen's four); Concourse's inline `status=exited` check is gone; no `up -d … || true` anywhere
- [x] `shellcheck -x lib/helpers.sh` + `shellcheck` on all 14 touched task scripts + `bash -n` on `lib/helpers.sh` and all `tasks/*.sh`: 0 findings
- [x] `yamllint tests/machine-config.test.yml`: clean; `--help` of all 14 touched scripts exits 0 and documents the timeout variable
- [x] End-to-end on a fresh Ubuntu 26.04 (`resolute`) VM, `tests/run-vm-tests.sh --scripts setup-docker,setup-traefik,setup-planka,setup-monitoring --keep-vm` + fresh-login verification on the kept VM (same approach as tickets 04/07, see notes):
  - `setup-traefik` → rc=0, "All 2 container(s) up and healthy" (traefik + socket-proxy)
  - `setup-planka` (fresh) → rc=0, gate + HTTP poll pass
  - `setup-monitoring` → rc=0, "All 4 container(s) up and healthy"; re-run with `MONITORING_FORCE=true` → teardown + re-create + gate, rc=0 (port-conflict fix proven)
  - **Crash-loop acceptance (the ticket's headline test):** `POSTGRES_PASSWORD`/`DATABASE_URL` in `/srv/planka/.env` set to a value the persisted cluster does not know → `setup-planka.sh --interactive` exits **rc=1** with `Stack not healthy — a container is in a failed state (crash loop?): /planka(restarting)` + status table + logs pointer (immediate, no timeout burn); postgres container itself stayed `Up (healthy)` — the app restart-loop is what the gate catches
  - Recovery: cluster password aligned, `setup-planka.sh --interactive` → rc=0, "All 2 container(s) up and healthy" + "Planka is up and responding!"
  - `docker compose --profile client ps -q` verified to list the profile-gated container (scratch busybox project) — the netbird client gate checks what it claims to
- [x] VM torn down after verification (`vm-destroy mas-vmtest-20260830-101831`)

### Notes / assumptions
- **Harness flake (known, unchanged):** the suite's own run failed 7/9 for the same reason as the ticket-04/07 runs — all scripts execute in one long-lived SSH session that predates `usermod -aG docker`, so `docker info` as the session user is permission-denied for the whole run (setup-docker integration rc=1, then every docker task's pre-flight). The fresh-login runs above execute the identical scripts/env on the same VM and all pass; a per-script re-login is a harness fix for the test-infrastructure tickets (20/21), out of scope here.
- **setup-planka idempotency in a non-interactive suite run is expected to fail** on the pre-existing non-interactive existing-stack refusal ("Re-run with --interactive…") — that policy is ticket `12-existing-stack-rerun-policy.md`'s scope (already recorded by ticket 06). The `--interactive` re-create path (teardown → gate) is what the VM runs above prove.
- `setup-colqwen.sh` intentionally untouched: it only **generates** the project (all four `up -d` hits are `--help`/summary text — the operator builds and starts it manually), so there is no `up -d` to gate.
- `setup-omnigent.sh`'s later "Verifying container status" block (docker-ps greps + restart-loop check) is kept as a second, app-specific layer per the ticket's "keep existing polls" rule; the gate is the first line.
- Local real-docker proof briefly stopped and restarted the dev box's `/srv/planka` container; verified running+healthy afterwards.
- VM test report: `tests/reports/vmtest-20260830-101831/` (gitignored, on disk only).
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–07 were closed.

## 2026-08-30T13:31:46+02:00 - worker (ticket 09)

### Implemented: scope the failure-cleanup traps — a late failure can no longer tear down a stack that was running before the run (ticket `09-cleanup-trap-scoping`)

- [x] All six trap-carrying scripts (`tasks/setup-monitoring.sh`, `setup-nextcloud.sh`, `setup-omnigent.sh`, `setup-openwebui.sh`, `setup-opencode-server.sh`, `setup-llama-swap.sh`) — `cleanup_on_failure` is now flag-guarded, with the flag declared **before** the trap is armed (the `set -u` requirement from the ticket's notes): `STACK_CREATED_THIS_RUN` (docker stacks) / `SERVICE_TOUCHED_THIS_RUN` (llama-swap unit). Flag 0 → the trap returns without touching anything and prints "… — nothing torn down."; flag 1 → the existing `down --remove-orphans 2>/dev/null || true` (kept verbatim per the ticket, incl. `--remove-orphans`) removes the stack this run created. Existing `trap - EXIT` disarms (script end + existing-stack refusal branch) kept.
- [x] Flag lifecycle: `=1` immediately before every `up -d` / `systemctl enable|start llama-swap`, `=0` once the health gate proves healthy (llama-swap: after its HTTP poll responds). The interactive re-create branches set `=1` right after the operator confirms the teardown (monitoring: at the shared teardown point, covering both `MONITORING_FORCE=true` and the interactive confirm) — so a confirmed re-create is covered from teardown through re-create ("cleanup still applies to a half-created re-create").
- [x] `tasks/setup-omnigent.sh` — the five ad-hoc post-start checks (2× container-not-running, the restart-loop detection, 2× HTTP-check failures) are deleted together with their dead `exit 1` lines after `error` (error() exits — the log dump and `down` behind it never ran). The shared `wait_for_healthy` gate (ticket 08) is the single check now, and its failure path dumps `docker compose logs --tail=50` before `error "Omnigent stack did not come up"` (acceptance: "prints container logs when the stack fails to come up"). The embedded `down --remove-orphans` calls are stripped from the HTTP reachability check — a stack that is up but slow to answer is not removed (the flag is already 0 there, so the trap does not tear it down either). The unconditional pre-`up -d` teardown in the normal flow is kept (re-run policy = ticket 12) with a comment making that explicit.
- [x] `tasks/setup-opencode-server.sh` — the mid-script inline-string trap (which cannot see a later-set flag without quoting hazards) is hoisted to the same named-function + flag form as the other five: function next to the other helpers, one `trap cleanup_on_failure EXIT` (top level), `trap - EXIT` disarm in `setup_docker` kept.
- [x] `tasks/setup-llama-swap.sh` — a pre-existing **working** unit is no longer stopped/disabled by an unrelated failure: the flag is set only (a) immediately before the re-install stop/disable (operator-accepted re-install) and (b) immediately before `systemctl enable/start`; an earlier failure (preflight, download, …) exits with "The llama-swap service was not touched by this run — nothing stopped or disabled." and the unit stays `active` (verified live, see below).
- [x] **Blocker found by this ticket's own VM verification — fixed in `lib/helpers.sh`: the ticket-01 trap chain clobbered the exit code.** `_mktemp_arm_exit_trap` chained `"_mktemp_cleanup; <caller handler>"`; `_mktemp_cleanup` (always returns 0) ran **before** the caller's handler, so the handler's `local exit_code=$?` captured 0 and every failure cleanup chained this way silently did nothing — proven live (a failed confirmed re-create printed no trap output at all; `bash -x` showed `local exit_code=0`). Exactly the failure mode the ticket's note anticipates ("do not add commands before that capture or the exit code is lost" — ticket 01's chain *did* add one). Fixed by reordering to `"<caller handler>; _mktemp_cleanup"`: the handler sees the original exit status, and — `cleanup_on_failure` returns 0 on every path — the temp-file cleanup still runs. Affected every script that arms its trap before sourcing lib (monitoring, nextcloud, openwebui, llama-swap); omnigent/opencode-server install their trap after sourcing and were not affected.

### Deviations from the ticket's reference implementation (documented in code)
- **`setup-planka.sh` left untouched, although the ticket lists its re-create branch**: it has **no** `cleanup_on_failure` trap at all (verified: zero `trap` occurrences in the script), so there is nothing to guard and no flag to set — an unused flag would be dead code (SC2034 would fail the ticket's own shellcheck gate). All acceptance criteria are scoped to "the six scripts" that carry the trap, and planka already satisfies the goals (no late-failure teardown exists; the non-interactive re-run refuses before touching the stack).
- **Running-state check added inside the flag-set teardown branch of every cleanup** (beyond the ticket's reference): before calling `down`, the function now checks `docker compose ps -q` — running → `down --remove-orphans` + "Removed partially created stack."; nothing running → **no** `down` call + "Stack from this run is already stopped — data … is preserved." This implements the ticket's final note: a failed run after a confirmed re-create "may legitimately leave a *stopped* stack behind — the printed message must say so, otherwise it looks like data loss." (live-verified: the pull-failure re-create printed exactly that, data dirs intact.) The `down` command, its `2>/dev/null || true` guard and `--remove-orphans` are otherwise unchanged.

### Validation
- [x] `shellcheck -x lib/helpers.sh` + `shellcheck` on all six task scripts: 0 findings; `bash -n` clean on all seven files
- [x] `--help` of all six scripts exits 0 (no new options/env vars; no help text described the trap behaviour, so none needed updating)
- [x] Ticket greps: `grep -n "trap " tasks/*.sh` → exactly one `trap cleanup_on_failure EXIT` per script (no inline string traps) plus the 10 disarms; `grep -n -A3 "error \"" tasks/setup-omnigent.sh | grep -B1 "docker compose down"` → empty (dead code gone); `down -v` → only concourse's interactive-only volume wipe (explicitly allowed) and a monitoring header comment
- [x] Stub harness against the **extracted real trap blocks** of all six scripts (52/52 assertions, `set -euo pipefail`): flag 0 + running stack + forced failure → zero `down`/`stop` calls + "nothing torn down" message + exit code preserved (the M-6 core); flag 1 + running → `down --remove-orphans` / stop+disable exactly once + "Removed partially created stack"/"Partial service removed."; flag 1 + already stopped → no teardown + "already stopped … preserved"
- [x] Gate stub test with the **real** `wait_for_healthy` + extracted omnigent gate block (7/7): crashed container → immediate "failed state (crash loop?)" + container-logs dump + "Omnigent stack did not come up" + rc=1 (flag stays 1 → trap cleans up); healthy → gate passes + flag cleared to 0
- [x] Chain regression test (the lib fix): a caller trap armed before sourcing lib now sees the real exit status (handler got rc=1 on failure, final rc preserved; rc=0 stays silent) and direct `mktempfile` usage still cleans its files at exit
- [x] Live VM (fresh Ubuntu 26.04 `resolute`; `tests/run-vm-tests.sh --scripts setup-docker,setup-traefik,setup-monitoring --keep-vm` + fresh-login verification on the kept VM, same approach as tickets 04/07/08):
  - `setup-traefik` → rc=0 (idempotent skip on the second attempt; traefik + socket-proxy healthy)
  - `setup-monitoring` fresh → rc=0, "All 4 container(s) up and healthy" + HTTP check
  - **M-6 (the ticket's literal check):** healthy stack, `WAIT_TIMEOUT=1 ./tasks/setup-monitoring.sh` → **rc=1**, refusal message, `docker ps` before/after **identical** (stack stays running, nothing torn down)
  - **Confirmed re-create + late failure:** `MONITORING_FORCE=true PROMETHEUS_IMAGE_VERSION=prom/prometheus:doesnotexist123` → confirmed teardown, pull fails → rc=1, trap: "Setup failed (exit code: 1)! Removing the stack created by this run…" + "Stack from this run is already stopped — data in /srv/monitoring/prometheus and /srv/monitoring/grafana is preserved."; data dirs verified intact (grafana.db, prometheus chunks)
  - **Crash-loop (the ticket's intended case):** broken `prometheus.yml` template → `MONITORING_FORCE=true` → gate: "Stack not healthy — a container is in a failed state (crash loop?): /prometheus(restarting)" → trap: "Removed partially created stack." → rc=1, no monitoring containers left; template restored, `MONITORING_FORCE=true` re-run → rc=0, all 4 healthy (recovery)
  - **llama-swap AC:** fresh install rc=0, unit `active`; then `apt-get remove jq` → re-run rc=1, "The llama-swap service was not touched by this run — nothing stopped or disabled.", unit **still `active`** (jq restored afterwards)
  - **llama-swap confirmed re-install + download 404** (`LLAMA_SWAP_VERSION=v9.9.9 --force`): unit stopped first (operator-accepted, flag=1) → rc=1, "Service from this run is already stopped — config and data in /srv/llama-swap are preserved."; `systemctl enable --now` → `active` again
- [x] `./run-setup.sh status` rc=0 (33 scripts); VM torn down after verification (`vm-destroy mas-vmtest-20260830-123815`)

### Notes / assumptions
- **Supersedes one of ticket 08's recorded notes:** ticket 08 kept omnigent's "Verifying container status" block "as a second, app-specific layer"; ticket 09 re-examined it and found all of it dead code (every branch dies at `error()` before the log dump / `down` / `exit 1`), so this ticket deletes it per its explicit instruction ("Delete the five `error` + dead-code blocks … and the restart-loop detection").
- The VM suite's own docker phases failed for the **known harness artifact** (one long-lived SSH session predating `usermod -aG docker`, same signature as tickets 04/07/08; 2/7); all fresh-login runs above execute the identical scripts/env on the same VM and pass.
- The lib chain fix changes trap ordering for every script that arms its trap before sourcing lib: the temp-file cleanup now runs **after** the caller's handler. `cleanup_on_failure` returns 0 on all paths, so cleanup still happens; a hypothetical handler that exits itself would skip the file cleanup (documented in the function comment; no current handler does that). `setup-zed.sh` (the only `mktempfile` user) arms no own trap and is unaffected.
- After this change a failed **confirmed** re-create can legitimately leave a *stopped* stack behind (the operator accepted the re-create); the trap's message now says the data is preserved (live-verified above) instead of claiming a removal.
- `setup-omnigent.sh`'s live deploy was not exercised on the VM (installing omnigent — uv/Node prereqs, image pulls — is beyond this 1–2 h ticket's scope): its changes are covered by the dead-code grep, the trap-stub matrix and the real-`wait_for_healthy` gate test; the ticket's own Verification block scopes the VM run to monitoring.
- VM test report: `tests/reports/vmtest-20260830-123815/` (gitignored, on disk only).
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–08 were closed.

## 2026-08-30T14:45:08+02:00 - worker (ticket 10)

### Implemented: `run-setup.sh` CLI correctness — options after the subcommand, colour/TTY handling, validated status counts, read-only `status`, non-interactive contract (ticket `10-run-setup-cli-correctness`)

- [x] `run-setup.sh` — **M-2**: `main()` rewritten as a two-pass scan: global options (`-c/--config`, `--interactive`, `--non-interactive`, `-h/--help`) are consumed wherever they appear (before **or** after the subcommand); exactly one subcommand is taken; unknown option, extra positional, `--config` without a value, duplicate `--config`, and both interactive flags → `exit 2` with usage on stderr (never silently dropped). `cmd_apply`/`cmd_status` now take **no** arguments (the shift-and-forward pattern is gone); unknown subcommand → single `log_error` line + help, `exit 1` (repo convention: 0 ok, 1 failure, 2 usage, per `tests/run-vm-tests.sh`); `--help` anywhere → help, exit 0; no args → usage, exit 0.
- [x] `run-setup.sh` — **L-1**: colour is emitted only when stdout is a TTY and `NO_COLOR` is unset (`-t 1` probe at source time; the VM harness captures to files, so it automatically gets the plain variant). Log helpers: the empty third `%b` (stray double space) is gone; the unknown-subcommand branch prints a **single** `[ERROR]` line (was `[ERROR] [ERROR]`); `log_step` no longer puts a stray `RESET` after the message.
- [x] `run-setup.sh` — **L-2**: `enabled_count` is normalised to 0 *before* any arithmetic in both `cmd_status` and `cmd_apply` (`[[ =~ ^[0-9]+$ ]] || =0`); `disabled_count` clamped to ≥ 0; the duplicate `local line` deleted (the one at old `:293`). The count queries are guarded (`if ! …=$(yq … 2>/dev/null)`), so a yq failure yields a clean error + `exit 1` instead of a `set -e` abort mid-script.
- [x] `run-setup.sh` — **L-7**: `check_dependencies <mode>` — `status` is read-only: missing yq/jq → hint ("Install them (e.g. './run-setup.sh apply' or 'tasks/setup-basics.sh'), then re-run status.") + `exit 1`, `ensure_basic_tools` is never called; `apply` keeps the auto-install. `ensure_basic_tools` now refuses the auto-run when `NON_INTERACTIVE=true` and `ASSUME_SETUP_BASICS` is not explicitly `true` (fail fast: an unattended run does not silently provision a machine) — documented in `--help` and README; plain `apply` still auto-installs (README quick-start unchanged).
- [x] `run-setup.sh` — **M-3 orchestrator half**: the `INTERACTIVE` contract is declared at the top (`: "${INTERACTIVE:=false}"` + `NON_INTERACTIVE`, with the conventions.md pointer); `--interactive`/`--non-interactive` set it (mutually exclusive → `exit 2`); `run_script` now passes `INTERACTIVE=true|false` explicitly to every child, and in non-interactive mode gives children `stdin=/dev/null` so a stray `read` fails fast instead of hanging an unattended run (both the with-env and no-env branches).
- [x] `run-setup.sh` — new config sanity check in `check_dependencies` (both modes): `.scripts | type` must be `object`/`null` (or absent) → clean early error for a config that does not parse or has the wrong type (e.g. `scripts: "not-a-map"` → "Invalid configuration: '.scripts' must be a mapping (got string)"), before any count arithmetic can be reached (see deviation below).
- [x] `run-setup.sh` — `cmd_help` rewritten: the new flags, options-before-or-after-subcommand, the INTERACTIVE contract, the recorded decision that `--yes`/`ASSUME_YES` is **deliberately not** implemented, `--only`/`--dry-run` noted as unimplemented, `ASSUME_SETUP_BASICS` documented, config-wins for `env: INTERACTIVE`, corrected examples (`./run-setup.sh apply --config my-config.yml`); the file-header USAGE block matches.
- [x] `README.md` — "Running the Orchestrator" section updated to match (option list incl. `--interactive`/`--non-interactive`, placement note, read-only `status` / auto-install semantics, config-wins note, corrected example); the "How It Works" orchestrator bullet mentions the before-or-after placement.

### Deviations from the ticket's reference implementation (documented in code)
- `run_script` places the orchestrator's `INTERACTIVE` value **before** the config env entries (`env "INTERACTIVE=false" "${env_args[@]}" …`) instead of the ticket's reference snippet order (`env "${env_args[@]}" INTERACTIVE=false …`). The reference snippet contradicts the ticket's own rules ("A per-script `env:` entry in the config may still override `INTERACTIVE` (config wins)" and the Notes: "children get `env … INTERACTIVE=<config value>` last … appending our value first keeps config precedence"); with the reference order the config could never win. Verified with the probe: `env: {INTERACTIVE: "true"}` + `--non-interactive` → child sees `INTERACTIVE=true` (stdin still `/dev/null`); `env: {INTERACTIVE: "false"}` + `--interactive` → child sees `INTERACTIVE=false` on the inherited tty.
- Log helpers pass `$*` as a **separate** printf argument (`printf '%b %b %s\n' … "${CYAN}[INFO]${RESET}   " "$*"`) rather than embedded in the tag string as in the ticket's snippet: the snippet's format strings trigger shellcheck SC2183 (3 format variables, 2 arguments) and would fail the ticket's own `shellcheck → exit 0` gate. Output is byte-identical to the ticket's intended alignment (4/6/3/1 spaces after `[INFO]`/`[OK]`/`[WARN]`/`[ERROR]`).
- The `.scripts | type` sanity check (above) is an addition over the ticket's reference: without it, `apply` on a wrong-type config aborts with a raw jq error under `set -e`, and `status` prints a misleading "Scripts in config: 9" (string length) before failing. It uses jq's `type` because the repo's yq is the jq wrapper (apt `yq`); mikefarah's `tag` is unavailable.

### Validation
- [x] `shellcheck run-setup.sh` exit 0; `bash -n run-setup.sh` clean
- [x] **M-2:** `./run-setup.sh -c tests/machine-config.test.yml status` ≡ `./run-setup.sh status --config tests/machine-config.test.yml` — both print `Configuration: …/tests/machine-config.test.yml`, rc=0
- [x] **M-2:** all-disabled config (2 entries, both `enabled: false`) via `apply --config …` → nothing runs, rc=0
- [x] `status --config` (no value) → rc=2 + "--config requires a value"; `status --bogus` → rc=2, usage on stderr, exactly one `[ERROR]` line; `status extra-arg` → rc=2 "Unexpected argument"; `-c` twice → rc=2
- [x] `--help` → rc=0 (also after a subcommand: `status --help` → help, rc=0); `nosuchcmd` → rc=1, single error line; no args → usage, rc=0; `--interactive --non-interactive status` → rc=2 "mutually exclusive"
- [x] **Colour probe:** piped `status | grep -c $'\033'` → 0; `NO_COLOR=1 script -qec … | grep -c $'\033'` → 0; `script -qec … | grep -c $'\033'` → 52 (> 0)
- [x] **L-2:** `printf 'scripts: "not-a-map"\n' > /tmp/bad.yml; ./run-setup.sh -c /tmp/bad.yml status` → rc=1, clean "Invalid configuration: '.scripts' must be a mapping (got string)" — no arithmetic error; a string *entry* (`scripts.a: "not-a-map"`) → clean "Could not compute the enabled-script count" error, rc=1
- [x] **L-7:** stripped-`PATH` (no yq/jq): `status` → rc=1 + install hint, `bash -x` trace confirms `setup-basics.sh` is never invoked (only mentioned in the hint text); `apply --non-interactive` → rc=1 refusal naming the remedy, no auto-install
- [x] **Auto-install matrix** (fake `setup-basics.sh` in a throwaway tree, real machine untouched): default `apply` → auto-installs and continues, rc=0 (README quick-start preserved); `apply --non-interactive` → refuses, rc=1; `ASSUME_SETUP_BASICS=true apply --non-interactive` → auto-installs, rc=0
- [x] **M-3 probe** (the ticket's `/tmp/rs` harness — real `tasks/` untouched): `apply --non-interactive` and default `apply` → child prints `INTERACTIVE=false stdin_tty=no`; `apply --interactive` under a pty → `INTERACTIVE=true stdin_tty=yes`; config-wins matrix as in the deviation above
- [x] Existing consumer (VM-harness precheck form): `./run-setup.sh -c tests/machine-config.test.yml status` → rc=0, 10 scripts listed (8 enabled per test config)
- [x] `./run-setup.sh status` on the default config → rc=0; `--help` documents the new flags and post-subcommand `--config`; README "Running the Orchestrator" matches

### Notes / assumptions
- Task-side consumption of the `INTERACTIVE` env var (incl. the `setup-llama-swap.sh` unguarded `read` fix) is ticket `11-llama-swap-non-interactive.md`'s scope; the ten task scripts today still gate on their own `--interactive` CLI flag. This ticket establishes the orchestrator contract (explicit env var + stripped stdin), exactly as the ticket scopes it ("11 and 12 consume the flags introduced here").
- `INTERACTIVE` inherited from the calling environment is kept by the `: "${INTERACTIVE:=false}"` default (the ticket's reference); an explicit `--non-interactive` overrides it, `--interactive` sets it.
- `apply` with zero enabled scripts still exits 0 silently (pre-existing behaviour, unchanged).
- No VM run for this ticket: all changes are CLI/contract-level and were verified with the ticket's probe harness, exit-code matrix, colour probes and stripped-PATH traces on the dev box (same machine class as the harness target). A fresh-VM `tests/run-vm-tests.sh` pass was not executed in this pass (capacity) — the precheck form it consumes (`-c <config> status`) is verified above.
- The two untracked `docs/` files at the branch root (`docs/plans/vm-integration-tests.md`, `docs/qwen38-flash-next-review.md`) are pre-existing and were left untouched and uncommitted.
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–09 were closed.

## 2026-08-30T15:32:31+02:00 - worker (ticket 11)

### Implemented: `setup-llama-swap.sh` non-interactive by default — `INTERACTIVE` flag gates both `read -rp` prompts, "keep existing + exit 0" is the non-interactive default (ticket `11-llama-swap-non-interactive`)

- [x] `INTERACTIVE=false` added to the flag-default block next to `FORCE=0`; new `--interactive) INTERACTIVE=true ;;` arm in the existing `while`/`case` parser (the stricter loop is kept; the ticket's "mirror traefik's for-loop parser" reference is superseded by its own Notes section)
- [x] Prompt 1 (existing unit, `:246-264`): `--force` proceeds as before; `--interactive` prompts `[y/N]` as before (`n` → keep + `exit 0`); neither → `info "Non-interactive: keeping existing setup (${SERVICE_FILE} untouched)."` + re-run hint + `exit 0` — the zero status keeps ticket 09's `cleanup_on_failure` trap quiet; the trap itself is untouched
- [x] Prompt 2 (existing binary, `:296-312`): same gating; the non-interactive branch sets `SKIP_BINARY_DOWNLOAD=1` (reuses existing state, no new variable) → "Binary unchanged at …"
- [x] Header `KEY ACTIONS` item 2 ("Keeps an existing installation unless `--force`; prompts only with `--interactive`"), header `USAGE` block (`--interactive` line + "`--force` takes precedence over `--interactive`") and `usage()` (option line + precedence note, options re-aligned) updated; `IMPORTANT VARIABLES` and the `--help` env list unchanged (no env-var changes)

### Validation
- [x] `bash -n tasks/setup-llama-swap.sh` + `shellcheck -x tasks/setup-llama-swap.sh` exit 0
- [x] `grep -n 'read -rp'` → exactly 2 lines, each directly under `elif [[ "$INTERACTIVE" == "true" ]]`; `grep -n 'INTERACTIVE'` shows `INTERACTIVE=false` in the flag-default block and `--interactive) INTERACTIVE=true ;;` in the parse loop
- [x] `--help | grep -c -- '--interactive'` → 1; unknown option still → clean `[ERROR]` + rc=1
- [x] VM harness (`tests/run-vm-tests.sh --scripts setup-basics,setup-llama-swap --keep-vm`, fresh Ubuntu 26.04 `resolute`): **5/5 PASS** — llama-swap integration (fresh install, unit active) rc=0 in 6 s; **idempotency rc=0 in 0 s** via the harness's non-tty stdin — exactly the keep-existing path this ticket makes safe (pre-fix this run aborted at `read` EOF under `set -euo pipefail`)
- [x] **The ticket's literal check** (VM, unit active + binary present): `sha256sum` of `/etc/systemd/system/llama-swap.service` and `stat %Y` of `/usr/local/bin/llama-swap` captured before; `time ./tasks/setup-llama-swap.sh </dev/null; echo "exit=$?"` → **exit=0 in 0.011 s** printing "Non-interactive: keeping existing setup (… untouched)" + hint; after: `systemctl is-active` = `active`, sha256 and mtime byte-identical
- [x] `--force </dev/null` → "proceeding automatically", unit stopped+disabled first, binary re-downloaded and replaced (mtime changed), never prompts, service restarted + healthy, exit=0
- [x] `--interactive --force </dev/null` → **force wins**: both prompts auto-proceed, no prompt, binary replaced, exit=0
- [x] `--interactive` on a tty (via `script` pty, delayed input): `n` → "Keeping existing setup. Exiting." exit=0 with nothing touched; `y` + `n` → unit stopped/disabled, prompt 2 kept the binary ("Binary unchanged at …"), service re-installed + healthy, exit=0
- [x] `--check` output unchanged (service/config/binary reports + status dump, exit 0)
- [x] VM torn down after verification (`vm-destroy mas-vmtest-20260830-151555`)

### Notes / assumptions
- First interactive pty probe used `printf 'y\nn\n' | script -qec …`: the input pipe closed immediately, so `script` tore down the pty before prompt 2's `read` (EOF → `set -e` abort → the flag-guarded trap reported "already stopped — config and data … preserved", unit left stopped, data intact). That is the ticket's documented residual risk ("`--interactive` without a tty still aborts at `read`"), not a script defect — a real operator tty stays open; the retest with delayed input passes end-to-end.
- `INTERACTIVE` is a plain script-local flag (like the ten other task scripts), not inherited from the environment: `run-setup.sh`'s `INTERACTIVE` env (ticket 10) reaches this child, but the local default overwrites it — exactly the reference the ticket specifies. Net effect: under `run-setup.sh apply` (non-interactive children get `stdin=/dev/null`) the script keeps an existing install and exits 0 without hanging or tearing down; an operator who wants prompts passes `--interactive` via the config's `args:` (interactive children keep the inherited tty).
- Ticket body line numbers drift from the file (ticket 09's trap rework added lines); all edits matched by content.
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–10 were closed.

## 2026-08-30T21:03:46+02:00 - worker (ticket 12)

### Implemented: one re-run policy for existing stacks — converge by default (ticket `12-existing-stack-rerun-policy`)

- [x] **Policy text in `specification/project/conventions.md`** — new bullet **`Re-run policy: converge by default`** under the `Non-interactive by default` rule (re-render from `templates/<component>/`, reuse stored secrets, `docker compose up -d`, prove health via ticket 08's `wait_for_healthy`; no `down`, never `down -v`; `--interactive` may offer tear-down/re-create with converge as the default answer and `y` the only `down` path; `--force` / `<NAME>_FORCE=true` keep re-create meaning and win over `INTERACTIVE`), the nested "cannot converge onto a running stack" case list (traefik static args/ACME, nextcloud admin password, concourse/planka/forgejo volume-bound credentials, vllm/vllm-omni/colqwen model args, excalidraw bare `docker run` args) with each printed remedy, plus the **`Never `exit 0` silently on an existing stack`** bullet
- [x] **`AGENTS.md`** — "Re-run policy (converge by default)" section next to the `--help` rule; **`README.md`** — two-line policy summary in "How It Works"
- [x] **setup-traefik.sh** — silent `exit 0` skip deleted → converge (running or stopped-with-file); prompt defaults to converge (`y` only path that runs `down`); CF_DNS_API_TOKEN + dashboard password read back from the existing `.env`/`.credentials` before any (re)generation; rendered config (compose + `traefik.yml` + `.env`, `# Generated` lines stripped) hashed to `${TRAEFIK_HOME}/.converge-hash` after the health gate and compared on the next run — divergence prints the mode/ACME remedy (`up -d --force-recreate traefik`, else `$0 --interactive`) and exits 0 without touching the stack; old ASCII diagram replaced by the converge summary
- [x] **setup-concourse.sh** — non-interactive `error` → converge (stored `.env` credentials reused to match the persisted postgres volume); `[c/N]` prompt behind `INTERACTIVE`; the volume wipe stays interactive-only behind the `y` re-create; RSA keys preserved as before
- [x] **setup-forgejo.sh** — non-interactive `error` → converge; `POSTGRES_PASSWORD` read back from the existing compose when not set explicitly (default `changeme` skipped), so re-runs keep DB auth against the persisted volume; explicitly changed password prints the `psql ALTER USER` remedy + `$0 --interactive` and exits 0 (gated on `DB_TYPE != sqlite`)
- [x] **setup-nextcloud.sh** — `trap - EXIT` disarm + `error` deleted → converge (stored secrets reused); admin password is first-install-only, so an explicitly changed `NEXTCLOUD_ADMIN_PASSWORD` prints the `occ user:resetpassword` remedy + `$0 --interactive` and exits 0 (nothing modified); `STACK_CREATED_THIS_RUN` now only set on the confirmed re-create path
- [x] **setup-openwebui.sh** / **setup-planka.sh** — `trap - EXIT` + `error` → converge (secrets from the existing `.env` reused, tickets 05/06); `[c/N]` prompt behind `INTERACTIVE`
- [x] **setup-omnigent.sh** — `trap - EXIT` + `error` deleted; the **unconditional `down --remove-orphans` in the normal flow deleted**; `--pull always` moved to the re-create path (plain re-runs no longer depend on the registry); port-conflict check no longer false-positives on the stack's own running container (`docker compose ps -q` self-check)
- [x] **setup-monitoring.sh** — `trap - EXIT` + `error` → converge; `MONITORING_FORCE=true` keeps re-create meaning and wins over `INTERACTIVE`; `[c/N]` prompt behind `INTERACTIVE`
- [x] **setup-excalidraw.sh** — running container: args compared against what this run would create (image; traefik router rule label, or host port via `docker port`) — match → "converged (nothing to do)" + exit 0; diff → every difference + `docker rm -f` + the exact `docker run` line + `$0 --interactive` hint, exit 0; new `--interactive` flag gates the stop/re-create (stopped-container auto-start kept)
- [x] **setup-vllm.sh** / **setup-vllm-omni.sh** — `Nothing to do.` + `exit 0` replaced by converge: reuse-first for all model args (explicit env/CLI wins, else stored `.env` value, reused keys printed), new `--interactive` flag (`c/N` prompt; `--force` keeps `down` + re-create and wins over `INTERACTIVE`), rendered `.env`/compose hashed to `.converge-hash` after the health gate — model-arg divergence on a running stack prints `cd ${PROJECT_DIR} && docker compose up -d --force-recreate` + `$0 --force` and exits 0
- [x] **setup-colqwen.sh** — silent "project exists" `exit 0` removed; new `--interactive` flag + converge step for an existing project: re-render (5 model args reuse-first from `.env`), `docker compose up -d`, ticket-08 health gate (`COLQWEN_HEALTH_TIMEOUT`, default 600 s), hash to `.converge-hash`; model-arg divergence prints the `--force-recreate` remedy + `$0 --interactive` and exits 0; summary now reports CONVERGED vs fresh next-steps
- [x] **setup-n8n.sh / setup-netbird.sh / setup-hermes.sh** — already converge (ticket's table: "only touch `--help`"); `--help` gained a "Re-run policy (converge by default)" note, no behavioural change
- [x] **setup-opencode-server.sh** — untouched (converges already; its inline failure trap is ticket 09's)
- [x] **`tests/machine-config.test.yml`** — `MONITORING_FORCE: "true"` removed (the non-interactive refusal it worked around is gone; re-runs converge) and the stale comment replaced
- [x] **`--help` + header flag comments** updated in every touched script: `--interactive` documented as "Offer tear-down/re-create of an existing stack (default: converge)" (plus "prompt on other risky conditions" where the flag gates those too)

### Validation
- [x] Ticket AC greps: `grep -rn 'Existing .*stack detected' tasks/*.sh` → empty; `grep -rn 'already running — skipping setup' tasks/*.sh` → empty; `grep -rn 'compose down' tasks/*.sh` → only `--force`/interactive-`y` branches, ticket-09 failure-cleanup traps, and help/summary text (no non-interactive-reachable `down`)
- [x] `shellcheck` clean on all 15 touched scripts + `bash -n tasks/*.sh` clean repo-wide; `yamllint tests/machine-config.test.yml` clean; every touched `--help` exits 0 and mentions converge (12/15 also document `--interactive` — n8n/netbird/hermes have no such flag by design)
- [x] **Stub harness (fake `docker`/`sudo`/`curl`, stateful, dev box)** — 30+ scenario checks, all pass: traefik fresh/no-op-re-run/divergent-re-run (`up -d --force-recreate` remedy, no `up -d`/`down` calls, exit 0)/`--interactive y` (down+recreate)/stopped-stack (converge restarts); vllm + vllm-omni fresh (hash saved)/no-op (reuse-first printed, hash match, no recreate)/divergent (remedy, exit 0)/`--force` (down+recreate)/`--interactive c` (converge, no down); nextcloud same-password converge / changed-password remedy (`occ user:resetpassword`, exit 0) / unset-password reuse; forgejo postgres fresh/reuse (stored pw kept in re-rendered compose) / changed-pw remedy (exit 0, compose untouched) / sqlite no-false-positive; excalidraw match (converged exit 0, no `docker run`) / port diff (remedy) / `--interactive y` (stop+rm+run); omnigent fresh (no unconditional `down`) / re-run (converge, no `--pull always`); monitoring re-run (converge) / `MONITORING_FORCE=true` (down+recreate); concourse no-op (converge) / `y`+no-wipe (down without `-v`); colqwen fresh / stopped-project converge (health gate + hash) / model-change remedy
- [x] **VM acceptance (fresh Ubuntu 26.04 `resolute` VM via virt-runner, ticket's verification block)**: `./run-setup.sh apply --config tests/machine-config.test.yml` run A → rc=0, 8/8; run B (second consecutive, fresh session) → rc=0, 8/8; `docker ps` names/state/image identical between the two runs (diff clean; container IDs unchanged — traefik converged in place, "All 2 container(s) up and healthy"); run B log shows `Existing Traefik stack is running — it will be converged (no tear-down)`. VM destroyed after verification (`mas-vmtest-t12-20260830-210907`)

### Notes / assumptions
- The first VM `apply` attempt failed in `setup-docker` ("permission denied … docker.sock") because the script's own post-install `docker info` runs in the same session that just gained the `docker` group — a fresh SSH session makes it pass. Pre-existing session-scoping behaviour of `setup-docker` (out of scope); the two AC runs both start from fresh sessions.
- `n8n`/`netbird`/`hermes` have no `--interactive` flag (no prompts in those scripts), so their `--help` notes document the converge policy without the flag — the ticket's per-script table scopes them to "`--help` only, no behavioural change", which wins over the general AC wording.
- `setup-forgejo.sh` pre-existing bug found and fixed while testing: `lib/helpers.sh` was only sourced when `FORGEJO_TRAEFIK=true`, so ticket 08's unconditional `wait_for_healthy` health gate crashed non-Traefik runs (`command not found`); the source is now unconditional (helper is idempotent, script colors kept).
- `setup-excalidraw.sh`: the host-port comparison now matches `docker port`'s real output format (`0.0.0.0:5005->80/tcp` — host port followed by `->`, not end-of-line); the original `:PORT$` grep could never match.
- `setup-omnigent.sh`: `RECREATE` is now initialised (`false`) before the existing-stack block — the later `--pull always` decision references it, and `set -u` would have crashed fresh installs.
- Concourse's optional postgres volume wipe is the only remaining `down -v` in `tasks/` — interactive-only, as the ticket requires.
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–11 were closed.

## 2026-08-30T23:21:18+02:00 - worker (ticket 14)

### Implemented: Docker post-install steps fixed — no `newgrp`, `$USER`-independent `usermod`, usable-install early exit, non-fatal smoke test (ticket `14-docker-install-post-steps`)

- [x] **`tasks/setup-docker.sh` early exit** — `command -v docker && docker --version` alone accepted a host with Ubuntu's `docker.io` and no Compose plugin (or a stopped daemon): the host "passed" and all 15 compose-based task scripts failed later. Condition extended to `&& sudo docker compose version &>/dev/null && sudo docker info &>/dev/null` (success message now "Docker is already installed **and usable**"). `sudo` prefix because a fresh group member cannot query the daemon before re-login; if only Compose or the daemon is missing the script falls through to the idempotent apt install, which ships `docker-compose-plugin` in `DOCKER_PACKAGES`
- [x] **`usermod` no longer assumes `$USER`** — new `RUN_USER="${USER:-$(id -un)}"` and `sudo usermod -aG docker "${RUN_USER}"`; with `USER` unset (some `sudo -E`/cron invocations) the old line killed the script with `set -u` *after* apt had already modified the system. Membership is now checked against the group DB (`id -nG "${RUN_USER}" | tr ' ' '\n' | grep -qx docker`) instead of the current shell's credentials, so the just-added case no longer re-runs `usermod` every time and the message states the truth: `Added <user> to docker group - re-login required for unprivileged docker to work`
- [x] **`newgrp docker` deleted** — it spawned a shell fed by the script's own stdin, i.e. a hang under `ssh host ./script.sh` / `run-setup.sh apply` / the VM harness (previous run: `setup-docker` integration `rc=124` at the 1800 s per-script timeout, `tests/reports/vmtest-20260827-145344/`). The whole `if id -nG | grep -q docker` block is gone; no interactive primitive remains in the script
- [x] **smoke test guarded and leak-free** — bare `docker run hello-world` → `if sudo docker run --rm hello-world >/dev/null 2>&1; then success ... else warn ...; fi`: a host without egress (or a stopped daemon) now ends in `[WARN] Docker smoke test failed (network or daemon issue?) - install completed; verify with: sudo docker info` and exit 0 instead of failing a completed install, and `--rm` stops leaving a hello-world container behind on every run
- [x] **header + `--help` in sync** — `Behaviour:` block added to both (`-` already installed and usable → exits 0; `-` otherwise the idempotent apt install runs, then group membership, then a smoke test that only warns`;` and "After install, group membership needs a re-login; no interactive shell is spawned"); no new flags and no new environment variables, so the `Options:`/`Usage:` lists stay as they were
- [x] **no other files touched** — nothing in `lib/` was needed (the message/flow helpers `step`/`info`/`success`/`warn` already exist), no templates involved, `README.md` and the skill docs left alone (see notes)

### Validation
- [x] **Ticket acceptance greps** — `grep -n newgrp tasks/setup-docker.sh` → empty; `grep -n 'usermod -aG docker "${USER}"'` → empty; early-exit condition contains `sudo docker compose version` and `sudo docker info` (line 98); the only `docker run` is the guarded `sudo docker run --rm hello-world` (line 165)
- [x] **Static checks** — `shellcheck tasks/setup-docker.sh` clean (0 findings), `bash -n tasks/setup-docker.sh` clean, `./tasks/setup-docker.sh --help` exits 0 (`GNU bash, version 5.2.21(1)-release`); `tests/lint.sh` → `lint guards: PASS` (baseline unchanged)
- [x] **Stub harness (dev box, PATH override with fake `sudo`/`docker`/`apt`/`apt-get`/`usermod`/`groupadd`/`getent`/`install`/`curl`/`dpkg`, real script + real `lib/helpers.sh`, `timeout` guarded)** — 8 scenarios, all as expected: (A) usable install → early exit, zero apt calls; (B) `docker compose version` failing → no early exit, apt path runs and installs `docker-compose-plugin`; (C) `docker info` failing → no early exit; (D) `--force` → check skipped; (E) `RUN_USER` already in `docker` → `already in docker group`, no `usermod` call; (F) not a member → one `usermod -aG docker <user>` + re-login hint, failing smoke test → `[WARN]` and rc=0; (G) run with `env -u USER` → `Added root to docker group` (no `set -u` abort); (H) missing `docker` group → `groupadd docker` then `usermod`
- [x] **VM run (the acceptance criterion that used to hang)** — `tests/run-vm-tests.sh --scripts setup-docker` on a fresh Ubuntu 26.04 `resolute` VM (virt-runner, 4 GiB/2 vCPU/30 GiB): `VM TEST SUITE: PASS (3/3 test cases)`; `results.jsonl`: precheck `run-setup.sh status` rc=0 / 0 s, **integration rc=0 / 24 s** (previous suite: rc=124 at 1800 s — the fix is ~75x under the old timeout and reaches the smoke test at all), **idempotency rc=0 / 0 s** with `[OK] Docker is already installed and usable: Docker version 29.7.2, build a7dcaa6` (proves the strengthened exit fires on a converged host). Integration log shows `Added ubuntu to docker group - re-login required for unprivileged docker to work` followed by `[OK] Docker smoke test passed (hello-world).` and no interactive pause. Report: `tests/reports/vmtest-20260830-231146/` (gitignored, not committed); VM destroyed after the run

### Notes / assumptions
- **Not verified on a real `docker.io`-only host**: the ticket's literal verification step (`apt-get remove -y docker-compose-plugin && ./tasks/setup-docker.sh && docker compose version`) was not executed — no disposable host was kept around for it, and the VM used above has the Docker CE stack. The fall-through logic behind that step is covered by stub scenarios B (compose missing → apt path runs, `docker-compose-plugin` installed) and C (daemon unreachable → apt path runs); the early exit is a plain `&&` chain, so a failing probe cannot let it fire.
- `sudo` for both the probes and the smoke test is deliberate: without it, `docker info` / `docker run` fail in the very session that just gained group membership. Consistent with every other privileged step in the script; `run_preflight_checks` already enforces sudo availability.
- Behaviour change on a host where docker is installed but the daemon is *intentionally* stopped: the early exit no longer fires, so the script re-runs the (no-op) apt install, keeps group membership as-is and ends with the `[WARN]` from the smoke test, exit 0. Chosen over the old false "already installed" success; no daemon config is written either way (`daemon.json` tuning / rootless docker stay out of scope).
- The interactive `newgrp docker` hints in `README.md:746` (troubleshooting) and `skills/machine-setup-automation-assistant/SKILL.md:171` were deliberately left untouched: they instruct the operator in an interactive shell, where `newgrp` is legitimate — the ticket scopes the removal to the script, and `README.md:163` ("adds the current user to the `docker` group and verifies the installation") is still accurate.
- Out of scope, untouched as the ticket names: the `chmod a+r` GPG-key comment (`23-repo-hygiene-and-docs.md`, L-9), pinning/verification of the Docker GPG key and repo (`17-supply-chain-pinning.md`), rootless docker / `daemon.json`, and orchestrator-level stdin handling for children (`10-run-setup-cli-correctness.md`, already landed as `stdin=/dev/null` in non-interactive mode).
- Ticket's `**Status**: open` field left untouched, consistent with how tickets 01–12 were closed.
