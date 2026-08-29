# Feature: setup-backup-server — Central Borg Backup Infrastructure

> **Status:** Specification (not yet implemented)
> **Target:** Any Ubuntu server machine (this repo's normal target), plus any other machine as a backup client
> **Defaults grounded in:** a working reference deployment — see Appendix A

## Overview

Turn **one machine** into the central backup server of a fleet and provide a repeatable, automated
way for **other machines** to push **encrypted, deduplicated, incremental backups** into it.

The engine is **BorgBackup** (plain `borg` — see Design Decision 1). Each client machine holds a
*client-side* repo URI pointing at a directory on the server's backup drive (or a local path) and a
systemd timer that runs `borg create` + `borg prune` daily. The server only runs `borg serve`
implicitly through SSH — it is a **dumb storage host**: no scheduling, no plaintext data, no
passphrases ever stored there. Adding a machine to the fleet is one client-side script run; the
server needs no changes.

This feature delivers two idempotent task scripts, following the repo's one-script-per-component
pattern:

| Script | Role | Runs on |
|--------|------|---------|
| `tasks/setup-backup-server.sh` | Storage host: install borg, verify the backup drive, create the repo directory layout, fix group/ownership | the designated server machine |
| `tasks/setup-backup-client.sh` | Backup client: install borg, init its repo (over SSH or local), generate passphrase, install wrapper + systemd timer/service, optionally run the initial full backup | any client machine (and the server itself, in local mode) |

## Requirements

**Server machine**
- Ubuntu 22.04+ (amd64 or arm64) with systemd; verified with `borgbackup` 1.2.x from apt on 24.04
- A backup drive **already mounted and fstab-persistent** at a chosen path (the script verifies, it
  never formats or edits fstab)
- A regular (non-root) user that may write the repos (default: the invoking user)
- SSH reachable by clients on a chosen port with **key-based, passwordless** auth for that user

**Client machine**
- Ubuntu 22.04+ with systemd (any other OS is out of scope, see Future Work)
- Key-based, BatchMode-able SSH access to the server port (remote mode), or local access to the
  repo path (local mode — e.g. the server backing up itself)
- Same borg major.minor as the server (apt on the same Ubuntu release satisfies this by
  construction; the script warns on mismatch)
- Source paths chosen by the operator (the script never picks them silently)

## Architecture

```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐
│  client machine  │  │  client machine  │  │  more clients (later)│
│  (server, dev    │  │  (e.g. laptop)   │  │                      │
│   box, arm64/    │  │                  │  │                      │
│   amd64, ...)    │  │                  │  │                      │
│                  │  │                  │  │                      │
│ borg client      │  │ borg client      │  │  same client script  │
│ systemd timer    │  │ systemd timer    │  │                      │
└──────┬───────────┘  └──────┬───────────┘  └──────────┬───────────┘
       │  encrypted, deduplicated, incremental (only changed chunks after run 1)
       ▼                     ▼                        ▼
┌────────────────────────────────────────────────────────────────────┐
│  backup server  ("dumb" storage host)                              │
│  sshd :<port> → borg serve (implicit)                              │
│  <mount>/               ← backup drive (ext4/xfs/btrfs), fstab     │
│    ├─ <repo-root>/                          ← per-client borg repos│
│    │    ├─ <client-a>/        (repo A)                        │    │
│    │    ├─ <client-b>/        (repo B)                        │    │
│    │    └─ <server-self>/     (repo C, local mode)            │    │
│    └─ <manual-dir>/                           ← manual full dumps  │
└────────────────────────────────────────────────────────────────────┘
```

- **One Borg repository per client** under `<repo-root>/<client>/`. Per-client repos keep keys
  independent (one lost passphrase never endangers another machine's data) and make restores
  self-contained.
- Data is **encrypted client-side** (repokey, AES-256) before leaving the machine; the server
  never sees plaintext, and the passphrase never touches the server.
- After the initial full run, each daily run transfers only new/changed chunks (dedup + `lz4`).
- `<manual-dir>` is reserved for **manual** full dumps (monthly tarballs, raw clones) — a separate,
  non-deduplicated safety net. Not touched by any script in this feature.
- The server can back up its **own** state (home, /srv, docker volumes) into a **local** repo
  using the same client script in local mode (protects against software corruption; drive
  failure needs the offsite copy — see Future Work).

## Files Delivered

| File | Purpose |
|------|---------|
| `tasks/setup-backup-server.sh` | New — server (storage-host) setup |
| `tasks/setup-backup-client.sh` | New — client setup (remote-over-SSH *and* local repo support) |
| `machine-config.yml.example` | Add `setup-backup-server:` and `setup-backup-client:` entries, both `enabled: false` |
| `README.md` | Document both scripts under a new "Backups" section (evolution: server → clients) |
| `CONTEXT.md` | Add "backup-server" / "backup-client" domain terms |
| `skills/machine-setup-automation-assistant/SKILL.md` | Add both scripts to the service-category table |

Generated at runtime on the target host (not committed):

*Client role:*
| Path | Purpose |
|------|---------|
| `~/.config/borg/<client>.pass` | Repo passphrase (mode 0600, owned by backup user; dir 0700) |
| `/usr/local/bin/borg-backup-<client>` | Wrapper: `create` + `prune` (+ `list`, `check`, `restore` subcommands), carries repo URI, paths, exclusions, retention |
| `/etc/systemd/system/borg-backup-<client>.service` | One-shot service running the wrapper as the backup user |
| `/etc/systemd/system/borg-backup-<client>.timer` | Daily, `Persistent=true`, `RandomizedDelaySec=15m` |

*Server role:*
| Path | Purpose |
|------|---------|
| `<repo-root>/`, `<manual-dir>/` | Directory layout (created if missing; existing contents never modified) |

## Design Decisions

| # | Decision | Choice & rationale |
|---|----------|--------------------|
| 1 | Backup engine | **Plain Borg from apt** (`borgbackup`), *not* borgmatic. Rationale: keeps the feature in bash (repo conventions: shellcheck, `lib/helpers.sh`); no extra Python dependency; apt on the same Ubuntu release gives identical borg versions on client and server (the version-pairing constraint is satisfied by construction). borgmatic's main extra value (DB pre-dump hooks) is not needed for a typical Ubuntu-server fleet in v1. |
| 2 | Topology | **Client-push over SSH** (repo URI `ssh://user@server:port/<repo-root>/<client>`, or a local path). Server stays stateless w.r.t. scheduling; a new machine = one client-side script run, zero server changes. |
| 3 | SSH endpoint | Host, port, and user are **configuration** (`BACKUP_SERVER_HOST/PORT/USER`), default port **22**. Use whichever key-based port is reachable on the target network (some machines only expose a non-standard or internet-forwarded port — set `BACKUP_SERVER_PORT` accordingly). |
| 4 | Encryption | `repokey` (key stored with the repo) + `lz4` compression. `repokey` keeps the key with the data (one passphrase to remember) — the right trade-off for personal/small fleets where the repo host is trusted LAN infrastructure. |
| 5 | Passphrase handling | Generated by the client script (32 chars from `/dev/urandom`), written **only** to `~/.config/borg/<client>.pass` (0600), referenced via `BORG_PASSPHRASE_FILE`. **Never printed** by default (opt-in `--show-passphrase`), never logged to the journal, never transmitted. The operator is instructed to move it to a password manager. The passphrase file must not be placed inside any backed-up path. |
| 6 | Scheduling | **System-level systemd timer** (not user unit, not cron): runs without login, `Persistent=true` fires a missed run (machine off/lid closed) after boot, `RandomizedDelaySec=15m` spreads load. Service unit runs as the regular backup user (`User=`), not root. |
| 7 | Unit/wrapper generation | **Inline heredocs** in the script (precedent: `setup-vllm-omni.sh`) — repo URI, paths, exclusions and retention are strongly conditional per machine. Wrapper is generated per client; the unit stays trivial (`ExecStart=/usr/local/bin/borg-backup-<client> create`). |
| 8 | Retention (prune) | `--keep-daily=7 --keep-weekly=4 --keep-monthly=12` default, all overridable. Prune runs immediately after each successful create, same archive-name prefix. |
| 9 | Archive naming | `<client>-%Y-%m-%dT%H:%M:%S` — sortable, unique, prunable by prefix. |
| 10 | Paths | **No silent default scope.** `BACKUP_PATHS` is required (flag or env) — failing fast beats accidentally backing up the whole disk. Recommended scopes per machine type live in the Rollout section. |
| 11 | `--one-file-system` | On by default (skip bind mounts / `/snap` / docker overlay mounts under the paths), overridable off. `--exclude-cache` always on. |
| 12 | Local repo support | The client script accepts a plain local path as repo location (used for the server backing up itself, or any machine with its own spare drive): `BACKUP_SERVER_HOST` empty → local mode. |
| 13 | Server script scope | Install + verify + layout + group/ownership only. It never formats, never edits fstab (the drive mount must pre-exist — verified state), never deletes data. |
| 14 | Idempotency | Re-runs skip completed work: borg present → skip; drive mounted → verify only; repo exists → do **not** re-init, instead verify the stored passphrase opens it (`borg list`); passphrase file exists → keep; units exist → regenerate + `daemon-reload` (config is derived, safe to overwrite); timer enabled → leave. |
| 15 | `--check` mode | Both scripts get `--check`: report status (install, mount, repo health, timer state, last run result, latest snapshot) and exit non-zero on problems. Intended for future monitoring integration. |

## Environment Variables

All tunables are env vars with defaults at the top of the script (repo convention); CLI flags
mirror them (`--help` lists both).

### `setup-backup-server.sh`

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_MOUNT` | `/media/backups` | Mount point of the backup drive (must already be mounted & fstab-persistent) |
| `BACKUP_REPO_ROOT` | `${BACKUP_MOUNT}/automatic` | Root for per-client borg repos |
| `BACKUP_MANUAL_DIR` | `${BACKUP_MOUNT}/manual` | Manual-dump dir (created if missing, never modified) |
| `BACKUP_GROUP` | `backups` | Group with write access to the mount; `BACKUP_USER` is added to it (created if missing) |
| `BACKUP_USER` | current user | Regular user that must be able to write repos |
| `BACKUP_MIN_FREE_GB` | `100` | Warn if the drive has less free space |

### `setup-backup-client.sh`

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_CLIENT_NAME` | `$(hostname)` | Repo dir name & archive prefix (`[a-z0-9-]` only) |
| `BACKUP_SERVER_HOST` | *(empty)* | Server address. **Empty = local repo mode** (Decision 12); non-empty = remote SSH mode |
| `BACKUP_SERVER_PORT` | `22` | SSH port on the server (Decision 3) |
| `BACKUP_SERVER_USER` | current user | SSH user on the server (must have key-based, passwordless SSH from the client) |
| `BACKUP_REPO_PATH` | `/media/backups/automatic` | Server-side parent dir; final repo = `<BACKUP_REPO_PATH>/<client>/`. Should match the server's `BACKUP_REPO_ROOT` |
| `BACKUP_PATHS` | *(empty → required)* | Space-separated source paths (e.g. `/home/user /etc /srv`) |
| `BACKUP_EXCLUDE_REGEXES` | see below | Newline/space-separated borg `--exclude` regexes, appended to built-ins |
| `BACKUP_KEEP_DAILY` / `BACKUP_KEEP_WEEKLY` / `BACKUP_KEEP_MONTHLY` | `7` / `4` / `12` | Prune retention |
| `BACKUP_COMPRESSION` | `lz4` | `lz4` or `zstd` |
| `BACKUP_ONE_FILE_SYSTEM` | `true` | Pass `--one-file-system` to create |
| `BACKUP_RUN_INITIAL` | `false` | `true`/`--initial`: run the first (full) backup synchronously at setup time |

Default `BACKUP_EXCLUDE_REGEXES` (re-downloadable / regenerable on a typical Ubuntu machine):

```
(^|/)snap/
(^|/)node_modules/
(^|/)\.cache/
(^|/)\.npm/
(^|/)\.cargo/registry/
(^|/)\.rustup/
```

Always on (not in the regex list): `--exclude-cache`. Append machine-specific regexes via
`BACKUP_EXCLUDE_REGEXES` (example in Appendix A).

## Behaviors

### Behavior 1: Server setup (`setup-backup-server.sh`)

Happy path:
1. Verify running as root (sudo) and systemd present.
2. Install `borgbackup` if not installed (`apt-get`), report version.
3. Verify `${BACKUP_MOUNT}` is a mounted filesystem (`findmnt`), ext4/xfs/btrfs, and present in
   `/etc/fstab` (persistent). Print size / free space; **warn** if free < `BACKUP_MIN_FREE_GB`.
4. Ensure `${BACKUP_GROUP}` exists (create if missing) and add `BACKUP_USER` to it
   (`usermod -aG`).
5. Create `${BACKUP_REPO_ROOT}` and `${BACKUP_MANUAL_DIR}` if missing; chown to
   `BACKUP_USER:${BACKUP_GROUP}` mode `775`; verify `BACKUP_USER` can `stat` (and write a
   temp file into) `${BACKUP_REPO_ROOT}` — covers both `root:group` and `user:user` mount
   ownership layouts.
6. Print summary: repo root, free space, and how to add a client (exact client-script invocation).

Error cases:
| Case | Behavior |
|------|----------|
| Mount missing / not in fstab | **Abort** with message: mount the drive & add fstab entry first (script never does this itself) |
| Drive not present at all | Abort, list attached disks for diagnosis |
| `BACKUP_REPO_ROOT` exists with unexpected ownership | Warn + chown to `BACKUP_USER:${BACKUP_GROUP}` (never delete) |
| Not root | Abort with `sudo ./tasks/setup-backup-server.sh` hint |

`--check`: report install/version, mount+free space, group membership, dir layout; exit 0 only if
all green.

### Behavior 2: Client setup (`setup-backup-client.sh`)

Happy path (remote mode, first client run):
1. Verify `BACKUP_CLIENT_NAME` charset; require `BACKUP_PATHS` (every path must exist).
2. Install `borgbackup` if missing.
3. **SSH preflight** (remote mode): `ssh -o BatchMode=yes -o ConnectTimeout=10 -p PORT USER@HOST
   true`. On failure **abort** with instructions (copy key / `ssh-copy-id`, check port).
   Additionally verify the server's borg version (`ssh ... 'borg --version'`) and warn on major
   mismatch.
4. Resolve repo URI: remote → `ssh://USER@HOST:PORT/REPO_PATH/CLIENT/`; local mode →
   `REPO_PATH/CLIENT/`.
5. **Repo init** (idempotent): if `borg list` succeeds with the local passphrase file → skip.
   Else if `borg init -e repokey -C <comp> <repo-uri>` succeeds → generate passphrase, write
   `~/.config/borg/<client>.pass` (0600), `chmod 700 ~/.config/borg`.
   Else (init failed because repo already exists but passphrase is wrong/missing) → **abort**
   with explicit message: "repo exists but stored passphrase does not open it — restore the
   passphrase file from your password manager, then re-run".
6. Write the wrapper `/usr/local/bin/borg-backup-<client>` (heredoc; 0755) containing: repo URI,
   `BORG_PASSPHRASE_FILE` path, paths, excludes, compression, retention; subcommands:
   - `create` — `borg create --one-file-system --exclude-cache --exclude ... --stats
     <repo>:<client>-%Y-%m-%dT%H:%M:%S <paths...>` then `borg prune --prefix <client>- --keep-...`
   - `list` — `borg list <repo>` (latest 20 snapshots)
   - `check` — `borg check <repo>` (metadata; `--read-data` if `--full` passed)
   - `restore <snapshot> [paths...] [dest/]` — `borg extract <repo>:<snapshot> ...` into a
     destination dir (default `./restore-<client>-<date>`); **never extracts in place by default**
7. Write `.service` (`User=`, `ExecStart=... create`, `Nice=10`, `IOSchedulingClass=best-effort`)
   and `.timer` (`OnCalendar=daily`, `Persistent=true`, `RandomizedDelaySec=15m`);
   `systemctl daemon-reload`; `systemctl enable --now borg-backup-<client>.timer`.
8. Print summary: repo URI, passphrase file path (with "move to password manager" warning), timer
   state, and the exact restore command for the latest snapshot.
9. If `--initial`: run the wrapper `create` in the foreground (for large source sets this takes a
   long time — print a warning before starting) and fail setup on error.

Error cases:
| Case | Behavior |
|------|----------|
| `BACKUP_PATHS` empty or a path missing | Abort with usage |
| SSH BatchMode fails | Abort + key-setup instructions (for the configured port) |
| Repo exists, passphrase missing/wrong | Abort with restore-the-passphrase message (step 5) |
| Client/server borg major version mismatch | Warn loudly, proceed only with `--force-version-mismatch` |
| Timer already active from older setup | Regenerate units, `daemon-reload`, keep timer state |
| Local mode + repo parent missing | Create parent dir (local drive is the operator's own; allowed) |

### Behavior 3: Daily runtime (wrapper `create`)

- Runs as `BACKUP_USER` via the system service (no root needed).
- Success = archive created **and** prune completed. Journal output via systemd
  (`journalctl -u borg-backup-<client>`).
- Failure modes handled by Borg itself (remote lock held by another run → exit with error;
  journal shows it). The wrapper adds: `--show-version` line at start, non-zero exit on any
  failure, no `--progress` (systemd context).
- Stale locks: documented `borg break-lock` recovery in the wrapper header comment (manual, not
  automated — break-lock on a *live* server is dangerous).

### Behavior 4: Verification / `--check` (client)

Report, exit non-zero on first failure:
1. borg installed (version); 2. passphrase file exists (0600); 3. repo reachable —
   `borg list` works; 4. timer `active` + `systemctl list-timers` next elapse; 5. last service
   run status (most recent result); 6. latest snapshot name/size/time;
   7. (optional `--full`) `borg check --read-data` (slow — reads all data).

## Implementation Plan

> For agentic workers: implement task-by-task; steps use checkbox syntax.
> **Global constraints** (repo conventions): `#!/usr/bin/env bash` + `set -eu`;
> ShellCheck-clean; quote all variables; `[[ ]]` conditionals; non-interactive unless
> `--interactive`/documented opt-in flags; `--help` on both scripts; env vars with defaults;
> source `lib/helpers.sh` for logging (`step/info/success/warn/error`) and colours; inline
> heredocs for generated units/wrapper; both scripts idempotent; **no machine-specific values
> hardcoded anywhere** (no hostnames, IPs, user names, or paths outside the documented defaults).

### Task 1: `tasks/setup-backup-server.sh`

- [ ] Defaults block: `BACKUP_MOUNT`, `BACKUP_REPO_ROOT`, `BACKUP_MANUAL_DIR`, `BACKUP_GROUP`,
      `BACKUP_USER`, `BACKUP_MIN_FREE_GB`; CLI flags mirror (`--mount`, `--repo-root`,
      `--manual-dir`, `--group`, `--user`, `--min-free-gb`, `--check`, `--help`).
- [ ] Root check; borg install (guard `dpkg -l borgbackup`); version print.
- [ ] Mount verification: `findmnt -n ${BACKUP_MOUNT}`; fstab persistence check by resolved UUID
      (`blkid` → grep `/etc/fstab`); `df --output=size,avail` for free-space warn.
- [ ] Group ensure (`getent group`) + `usermod -aG` (guard: already member).
- [ ] Dir layout create/verify + `chown`/`chmod` (never `rm` anything) + write-permission probe
      for `BACKUP_USER`.
- [ ] `--check` mode; final summary print incl. example client invocation.
- [ ] `shellcheck` clean; `bash -n` clean.

### Task 2: `tasks/setup-backup-client.sh`

- [ ] Defaults block + validation (client-name charset `[a-z0-9-]`, paths exist, remote mode
      needs host, local mode repo parent creatable).
- [ ] Borg install (same guard as server).
- [ ] SSH preflight (BatchMode true + remote `borg --version` parse + major-version compare).
- [ ] Repo init idempotency matrix (Decision 14 step 5) with the three outcomes: skip / init /
      abort-with-passphrase-message.
- [ ] Passphrase generation: `tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32` → file 0600,
      dir 700; `--show-passphrase` opt-in print.
- [ ] Wrapper generation (heredoc): `create`/`list`/`check`/`restore` subcommands per Behavior 3
      + 4; `BORG_PASSPHRASE_FILE` exported in the wrapper, not in the unit.
- [ ] Unit generation (heredocs) + `daemon-reload` + `enable --now` timer.
- [ ] `--initial` foreground first run with long-run warning.
- [ ] `--check` mode per Behavior 4.
- [ ] `shellcheck` clean; `bash -n` clean.

### Task 3: Repo registration & docs

- [ ] `machine-config.yml.example`: add `setup-backup-server:` (enabled: false) and
      `setup-backup-client:` (enabled: false) entries, placed consistently with existing entries.
- [ ] `README.md`: new "Backups" section with both scripts, one-paragraph descriptions,
      evolution note (run server first, then clients), env-var summary tables.
- [ ] `CONTEXT.md`: terms "backup-server" (designated storage machine) and "backup-client"
      (any machine pushing backups).
- [ ] `skills/machine-setup-automation-assistant/SKILL.md`: add both scripts to the
      service-category table.
- [ ] `yamllint` clean on edited YAML.

### Task 4: End-to-end validation on the reference deployment (manual, not code)

- [ ] Server script on the lab server → verify `--check` green.
- [ ] Client script on the first lab client with `--initial` (paths per Rollout) → verify
      `--check`, timer fires.
- [ ] Client script in local mode on the server itself (self-backup) → verify.
- [ ] Client script run manually on an unmanaged machine (laptop) → verify.
- [ ] **Restore test (mandatory before declaring done):** pick 2–3 known files (incl. one file
      deleted from source, recoverable only from an older snapshot) → `restore` into a scratch
      dir → `sha256sum` compare against source → delete scratch. Repeat for the self-backup repo.
- [ ] Wait ≥ 2 daily timer runs; `journalctl` shows clean runs; snapshot count grows.

## Testing

Repo has no bash unit-test framework (parity with other features): verification =
`shellcheck` + `bash -n` + `--help`/`--check` smoke runs + the live validation in Task 4.
Additional manual scenario table:

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| T1.1 | Server script on a machine with a mounted, fstab-persistent drive | Installs borg, creates/verifies layout, green summary, exit 0 |
| T1.2 | Server script with `BACKUP_MOUNT` pointing at an unmounted dir | Abort with fstab/mount instruction, no changes made |
| T1.3 | Re-run server script | All steps "already present/skipped", exit 0 |
| T1.4 | Server script with `BACKUP_USER` set to a different existing user | That user is added to the group, layout owned accordingly |
| T2.1 | Client script where key auth to server:port is not set up | Abort at SSH preflight with ssh-copy-id instructions, no repo created |
| T2.2 | Client script, correct keys, fresh repo | Repo initialized, passphrase file 0600, timer active, exit 0 |
| T2.3 | Re-run client script (repo exists, passphrase present) | Repo skip, units regenerated, timer untouched, passphrase file **not** rewritten |
| T2.4 | Re-run client script after `rm ~/.config/borg/<client>.pass` | Abort with "restore passphrase" message, repo untouched |
| T2.5 | `--initial` with a small path set | Full run completes in foreground, 1 snapshot listed |
| T2.6 | Local mode: repo on a local path, no host configured | Repo created locally, same wrapper/timer behavior |
| T3.1 | Small file change + manual `create` | Second snapshot; transferred bytes ≪ snapshot size (dedup working) |
| T3.2 | Two overlapping runs (lock) | Second run fails cleanly with lock message in journal; first completes |
| T3.3 | `prune` after > 8 `create` runs (shortened retention for test) | Retention honored (test values applied) |
| T4.1 | `restore` of 3 files incl. one only present in an older snapshot | Files match source byte-for-byte (sha256sum) |
| T4.2 | `--check` after all of the above | All green, exit 0 |
| T4.3 | `--check` with timer disabled | Non-zero exit, clear line pointing at the timer |

## Out of Scope / Future Work

Explicitly **not** in v1 (each is a candidate follow-up feature):

1. **Append-only / immutability mode** on the server repos (ransomware hardening: server-side
   read-only repo dir after init, `--append-only` creates; trade-off: `prune` must be handled
   via a scheduled privilege bump or a separate pruning repo layout).
2. **Dead-man's-switch monitoring** — Healthchecks.io ping from the wrapper (alert if a backup
   stops firing, not just errors); the `--check` modes are the hook for this.
3. **Offsite copy (the "1" of 3-2-1)** — the server is typically LAN-only; consider a nightly
   `borg replicate` to a cold drive or a remote S3/B2 target. Until then the strategy is
   effectively 2-2-0.
4. **Web GUI / fleet dashboard** — BorgBackup Server (BBS) if > 5 machines or non-Linux clients
   appear.
5. **Docker-volume consistency** — stopping containers pre-backup for stateful volumes (volumes
   can be included but are not quiesced in v1; acceptable for most services, note per service at
   rollout).
6. **Windows/macOS clients** — Borg runs on both (Windows natively, macOS via Homebrew); the
   client script would need a port, or a restic/kopia sibling feature.
7. **Server drive failure / replacement runbook** — re-init drive, `borg init` each repo, restore
   latest snapshot per client; document when the offsite copy exists.

## Rollout

Order: **server first, then clients** (any machine, in any order afterwards).

1. **Server machine**: `sudo ./tasks/setup-backup-server.sh` (defaults are fine if the drive is
   at `/media/backups`; otherwise set `BACKUP_MOUNT` and friends). Verify with `--check`.
2. **Each client machine**: ensure key-based SSH to the server's backup port, then
   `sudo ./tasks/setup-backup-client.sh --host <server> --port <port> --user <user>
   --paths "<paths>" [--initial]`. Move the generated passphrase to a password manager.
3. **Server self-backup** (recommended): run the client script on the server in local mode
   (`--host ""`, `BACKUP_REPO_PATH` matching the repo root).
4. **Restore test** per Task 4 before declaring the setup done.

Recommended `BACKUP_PATHS` per machine type (operator picks; nothing is default):

| Machine type | Recommended paths |
|--------------|-------------------|
| Ubuntu server (services) | `/home/<user> /etc /srv /var/lib/docker/volumes` (include docker volumes only if Docker is in use; volumes are not quiesced — Future Work 5) |
| Developer workstation | `/home/<user>` with the default excludes; add re-downloadable toolchain/model-binary dirs to `BACKUP_EXCLUDE_REGEXES` |
| Laptop | `/home/<user>` with the default excludes (first run can be large — use `--initial` deliberately) |

## References

- Borg docs: https://www.borgbackup.org/docs/usage.html (`borg init/create/prune/check/extract`,
  remote repositories, `BORG_PASSPHRASE_FILE`, `--one-file-system`, `--append-only`)
- Repo conventions: `specification/project/conventions.md`; pattern precedents:
  `specification/features/vllm-omni-setup/`, `tasks/setup-llama-swap.sh`
