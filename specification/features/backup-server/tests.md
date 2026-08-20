# Tests: Backup Server Feature

## Test Strategy Note (v1)
Automated test coverage for this feature is **deferred to a future release**. This file documents manual test scenarios that should be executed before any deployment. Automated testing via the project's bats framework will be evaluated in a subsequent iteration.

---

## Manual Test Scenarios

### Prerequisites
- Ubuntu target machine with Docker and Docker Compose installed
- At least one running service with Docker volumes (e.g., forgejo, openwebui)
- External storage location or S3 credentials for multi-target tests - can be simulated with local directory

---

## Behavior 1: Full Component Backup

| Test ID | Description | Expected Result |
|----------|--------------|------------------|
| T1.1 | Run full backup with single target (local) | All configured components backed up, manifest written with snapshot IDs |
| T1.2 | Run full backup when Docker daemon is NOT running | Exit immediately with clear error suggesting `systemctl start docker` |
| T1.3 | Run full backup to unavailable target location (unmounted drive) | Warning logged, continue with remaining targets |
| T1.4 | Run full backup with permission denied on source directory | Component marked as "partial" in manifest with warning flag |
| T1.5 | Run full backup with large files (>10GB) - if test volume available | Progress indicator shows percentage complete |
| T1.6 | Run full backup twice, verify second run succeeds (idempotency) | Both runs succeed; second run completes faster due to CDC |

---

## Behavior 2: Incremental Component Backup

| Test ID | Description | Expected Result |
|----------|--------------|------------------|
| T2.1 | Make small file change in backed-up volume, run incremental backup | Only changed chunks uploaded; verify snapshot created with proper tagging |
| T2.2 | Run incremental backup when no prior full backup exists | Exit immediately with error suggesting `--full` first |
| T2.3 | Delete files from source, run incremental backup, then restore and verify deletions are propagated | Deleted files properly removed on restore |

---

## Behavior 3: Restore from Backup

| Test ID | Description | Expected Result |
|----------|--------------|------------------|
| T3.1 | Perform full backup, make changes to volume, then restore | Volume data matches backed-up state exactly; containers restart successfully |
| T3.2 | Run restore with `--verify` flag | `restic check --read-data` runs and reports integrity status |
| T3.3 | Attempt restore when target directory already has files (non-interactive mode) | Exit with error showing existing files |
| T3.4 | Restore to new "hardware" scenario - different absolute paths | Files restored correctly if config adjusted appropriately |

---

## Behavior 4: Selective Component Backup/Restore

| Test ID | Description | Expected Result |
|----------|--------------|------------------|
| T4.1 | Run backup with `--components forgejo,openwebui` and multiple services configured | Only specified components included in manifest; others skipped |
| T4.2 | Provide unknown component name in `--components` list | Exit immediately with error showing available components |
| T4.3 | Request component not found on source system without `--allow-missing-components` flag | Exit immediately with error |

---

## Behavior 5: Backup Management Operations

| Test ID | Description | Expected Result |
|----------|--------------|------------------|
| T5.1 | Run `--list-backups` after creating multiple backups across targets | All snapshots displayed with timestamps, component names, repository locations; sorted newest first |
| T5.2 | Run cleanup with retention policy that would delete all backups | At least one full backup preserved as anchor point; warning issued |
| T5.3 | Run `--verify` on target location | `restic check --read-data` completes and reports any corruption |

---

## Behavior 6: CLI Interface & User Experience

| Test ID | Description | Expected Result |
|----------|--------------|------------------|
| T6.1 | Provide invalid argument combination (e.g., `--restore` without `--source`) | Usage help displayed with specific error explaining the conflict |
| T6.2 | Run in non-interactive mode (`BACKUP_QUIET=true` or `--quiet`) | No color codes; minimal output suitable for scripted automation |
| T6.3 | Run with `--dry-run` flag | All arguments parsed, configuration validated; actions that would be performed are displayed without filesystem changes |

---

## Integration Tests

### Full Workflow Scenarios

| Test ID | Description | Expected Result |
|----------|--------------|------------------|
| IT1 | Complete lifecycle: full backup → modify data → incremental backup → restore from original snapshot | System returns to exact state at time of first backup |
| IT2 | Multi-target backup (local + simulated remote) then verify both locations contain identical snapshots | Both targets have matching snapshot IDs and data |

---

## Test Execution Checklist

Before marking this feature as ready for deployment, verify:

- [ ] All Happy Path tests pass (T1.1, T2.1, T3.1, etc.)
- [ ] Error handling behaves as specified (exit codes match behaviors.md)
- [ ] Idempotency verified: running backup twice produces no errors
- [ ] Multi-target scenarios work when multiple targets configured

---

## Notes for Future Automated Testing

When automated testing is added via the project's bats framework or VM-based integration tests:

1. **Focus on Happy Paths first** - automated coverage of main workflows provides highest value
2. **Idempotency should be automated** - run entrypoint twice, verify no errors second time
3. **Mock external targets** - for CI/CD, use local directory as mock S3/SSH target
4. **Container state verification** - after restore, verify containers are running and healthy (e.g., `docker ps` shows expected containers)
