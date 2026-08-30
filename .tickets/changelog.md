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
