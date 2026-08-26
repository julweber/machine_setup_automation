# Behaviors — Model Auto-Configuration (Model Catalog Sync)

> **Design basis:** Brainstormed feature spec (2026-08-23). Grounded in the actual on-disk state of
> `tasks/setup-llama-swap.sh`, `tasks/setup-pi.sh`, `tasks/setup-opencode-server.sh`,
> `/srv/llama-swap/config/config.yaml`, `~/.pi/agent/models.json`, and the HuggingFace CLI
> (`hf` 1.22.0 — download behavior verified empirically on the target host).

## Overview

This feature adds a **declarative model catalog** (`models.yml`) and a **sync script**
(`tasks/sync-models.sh`) that configure LLMs on an already-provisioned inference server:

1. Download model weight files that are not already present (via the `hf` CLI).
2. Add missing model entries to the **llama-swap** configuration (strictly additive).
3. Wire every catalog model into the **coding agents'** model configuration files
   (**pi**, **opencode**, and future agents via pluggable adapters) — add missing entries,
   fix misconfigured fields.

The script is **idempotent** and **strictly additive** with respect to state it does not own:
it never removes or rewrites entries that were not created from the catalog, and re-running
after a successful run is a no-op.

**Scope boundary:** the script does **not** install llama-swap, pi, or opencode. Those are
assumed to be set up by `tasks/setup-llama-swap.sh`, `tasks/setup-pi.sh`, and
`tasks/setup-opencode-server.sh` respectively. It does not install `hf`/`jq`/`yq`
(installed by `tasks/setup-basics.sh`).

### Files Delivered

| File | Purpose |
|------|---------|
| `tasks/sync-models.sh` | Main sync script (new) |
| `lib/agent-pi.sh` | Pi agent adapter: config path + model.json merge logic (new) |
| `lib/agent-opencode.sh` | Opencode agent adapter: config path + opencode.json merge logic (new) |
| `models.yml.default` | Committed default model catalog in repo root (placeholders only, no secrets) (new) |
| `.gitignore` | Add `models.yml` (contains API keys) (edit) |
| `machine-config.yml.example` | Add `sync-models` entry, `enabled: false` (edit) |
| `README.md` | Document catalog workflow (copy `.default` → `models.yml`, edit, run) (edit) |
| `CONTEXT.md` | Add "model catalog" domain term (edit) |
| `skills/machine-setup-automation-assistant/SKILL.md` | Mention `sync-models` in the task list (edit) |

Generated/modified at runtime on the target host (not committed): `models.yml` (repo root),
`/srv/llama-swap/config/config.yaml` (additive), `~/.pi/agent/models.json` (additive),
`~/.config/opencode/opencode.json` (additive).

### Design Decisions

Numbered to match the brainstorm.

| # | Decision | Choice |
|---|----------|--------|
| 1 | Prerequisites | llama-swap, pi, opencode assumed already set up by existing `tasks/` scripts |
| 2 | Model types | Both **local** (gguf weights downloaded, served by llama-swap) and **remote** (external OpenAI-compatible provider) |
| 3 | Provider grouping | Several models can live under one provider/baseUrl; the catalog has a `providers:` section, each provider with `name`, `baseUrl`, `apiKey`, `models:` |
| 4 | Download mechanism | Always the `hf` CLI; per-model `download:` is a free-form **list of shell commands** (supports multi-file large models) |
| 5 | llama-swap serving command | **Raw `serve.cmd` fully owned by the user** in the catalog (no templating, no default generation) |
| 6 | Template variables | `env:` as `name`/`value` arrays, both **top-level** (inherited by all models) and **per-model** (add/override). Placeholders like `${HOME}`, `${MODEL_DIR}` expanded **at execution time** |
| 7 | Model data location | No dedicated `modelDataDir` key — controlled through `env` (e.g. `MODEL_DIR=${HOME}/.cache/huggingface/hub`, the default in `models.yml.default`) |
| 8 | Agent config mutation | **Merge/additive**: ensure provider exists, add missing models, leave pre-existing entries untouched |
| 9 | llama-swap mutation | **Merge/additive**: add missing model entries only; existing entries and all non-model sections (`macros`, `matrix`, `hooks`, `apiKeys`, global settings) are never touched |
| 10 | Download-once guarantee | `hf download ... --local-dir ${MODEL_DIR}/<repo>` mode: stable authorable paths + built-in idempotency via in-dir `.cache/huggingface/` metadata (default `--no-force-download`). In-dir metadata must be kept. Script runs `--dry-run` first per command to report "already present" vs. "downloading N files (X)" |
| 11 | Agent model metadata | Explicit per-model `agent:` block; optional fields with defaults: `contextWindow: 200000`, `maxTokens: 16000`, `reasoning: true`, `input: [text]`; optional `thinkingLevelMap` |
| 12 | Model identity | One canonical `name` per model, used verbatim as llama-swap model key, agent model id, and display name. For `remote` models, `name` is the upstream model id, used as-is |
| 13 | Agent targeting | **Auto-detect** supported agents by config-file presence (missing agent → skipped with note) **plus optional override** to restrict the set. One **adapter file per agent** in `lib/` (`lib/agent-<name>.sh`); adding a future agent = adding one new file |
| 14 | Script & catalog location | `tasks/sync-models.sh`; catalog resolution: `MODELS_YML` env override → `<repo root>/models.yml` → `<repo root>/models.yml.default`. `models.yml` is gitignored (contains API keys); README instructs copying `.default` → `models.yml` to customize |
| 15 | llama-swap restart | **Only if the config actually changed**; `--no-restart` flag to skip. If the service is not running, the restart starts it |
| 16 | Missing llama-swap + local models | **Fail hard** with message: run `./tasks/setup-llama-swap.sh` first |
| 17 | Missing `hf` + downloads needed | **Fail hard** with message: run `./tasks/setup-basics.sh` first |
| 18 | llama-swap not running | Proceed: download, configure, restart (restart starts the service) |
| 19 | "Well configured" scope | Agent configs: add missing **and** fix managed fields that differ from the catalog. llama-swap: **add-only** — an existing model entry is never modified |
| 20 | Provider matching in agent configs | Existing provider blocks matched **by name** |

### CLI & Environment

```
tasks/sync-models.sh [--no-restart] [--agents pi,opencode] [--help]
```

| Flag | Description |
|------|-------------|
| `--no-restart` | Do not restart llama-swap even if its config changed |
| `--agents <list>` | Restrict agent sync to a comma-separated list of supported agents (default: auto-detect all present) |
| `--help` | Usage |

| Variable | Default | Description |
|----------|---------|-------------|
| `MODELS_YML` | *(unset)* | Explicit path to the catalog. If set, it is used and **must exist** |
| `LLAMA_SWAP_CONFIG` | `/srv/llama-swap/config/config.yaml` | llama-swap config path (matches `setup-llama-swap.sh` default `LLAMA_SWAP_DIR`) |
| `PI_MODELS_JSON` | `$HOME/.pi/agent/models.json` | Pi model config path |
| `OPENCODE_CONFIG` | `$HOME/.config/opencode/opencode.json` | Opencode config path |

### Catalog Resolution

1. If `MODELS_YML` is set → use it; **error** if the file does not exist.
2. Else if `<repo root>/models.yml` exists → use it.
3. Else use `<repo root>/models.yml.default`.

`<repo root>` = the parent directory of `tasks/` (derived from the script location).
The chosen file is logged on start.

`models.yml.default` is committed and must contain **no real secrets** (placeholder API keys).
`models.yml` is added to `.gitignore`.

---

## Model Catalog Schema

```yaml
# Top-level env: inherited by all models. Placeholders in env values are
# expanded (env vars may reference earlier-defined env vars and shell env).
env:
  - name: MODEL_DIR
    value: ${HOME}/.cache/huggingface/hub

providers:
  - name: evo                       # provider name; used for matching in agent configs
    baseUrl: http://localhost:9292/v1
    apiKey: sk-PLACEHOLDER
    models:
      # ── Local model: weights downloaded, served by llama-swap ──
      - name: ornith-1.5-35b        # canonical id: llama-swap key + agent model id
        type: local
        env:                        # optional; adds/overrides top-level env for this model
          - name: CUDA_VISIBLE_DEVICES
            value: "0"
        download:                   # required for local; list of shell commands
          - "hf download hf://bartowski/Ornith-1.5-35B-A3B-GGUF/Ornith-1.5-35B-A3B-Q4_K_S.gguf --local-dir ${MODEL_DIR}/bartowski/Ornith-1.5-35B-A3B-GGUF"
        serve:
          cmd: |                    # required for local; raw llama-swap cmd, user-owned
            ${llama-server-bin}
            --port ${PORT}
            -m ${MODEL_DIR}/bartowski/Ornith-1.5-35B-A3B-GGUF/Ornith-1.5-35B-A3B-Q4_K_S.gguf
            --ctx-size 128000
            --jinja
        agent:                      # optional; all fields optional (defaults apply)
          contextWindow: 200000     # default: 200000
          maxTokens: 16000          # default: 16000
          reasoning: true           # default: true
          input: [text]             # default: [text]
          thinkingLevelMap:         # optional
            minimal: null
            low: low
            medium: medium
            high: null
            xhigh: xhigh
            max: null

      # ── Remote model: no download, no serve; name = upstream model id ──
      - name: meta-llama/llama-3.1-8b-instruct
        type: remote
        agent:
          contextWindow: 131072
```

### Schema Rules

- `env` (top-level and per-model): list of `{name, value}`. Names must be valid shell-style
  identifiers. **Reserved names rejected:** `PORT`, `MODEL_ID`, `PID` (llama-swap reserved
  macros) — using them would corrupt `serve.cmd` expansion. For `type: local` models the
  effective env (top-level merged with per-model) is also written into the new llama-swap
  entry's `env:` list (Behavior 3).
- `providers[]`: `name` (non-empty), `baseUrl` (valid URL), `models` (non-empty list).
- `models[]`: `name` (non-empty; charset `[A-Za-z0-9._/-]` — it becomes a llama-swap key and a
  JSON model id), `type` (`local` | `remote`).
- `type: local` requires non-empty `download` (list of strings) and non-empty `serve.cmd`.
  `download`/`serve` must **not** be present for `type: remote`.
- **Uniqueness:** `name` must be unique **across all local models** (they share the llama-swap
  `models:` namespace). The same `name` may repeat across different providers and remote models
  (agent configs allow the same model id under multiple providers).
- `agent` fields: `contextWindow` (int), `maxTokens` (int), `reasoning` (bool),
  `input` (list of `text`/`image`), `thinkingLevelMap` (map of thinking level → level-or-null).

### Placeholder Expansion

Applied to `download` commands and `serve.cmd`:

1. Catalog env vars (top-level, in listed order, then per-model) are available.
2. A variable is substituted **only if** it is defined in the catalog env or in the current
   shell environment (this is how `${HOME}` works without declaring it).
3. Anything else — llama-swap macros such as `${PORT}`, `${MODEL_ID}`, `${llama-server-bin}`,
   `${models-dir}` — is left **untouched** for llama-swap to expand at serve time.
4. Env values may reference earlier-defined env vars and shell env; expansion runs to a fixed
   point (bounded passes; a non-converging reference is an error).
5. `download` commands are executed in a shell, so plain shell environment (e.g. `HF_TOKEN`
   for gated models) is available without catalog declaration.

---

## Behaviors

### Behavior 1: Pre-flight Checks

**When:** before any mutation, on every run.

| Check | On failure |
|-------|-----------|
| Catalog file resolves and parses as valid YAML | Exit 1, print parse error |
| Schema rules valid (see Schema Rules) | Exit 1, print all schema violations (not just the first) |
| Catalog contains `local` models **and** `LLAMA_SWAP_CONFIG` missing | Exit 1: "llama-swap is not set up. Run `./tasks/setup-llama-swap.sh` first." |
| Catalog has `download:` commands **and** `hf` not on PATH | Exit 1: "hf CLI is not installed. Run `./tasks/setup-basics.sh` first." |
| `jq` / `yq` not on PATH | Exit 1: run `./tasks/setup-basics.sh` first |
| Agent config file missing (per adapter) | **Skip** that agent with a note (not an error) |

Remote-only catalogs run fine on a machine without llama-swap.

### Behavior 2: Download Model Weights

**When:** after pre-flight, for each `type: local` model, in catalog order.

For each command in the model's `download` list:

1. Run the command with `--dry-run` appended (after placeholder expansion).
2. Parse the line `[dry-run] Will download N files (out of M) totalling SIZE.` to obtain the
   file count `N`. If the line is present and `N == 0`, log `already present, skipping` and
   do not run the real download (dry-run exits 0 in that case).
3. Otherwise (N > 0, the line cannot be parsed, or the dry-run exits nonzero) → log
   `downloading <N> files (<size>)` and run the real command, streaming its output.
   (Conservative: never skip a download on ambiguity.)
4. A failing command aborts the model's download with an error (exit 2 at the end — see
   "Failure Handling"); remaining models are still attempted.

Guarantees:

- **Download-once** is provided by the `hf` CLI in `--local-dir` mode: the in-dir
  `.cache/huggingface/` metadata ledger + default `--no-force-download` prevent re-downloads.
  The script never deletes this metadata.
- Interrupted/partial files are re-fetched/resumed by `hf` on the next run.
- The canonical download form (documented in `models.yml.default`) is
  `hf download <hf-uri> [files...] --local-dir ${MODEL_DIR}/<repo>`; per-repo subdirectories
  are recommended to avoid filename collisions across repos in a shared `MODEL_DIR`.

### Behavior 3: llama-swap Configuration Sync

**When:** after downloads, if the catalog has local models.

1. Read `LLAMA_SWAP_CONFIG` (`/srv/llama-swap/config/config.yaml` default).
2. For each local model (in catalog order):
   - If the model key (= `name`) **does not exist** under `models:` → add the entry:
     key = `name`, `cmd` = the expanded `serve.cmd`, and — if the model's
     **effective env** (top-level `env` merged with per-model `env`, per-model
     wins; values placeholder-expanded) is non-empty — `env:` = that list in
     `NAME=value` form.
   - If the key **exists** → leave it **completely untouched**; log `already present, unchanged`.
     (Decision 19: the user hand-tunes serving commands; the script never modifies them.)
3. Never touch: `macros`, `matrix`, `hooks`, `apiKeys`, `peers`, and all top-level global
   settings.
4. After any addition, validate the result parses as YAML (`yq . file`; exits nonzero on
   invalid YAML); if invalid, restore the previous file from a temp backup and fail (exit 2).

   **Important note:** kislyuk-style `yq` round-trips the *entire* YAML document, so comments
   and manual reformatting are **not preserved** when the file is rewritten. The script MUST
   log a warning the first time it modifies `config.yaml`.
5. **Restart:** if the config file changed → `sudo systemctl restart llama-swap`
   (this also starts the service if it was stopped). Log the restart. If unchanged → no
   restart. `--no-restart` suppresses the restart (and prints the manual command).

### Behavior 4: Agent Configuration Sync

**When:** after llama-swap sync, for each **detected** agent (or each agent named in
`--agents`).

Each agent is an adapter (`lib/agent-<name>.sh`) providing:
- the config file path,
- the "provider exists?" lookup (by provider **name**, Decision 20),
- the merge/write logic for its specific JSON structure.

For each agent named in `--agents` (after validating it is a supported agent; unsupported names cause an immediate exit 1 with a message listing the supported agents and the offending names):

1. **Provider block:**
   - If a provider with the same **name** exists → keep it. If its `baseUrl` differs from the
     catalog → update it and warn. `apiKey` is updated only if the catalog provides one.
   - If no such provider exists → create it with `name`/`baseUrl`/`apiKey` and an empty
     model list.

   **WARNING:** If any catalog `apiKey` value looks like a placeholder (contains the
   substring `PLACEHOLDER`, e.g. `sk-PLACEHOLDER`), log a warning before writing it to any
   agent config; the placeholder is still written (user responsibility to replace it in
   `models.yml`).
2. **Models** (for the provider's catalog models), using the `agent:` metadata with defaults
   (Decision 11):
   - Model id (= catalog `name`) **missing** in the provider → add the full entry with
     defaults applied; log `added`.
   - Model id **present** → compare the **managed fields** (`name`, `contextWindow`,
     `maxTokens`, `reasoning`, `input`, `thinkingLevelMap`) with the catalog; update any that
     differ and log `updated <fields>`; untouched fields of the existing entry are preserved
     (Decision 19). Unmanaged fields (e.g. `cost`) are never written by the script.
3. Models/providers in the agent config that are **not** in the catalog are never removed or
   modified (Decision 8).
4. After each agent write: validate the JSON parses (`jq empty`); on invalid output, restore
   the pre-run backup and fail (exit 2).

**Adapters delivered:**
- `lib/agent-pi.sh` — `~/.pi/agent/models.json`.
  - Provider block: `providers.<name>` with `baseUrl`, `api: "openai-completions"`
    (written when the provider is created), `apiKey` (only if the catalog provides one),
    `models: []`. Existing provider blocks: only `baseUrl`/`apiKey` managed (Behavior 4).
  - Model entry (list item): `id` = catalog `name`, `name`, `reasoning`, `input`,
    `contextWindow`, `maxTokens`, optional `thinkingLevelMap` (written as-is, nulls
    preserved). `cost` is unmanaged: omitted on new entries, never modified on existing.
- `lib/agent-opencode.sh` — `~/.config/opencode/opencode.json`. Reference: opencode
  custom-provider config (opencode.ai/docs/providers, "Custom provider"; schema:
  opencode.ai/config.json → `ProviderConfig`).
  - Provider block: `provider.<name>` with `name`, `npm: "@ai-sdk/openai-compatible"`
    (written when the provider is created), `options.baseURL` = catalog `baseUrl`,
    `options.apiKey` (only if the catalog provides one), `models: {}`.
  - Model entry: object keyed by catalog `name` under `provider.<name>.models`.
    Managed field mapping:

  | Catalog | opencode | Notes |
  |---------|----------|-------|
  | `name` | `name` | |
  | `contextWindow` | `limit.context` | `limit` requires both fields, both always written |
  | `maxTokens` | `limit.output` | |
  | `reasoning` | `reasoning` | |
  | `input` | `modalities.input` | plus `attachment` = `true` iff `input` contains `image` |
  | `thinkingLevelMap` | — | no opencode equivalent; **not written** (model objects reject unknown fields) |

    Creation-time defaults for new entries (written once, never managed afterwards):
    `tool_call: true`, `modalities.output: ["text"]`. Existing entries: managed fields
    updated if different; all other fields (`tool_call`, `modalities.output`, `cost`,
    …) never touched.

### Behavior 5: Verification & Summary

**When:** at the end of every run, before exiting.

1. **Verify** (re-read from disk):
   - Every local model key exists in `LLAMA_SWAP_CONFIG` under `models:`.
   - For every synced agent: every catalog provider (by name) exists, and every catalog model
     id exists under it.
2. **Summary** table per component (llama-swap, each agent, downloads):
   `added` / `updated` / `already present` / `skipped` / `failed` counts with model names.
3. Exit code: `0` all good (including pure no-op), `1` pre-flight failure,
   `2` partial/complete failure during mutation or verification.

### Failure Handling

- Pre-flight failures exit immediately (1) with an actionable message (Decision 16/17).
- A download failure does not stop other models' downloads, but the run ends with exit 2 and
  the verification step reports the gap.
- Config writes are all-or-nothing per file: temp-write + JSON/YAML validation + atomic move;
  on validation failure the original file is restored and the run exits 2.
- The script is non-interactive (project convention): no prompts, ever.

### Idempotency

Running `sync-models.sh` twice in a row with an unchanged catalog:

- Downloads: every `--dry-run` reports 0 files → nothing downloaded.
- llama-swap: no new keys → file untouched → **no service restart**.
- Agents: all providers/models present with matching managed fields → files untouched.
- Exit 0, summary shows all "already present".

### Out of Scope

- Installing/updating llama-swap, pi, opencode, or the `hf` CLI (existing tasks).
- Managing llama-swap `matrix:`/`hooks:`/`apiKeys:` or any global llama-swap settings.
- Removing models from any config (no deprovisioning).
- vLLM/LM-Studio serving paths for local models (the user writes the raw `serve.cmd`, so any
  backend is possible, but no first-class support/templating).
- Synchronizing the catalog *from* the machine back to the YAML (one-way only).
- Automated test coverage (see `tests.md` — manual scenarios; bats deferred per project test strategy).
