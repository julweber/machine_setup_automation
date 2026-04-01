The document is written to `/home/verfeinerer/dev/machine_setup_automation/research.md`. Here's what the research uncovered:

---

## Key Findings

### Architecture in One Sentence
Offen is the **orchestration layer** (Docker lifecycle, scheduling, pre/post hooks); Restic is the **storage engine** (deduplication, encryption, versioning). They integrate via offen's `copy-post` lifecycle hook in a custom Docker image that extends offen with restic installed.

### Critical Design Decisions

1. **How they connect**: Build `FROM offen/docker-volume-backup:v2` + install restic. Set the `docker-volume-backup.copy-post` label on the backup container itself to a script that calls `restic backup $COMMAND_RUNTIME_BACKUP_FILEPATH`. Offen injects the tar archive path via that env var.

2. **What NOT to configure**:
   - No offen storage backends (no `AWS_S3_BUCKET_NAME` etc.) — otherwise offen uploads the tar *and* restic uploads it
   - No offen encryption (`GPG_PASSPHRASE`) — restic handles encryption, double-encrypting destroys CDC deduplication
   - No `BACKUP_RETENTION_DAYS` — use `restic forget` instead for richer policy

3. **Two integration patterns**: 
   - **Tar→Restic** (simple): offen creates tar, restic's CDC chunks it — works well, slight dedup penalty
   - **Direct volume→Restic** (optimal): use offen only for stop/start, restic backs up volume directories directly via `archive-pre` hook — maximum dedup, but offen still creates a tiny tar

4. **Error resilience**: offen **always** restarts containers even when hooks fail — designed this way. Restic stale locks need explicit `restic unlock` on startup. Run prune on a separate weekly schedule to avoid locking conflicts with daily backups.

5. **Version requirements**: restic ≥ 0.18.x (CDC security fix, repo v2), offen/docker-volume-backup v2.x, Docker Compose v2+ (secrets support).