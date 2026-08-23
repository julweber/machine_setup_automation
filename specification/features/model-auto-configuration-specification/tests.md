# Tests: Model Auto-Configuration (Model Catalog Sync)

## Test Strategy Note (v1)
Automated test coverage for this feature is **deferred to a future release** (project test
strategy: bats/VM integration planned). This file documents manual test scenarios to execute
on a target machine before considering the feature done. Static gate: `shellcheck` must pass
on `tasks/sync-models.sh` and all `lib/agent-*.sh` files.

**Static gates (run before all scenarios):**
- `shellcheck tasks/sync-models.sh lib/agent-pi.sh lib/agent-opencode.sh` — no errors/warnings
- `yamllint models.yml.default` — clean

---

## Behavior 1: Pre-flight Checks

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| T1.1 | Run with valid `models.yml.default` (remote-only catalog) on a machine without llama-swap | Exit 0; agent sync proceeds; llama-swap step skipped |
| T1.2 | Run with local models while `/srv/llama-swap/config/config.yaml` is missing | Exit 1, message references `./tasks/setup-llama-swap.sh`; **no** agent files modified |
| T1.3 | Run with `download:` commands while `hf` is not on PATH (e.g. `PATH` without `~/.local/bin`) | Exit 1, message references `./tasks/setup-basics.sh` |
| T1.4 | Run with a syntactically invalid YAML catalog | Exit 1, parse error shown; no mutations |
| T1.5 | Catalog with schema violations: missing `serve.cmd` on local model; `type: remote` with `download:`; duplicate local model names | Exit 1, **all** violations listed (not just the first) |
| T1.6 | Top-level `env` entry named `PORT` (llama-swap reserved macro) | Exit 1, reserved-name error |
| T1.7 | `MODELS_YML=/nonexistent/file.yml` | Exit 1, clear "file not found" |
| T1.8 | No `models.yml`, only `models.yml.default` present | `.default` is used and announced in the log |
| T1.9 | `models.yml` present | `models.yml` is used (not `.default`) |
| T1.10 | Both present + `MODELS_YML` pointing at a third file | `MODELS_YML` file wins |
| T1.11 | Opencode not installed (`~/.config/opencode/opencode.json` missing) | Opencode skipped with a note; pi still synced; exit 0 |
| T1.12 | `--agents pi` while opencode is installed | Only pi touched; opencode config file byte-identical before/after |

## Behavior 2: Downloads

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| T2.1 | First run with a small local model (e.g. a single small GGUF or `config.json`-sized test file) | Dry-run reports N files > 0 → real download runs; file lands under `--local-dir` path |
| T2.2 | Second run, same catalog | Dry-run reports 0 files → `already present, skipping` logged; no network transfer of the file |
| T2.3 | Delete one downloaded file, re-run | Only that file re-downloaded |
| T2.4 | Multi-file model (two `hf download` commands in `download:` list) | Both commands processed independently; per-command present/missing reporting |
| T2.5 | `download:` command with a bad repo id | Command fails, error logged; other models still attempted; exit 2; summary shows failure |
| T2.6 | Interrupted download (kill mid-transfer), re-run | `hf` resumes/completes; no double full download |
| T2.7 | `--local-dir` metadata folder (`.cache/huggingface/` inside the local dir) | Present after download; **not** deleted by the script on any run |
| T2.8 | `${MODEL_DIR}` placeholder in `download:` and in `serve.cmd` | Expanded to the top-level `env` value; `${HOME}` in an env value itself expands to the real home |
| T2.9 | `serve.cmd` contains `${PORT}` and `${llama-server-bin}` | These are **not** expanded by the script; they survive verbatim into `config.yaml` |
| T2.10 | Per-model `env` overrides a top-level env name | Per-model value wins in that model's expansion; other models use the top-level value |

## Behavior 3: llama-swap Sync

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| T3.1 | Add 1 new local model | `models:` gains the key with the expanded `cmd` and `env:` containing the catalog per-model env (e.g. `CUDA_VISIBLE_DEVICES=0`); service restarted once; llama-swap `/v1/models` lists it after load |
| T3.2 | Re-run immediately | Config file **byte-identical** (no reformatting); service **not** restarted |
| T3.3 | Pre-existing hand-tuned model entry (different `cmd` than catalog) with the same key | Entry untouched; `already present, unchanged` logged |
| T3.4 | `macros`, `matrix`, `hooks`, `apiKeys` sections | Present and byte-identical in the modified file after adding models |
| T3.5 | `--no-restart` with a new model added | Config written; no restart; manual `systemctl restart` command printed |
| T3.6 | llama-swap service stopped, run with a new model | Config written; restart **starts** the service; service active after run |
| T3.7 | Corrupted-partial-write simulation (e.g. read-only target or forced `yq` failure) | Original `config.yaml` restored intact; exit 2 |
| T3.8 | Catalog with only remote models | `config.yaml` byte-identical; no restart |
| T3.9 | Pre-existing entry with same key and a different/absent `env` | Entry untouched, including its `env`; `already present, unchanged` logged |

## Behavior 4: Agent Sync (pi)

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| T4.1 | Fresh `models.json` (only `{"providers":{}}`), catalog with 2 providers / 3 models | Both providers created with `baseUrl`/`apiKey`; all 3 models present with defaults applied (`contextWindow: 200000`, `maxTokens: 16000`, `reasoning: true`, `input: ["text"]`) |
| T4.2 | Existing provider `evo` with extra manual model `my-manual-model` | Manual model **preserved**; catalog models added |
| T4.3 | Existing catalog-managed model with a manually changed `contextWindow` | Field corrected to catalog value; `updated contextWindow` logged; other manual fields (e.g. `cost`) preserved |
| T4.4 | Provider exists under same name with a **different** `baseUrl` | `baseUrl` updated to catalog value with a warning |
| T4.5 | `thinkingLevelMap` in catalog | Written into the pi model entry as-is (nulls preserved) |
| T4.6 | Model id present under two different providers in catalog | Both provider entries get the model; no cross-contamination |
| T4.7 | Re-run | `models.json` byte-identical (modulo JSON formatting stability — assert parse-equal via `jq -S` at minimum) |
| T4.8 | Invalid JSON produced (simulated) | Original file restored; exit 2 |

## Behavior 4: Agent Sync (opencode)

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| T4.9 | Fresh/empty opencode config, catalog with providers | Provider(s) + models written in opencode's structure; `jq empty` passes |
| T4.10 | Existing opencode config with unrelated manual entries | Untouched; only catalog providers/models added or fixed |
| T4.11 | Re-run | Config stable (parse-equal), exit 0 |

## Behavior 5: Verification & Summary

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| T5.1 | Successful first run (local + remote models, pi + opencode) | Summary table per component: correct added/already-present counts; exit 0 |
| T5.2 | No-op re-run | All entries "already present"; exit 0 |
| T5.3 | Run with one failing download + successful config sync | Summary shows the failure; exit 2; verification lists the missing model |
| T5.4 | `--help` | Usage text with flags and `MODELS_YML`; exit 0; no side effects |

## Repo Hygiene

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| T6.1 | `git status` after creating a local `models.yml` with a real API key | `models.yml` untracked/ignored; not commit-able; `models.yml.default` tracked |
| T6.2 | `models.yml.default` scanned for real secrets | Only placeholders present |
| T6.3 | `machine-config.yml.example` contains `sync-models` with `enabled: false` | Orchestrator can list the task |
| T6.4 | Fresh clone on a new machine: `./tasks/setup-basics.sh`, `./tasks/setup-llama-swap.sh`, `./tasks/setup-pi.sh`, `./tasks/setup-opencode-server.sh`, then `./tasks/sync-models.sh` | End-to-end: weights downloaded, llama-swap serves a new model, pi + opencode list the models |
