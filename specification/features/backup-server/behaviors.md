# Feature: Backup Server

## Overview

A standalone utility tool for backing up and restoring an AI development server. The backup solution uses a **hybrid architecture** combining two open-source tools:
- **offen/docker-volume-backup**: Orchestration layer (Docker lifecycle, container stop/start, volume extraction)
- **restic**: Storage engine (CDC deduplication, AES-256 encryption, versioning, multi-backend storage)

This combination provides Docker-aware backup orchestration with enterprise-grade incremental deduplication and retention management.

---

## Architecture & Integration Strategy

### Tool Responsibilities
| Layer | Tool | Responsibilities |
|-------|------|------------------|
| **Orchestration** | offen/docker-volume-backup v2.x | Container lifecycle (stop/start), volume discovery, tar archive creation, pre/post hooks |
| **Storage Engine** | restic ≥ 0.18.x | CDC deduplication, AES-256 encryption, repository management, retention policies (`forget` command) |

### Integration Pattern
1. **Backup Flow**: 
   - Offen extracts Docker volumes to temporary tar archives (using `archive-pre` hook)
   - Restic ingests these archives via `copy-post` hook for deduplicated storage
   - Restic repository stored in configured targets (local, S3, SSH, etc.)
2. **Restore Flow**:
   - Restic extracts archived data to temporary location
   - Offen restores data back into Docker volumes and restarts containers

### Configuration Mappings
- **NO Offen storage backends**: Only restic handles final storage (avoid double-upload)
- **NO Offen encryption**: Restic's AES-256 provides encryption at rest (double-encrypting destroys CDC deduplication)
- **Retentions managed by restic**: Use `restic forget` instead of Offen's `BACKUP_RETENTION_DAYS`

### Version Requirements
- `offen/docker-volume-backup`: v2.x+
- `restic`: 0.18.x+ (CDC security fix, repo v2)
- `Docker Compose`: v2+ (secrets support)

---

## Behavior 1: Full Component Backup

### Description
Creates a complete backup of all configured data sources including Docker volumes, service configurations, and server directories to one or more target locations.

### Happy Path
1. Tool reads configuration from `backup-config.yaml` using `yq` for YAML parsing
2. Discovers all Docker volumes using Offen's volume discovery mechanism (via Docker labels or explicit config)
3. Cross-references discovered volumes with known service directories (`/srv/*`, `$HOME/<service>`)
4. For each configured component:
   - Uses Offen to extract Docker volume to temporary tar archive
   - Calls `restic backup` for EACH target location independently (Option B strategy)
   - Each target receives its own snapshot tagged with component name and timestamp
   - Restic stores deduplicated data in configured target locations (local/S3/SSH/etc.)
   - Restic computes SHA256 checksums for all chunks
   - Writes local manifest entry tracking ALL snapshot IDs (one per target)
5. Runs `restic forget` with per-target retention policies via `--keep-weekly`, `--keep-daily`, etc.
6. Outputs summary to stdout: total components backed up, aggregate size, duration, target locations
7. Returns non-zero exit code if any component or target failed

### Error Cases (Fail Fast Strategy)
- **Docker daemon not running**: Exit immediately with clear error message suggesting `systemctl start docker`
- **Target location unavailable** (external drive unmounted, network share disconnected): Skip that target, log warning, continue with remaining targets
- **Permission denied on source directory**: Mark component as "partial backup" in manifest with warning flag; continue with other components
- **Disk space exhausted during archive creation**: Rollback all files for that component's backup, mark component as failed, exit non-zero

### Edge Cases
- **Docker volume actively in use** (files being written): Attempt consistent backup; if files change mid-archive, warn user about potential inconsistency and proceed with best-effort snapshot
- **Large files (>10GB)**: Show real-time progress indicator with percentage complete; allow Ctrl+C to cancel current component backup (will rollback that component's partial archive)
- **Symbolic links in source paths**: Preserve symlinks as-is in archive, do not follow unless explicitly configured

---

## Behavior 2: Incremental Component Backup (via Restic CDC)

### Description
Performs file-level incremental backup by detecting changes since the last backup. Restic's Content-Defined Chunking automatically handles incrementality.

### Happy Path
1. Tool queries restic repository for existing snapshots tagged with component name across all targets
2. For each target location:
   - Calls `restic backup` with source data (Offen extracts volume first)
   - Restic's **Content-Defined Chunking** automatically detects changed blocks
   - Only new/modified chunks uploaded to repository (deduplication happens transparently)
   - Snapshot tagged with component name + timestamp for easy identification
   - Returns unique snapshot ID per target
3. Writes manifest entry tracking all snapshot IDs across targets
4. If `--incremental` flag used, restic automatically skips unchanged blocks; if omitted, still performs CDC-based incremental backup
5. Runs `restic forget` with per-target retention policies



### Error Cases
- **No previous full backup found** for a target: Exit immediately with error suggesting user run `--full` first for that component
- **Incremental chain broken** (parent backup missing or corrupted): Log warning, fall back to full backup for affected components

### Edge Cases
- **Component has excessive changes** (>50% of total files modified since last backup): Warn user that incremental backup is inefficient in terms of space/time, suggest running `--full` backup next cycle
- **Files deleted on source**: Record deletion metadata in incremental manifest to ensure restore operation removes corresponding files from target

---

## Behavior 3: Restore from Backup

### Happy Path
1. Tool reads restic repository configuration and local manifest to identify target snapshot by timestamp/component
2. Calls `restic unlock` at startup to clear any stale locks (critical for multi-run scenarios)
3. For each component in manifest:
   - Determines which target snapshot to restore from (default: first available, or specify via `--source <snapshot-id>`)
   - Calls `restic restore <snapshot-id>` to extract data to temporary location
   - Restic automatically decrypts and decompresses using AES-256 keys from config/ENV
   - Offen restores extracted data back into Docker volumes (preserves permissions via volume mount)
   - Offen restarts associated containers after successful restore
4. Runs `restic check --read-data` for optional full integrity verification (`--verify` flag)
5. Outputs summary: components restored, any warnings about missing files or permission adjustments

### Error Cases (Fail Fast)
- **Checksum mismatch** during verification: Exit immediately with detailed mismatch information
- **Target directory not empty**: In non-interactive mode, exit with error showing existing files; prompt interactively to confirm overwrite
- **Docker volume already exists with data**: Warn user that volume will be overwritten, offer options via flags: `--backup-existing`, `--force-overwrite`, or skip this component

### Edge Cases
- **Restoring to new hardware** (different machine): Adjust absolute paths in configuration if necessary; regenerate SSH host keys if `/etc/ssh` not included in backup and keys are missing on target system
- **Partial backup in manifest** (marked as incomplete from Behavior 1 error case): Restore available files for that component, clearly report gaps to user showing which paths have no data

---

## Behavior 4: Selective Component Backup/Restore

### Happy Path
1. User provides `--components` flag with comma-separated list of component names (e.g., `forgejo,openwebui`)
2. Tool validates that all requested components exist in configuration file or match auto-discovered Docker volumes/service directories
3. For backup: Only processes specified components across ALL targets; generates manifest containing only selected components
4. For restore: Only restores selected components to target locations, leaving all other services untouched

### Error Cases
- **Unknown component name** in `--components` list: Exit immediately with error displaying available components from configuration and auto-discovery results
- **Component not found on source system** (for backup operation): Exit immediately with error unless `--allow-missing-components` flag is set

### Edge Cases
- **User requests component with dependencies** (e.g., OpenWebUI depends on LM Studio data): Warn user about missing dependencies, offer to automatically include dependent components in the backup/restore scope
- **Component partially exists** (some but not all expected directories): Proceed with available paths, mark as "partial" in manifest

---

## Behavior 5: Backup Management Operations

### Description
Provides utilities for listing backups, enforcing retention policies per target, and verifying backup integrity.

### Happy Path (via Restic CLI)

#### List Backups (`--list-backups`)
- Calls `restic snapshots --json` to query all snapshots across configured repositories
- Parses JSON output to display: timestamp, component names, repository location, snapshot size
- Sorts by timestamp descending (newest first) using local tool logic
- Merges results from multiple target locations if configured

#### Cleanup Old Backups (`--cleanup --retention <policy>`)
- Calls `restic forget` for EACH target independently with per-target retention policies from config
- Policies applied: `--keep-weekly`, `--keep-daily`, `--keep-monthly`, `--keep-yearly`
- Restic automatically removes old snapshots while maintaining chain integrity
- Maintains at least one valid full backup as anchor point (restic's built-in behavior)

#### Verify Backup (`--verify --target <location>`)
- Calls `restic check --read-data` on ALL targets (or specified target via flag)
- Restic validates all chunk checksums against stored metadata
- Reports any corruption, missing files, or size mismatches with detailed error codes

### Error Cases
- **No backups found** in target location: Exit immediately with friendly message "No backups found in [location]" with suggestion to run `--full` backup (via `restic snapshots` returning empty)
- **Retention policy would delete all backups**: Keep at least one full backup as anchor point, exit non-zero with warning
- **Restic lock conflict** (another process holding repository): Exit immediately with clear message suggesting `restic unlock`

### Edge Cases
- **Cleanup interrupted mid-way** (Ctrl+C or system crash): Mark partial cleanup state in log file; next cleanup run detects incomplete operation and resumes from last successful state
- **Concurrent backup running during cleanup**: Lock mechanism prevents simultaneous access to same manifest; if lock held, wait with timeout or fail gracefully depending on `--wait` flag

---

## Behavior 6: CLI Interface & User Experience

### Description
Defines the command-line interface design and user experience patterns for the backup tool.

### Happy Path (Pure CLI Interface)
1. Parse command-line arguments using bash getopts in `lib/helpers.sh`
2. Validate argument combinations before execution (e.g., `--restore` requires source, `--incremental` requires existing full backup)
3. Display progress for long-running operations:
   - "Backing up component [name] ([X]% complete)"
   - Real-time throughput indicator (MB/s)
4. Use color-coded output from `lib/helpers.sh`:
   - GREEN (`\033[0;32m`): Success indicators, completed operations
   - CYAN (`\033[0;36m`): Informational messages, progress updates  
   - YELLOW (`\033[1;33m`): Warnings, non-critical issues
   - RED (`\033[0;31m`): Errors, failed operations
5. Log detailed actions to `~/.local/state/backup-tool/<timestamp>.log` with ISO 8601 timestamps
6. Exit codes: 0 = success, non-zero = partial failure or error

### Error Cases
- **Invalid argument combination**: Display usage help showing correct syntax along with specific error explaining the conflict
- **Missing required flag**: Show which flags are mandatory for the selected operation mode

### Edge Cases
- **Non-interactive mode** (scripted execution via `--quiet` or `BACKUP_QUIET=true` environment variable): Suppress color codes, minimal output suitable for parsing by automation scripts
- **Dry-run mode** (`--dry-run` flag): Parse all arguments and validate configuration, display exactly what would happen without making filesystem changes; show estimated total size and time

---

## Proposed CLI Command Structure

```bash
# Full backup to multiple targets
./backup-server.sh --full \
  --config backup-config.yaml \
  --target /mnt/external \
  --target s3://my-backups \
  --encrypt --passphrase-file ~/.secrets/backup.key

# Incremental backup
./backup-server.sh --incremental \
  --config backup-config.yaml \
  --target /mnt/external

# Restore from specific backup
./backup-server.sh --restore \
  --source /mnt/external/backups/2026-04-01T10-30-00 \
  --target /srv \
  --verify

# List all backups
./backup-server.sh --list-backups \
  --config backup-config.yaml

# Cleanup old backups (keep last 4 weeks)
./backup-server.sh --cleanup \
  --config backup-config.yaml \
  --retention "4-weeks"

# Selective component backup
./backup-server.sh --full \
  --components forgejo,openwebui \
  --target /mnt/external

# Dry run to preview operations
./backup-server.sh --full --dry-run \
  --config backup-config.yaml
```

---

## Configuration File Schema (backup-config.yaml)

### YAML Parsing
Configuration is parsed using `yq` command-line tool. Ensure `yq` is available in PATH or documented as dependency.

```yaml

```yaml
# Data sources to backup
sources:
  docker_volumes: true                    # Auto-discover all Docker volumes via Offen
  server_directories:                     # Explicit service directories
    - path: /srv/forgejo
      component_name: forgejo
    - path: /srv/openwebui
      component_name: openwebui
  home_directory_configs:                 # User configurations
    include_patterns:
      - ~/.ssh
      - ~/.config/docker
    exclude_patterns:
      - ~/.cache

# Target locations for backups (Restic repository destinations)
targets:
  - location: /mnt/external/backups
    type: local
    enabled: true
  - location: s3://my-company-backups/server1
    type: cloud
    enabled: true
    credentials_env: AWS_BACKUP_CREDS

# Encryption settings (Restic AES-256)
encryption:
  enabled: true
  method: restic                          # Always restic; Offen's encryption disabled to preserve CDC deduplication
  passphrase_file: ~/.secrets/backup.key
  # Note: GPG/age methods are deprecated in favor of restic's native AES-256

# Retention policy (applied via `restic forget`)
retention:
  full_backup_keep: 4                     # Number of weekly snapshots to keep (--keep-weekly)
  daily_keep: 7                           # Days to keep daily snapshots (--keep-daily)
  monthly_keep: 3                         # Months to keep monthly snapshots (--keep-monthly)
  yearly_keep: 5                          # Years to keep yearly snapshots (--keep-yearly)
  # Policy format examples:
  # - "4-weeks" → --keep-weekly 4
  # - "daily-for-7-days" → --keep-daily 7
  # - Custom JSON: {"keep_last": 10, "keep_hourly": 24}

# Offen-specific settings (orchestration layer)
offen:
  stop_containers_before_backup: true     # Gracefully stop containers before volume extraction
  restart_containers_after_restore: true  # Auto-restart containers after restore
  health_check_timeout: 30                # Seconds to wait for container health checks

# Logging
logging:
  level: info                             # debug, info, warning, error
  log_directory: ~/.local/state/backup-tool
```

## Integration-Specific Notes

### Offen Configuration (via Docker labels)
- Container label `docker-volume-backup.copy-post`: Points to restic backup script
- Container label `docker-volume-backup.archive-pre`: Optional pre-extraction hook
- **Critical**: Do NOT set Offen storage backends (`AWS_S3_BUCKET_NAME`, etc.) — restic handles final storage
- **Critical**: Disable Offen encryption via `GPG_PASSPHRASE` to avoid double-encryption destroying CDC deduplication

### Restic Configuration (via ENV variables)
- `RESTIC_REPOSITORY`: Points to target location (local/S3/SSH)
- `RESTIC_PASSWORD`: Loaded from `passphrase_file` in config
- `RESTIC_CACHE_DIR`: Optional custom cache directory for performance
- **Lock management**: Tool runs `restic unlock` on startup and `restic prune` weekly to reclaim space
