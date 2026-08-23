# Plan: Improve `tasks/setup-vllm.sh` (DGX Spark / vLLM best practices)

**Date:** 2026-07-06
**Scope:** Review of `tasks/setup-vllm.sh` against published best practices for running vLLM in Docker on an NVIDIA DGX Spark (GB10, `sm_121`, 128 GB unified memory) and general vLLM Docker deployment.

## Sources

| Source | Key content |
|---|---|
| [vLLM blog: vLLM on the DGX Spark (2026-06-01)](https://vllm.ai/blog/2026-06-01-vllm-dgx-spark) | Spark runtime flags, unified-memory tuning, image guidance, JIT warmup, metrics, model fit |
| [NVIDIA dgx-spark-playbooks: nvidia/vllm](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/vllm/README.md) | NGC `nvcr.io/nvidia/vllm` images, model support matrix, agent-ready Qwen3.6-35B recipe, multi-Spark/Ray, troubleshooting |
| [vLLM Docker docs](https://docs.vllm.ai/en/stable/deployment/docker/) | Official images (`vllm/vllm-openai`, `-rocm`), `--ipc=host`/`--shm-size`, persisting `VLLM_CACHE_ROOT`, non-root user |
| [NVIDIA Spark vLLM troubleshooting](https://build.nvidia.com/spark/vllm/troubleshooting) | Known issues (SM_121a, OOM, driver/CUDA mismatches) |

---

## 1. What the script already does right ✅

- `ipc: "host"` + configurable `shm_size` for GPU backends (vLLM docs recommend `ipc=host` or `--shm-size`).
- HF cache mounted at `/root/.cache/huggingface` ("download once, mount everywhere").
- `HF_TOKEN` support via `.env` (chmod 600) for gated models.
- `VLLM_NO_USAGE_STATS=1` telemetry opt-out.
- Blackwell detection (compute capability 12.1) + **INT8 quantization guard for GB10** (correct — INT8 is unsupported there).
- `restart: unless-stopped`, health check against `/health`, port pre-flight check, input validation of all env vars, Traefik integration, idempotency with `--force`/`--check`.
- Correct ROCm flags (`/dev/kfd`, `/dev/dri`, `SYS_PTRACE`, `seccomp=unconfined`, `video` group) matching upstream docs.
- Correctly uses `vllm/vllm-openai-rocm` (deprecated `rocm/vllm` is avoided).

## 2. Gaps vs. best practices

### 2.1 Image selection (High priority)

**Current:** for `sm_121` hosts the script hard-codes the community image
`lharillo/vllm-blackwell-gb10-spark:latest`; for everything else `vllm/vllm-openai:latest`.

**Best practice:**
- NVIDIA's DGX Spark playbook uses the official images: NGC `nvcr.io/nvidia/vllm:<version>` (e.g. `26.05-py3`) for CUDA 13 Blackwell, and `vllm/vllm-openai:latest` (or the CUDA 13 `cu130` track) for agent-ready recipes. Model-specific tags exist too: `vllm/vllm-openai:gemma`, `vllm/vllm-openai:gemma4-cu130`.
- The vLLM blog warns that nightly tags move: **pin a specific release tag, commit tag, or digest for deployments** — `:latest` is only acceptable for testing.
- `nvcr.io` pulls require NGC authentication (free API key) — a pre-flight `docker pull` test or `docker login nvcr.io` hint is needed.

**Improvements:**
- [ ] Replace `lharillo/...` with `nvcr.io/nvidia/vllm` (opt-in, requires NGC auth) and/or `vllm/vllm-openai:<cu130 tag>` as the default for `sm_121`. Keep the community image as an explicit opt-in via `VLLM_IMAGE`.
- [ ] Make the image fully overridable via `VLLM_IMAGE` env var / `--image` flag (currently only implicit).
- [ ] Replace bare `:latest` defaults with a pinned default tag (configurable), print a warning that `:latest` is not reproducible.
- [ ] Support model-family tags (`gemma`, `gemma4-cu130`) — e.g. auto-select when `VLLM_MODEL` matches a Gemma handle.
- [ ] Document/verify `docker login nvcr.io` when the NGC image is chosen (pre-flight pull test already exists — surface auth errors clearly).

### 2.2 `--gpu-memory-utilization` default is too aggressive for Spark (High)

**Current:** `VLLM_GPU_UTIL` default `0.90`.

**Best practice:** On DGX Spark this fraction applies to the **128 GB unified pool** shared with the OS, page cache, container runtime, and KV-cache growth. The blog recommends leaving headroom (its working recipe uses **0.85**; NVIDIA's playbook uses **0.8**, and the Qwen3.6-35B recipe even **0.4**). 0.90 risks OOM/instability with anything else running on the box.

**Improvements:**
- [ ] On detected `sm_121`, lower the *default* to 0.80–0.85 (keep 0.90 for discrete datacenter GPUs).
- [ ] Explain in the `.env` comment and summary output that on Spark the fraction is of the unified pool, and that headroom must cover OS/container/KV growth.
- [ ] Document the NVIDIA workaround for UMA memory pressure: `sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'`.

### 2.3 Spark-inappropriate tuning hints in `.env` (Medium)

The generated `.env` is written for "large datacenter GPUs", which misleads Spark users:

- `VLLM_MAX_NUM_SEQS` comment says *"higher = more throughput, Example: 256"* — the blog states **`--max-num-seqs 4`** is the right scale for Spark (above ~4 concurrent decode streams, bandwidth tax outweighs batching and TTFT spikes).
- `VLLM_MAX_NUM_BATCHED_TOKENS` comment says *"Recommended: >8192 for optimal throughput on large GPUs"* — Spark is explicitly **not** a large GPU; NVIDIA's Qwen3.6 recipe uses `8192`.
- `--kv-cache-dtype fp8` is listed as a plain example, but the blog warns it **may hurt predictability and can carry a noticeable performance cost on Spark** — avoid unless memory pressure requires it and quality checks pass.

**Improvements:**
- [ ] Branch the generated `.env` comments (or the summary) on whether an `sm_121` host was detected, and give Spark-specific guidance (low `max-num-seqs` ≤ 8, `max-num-batched-tokens` ≤ 8192, `kv-cache-dtype fp8` "only under memory pressure").
- [ ] `--enable-prefix-caching` in the examples is outdated — prefix caching is **on by default in vLLM V1**; remove or mark as "default, no flag needed".

### 2.4 No persistence of the vLLM compile cache (Medium)

**Best practice** (vLLM Docker docs): mount a named volume at `~/.cache/vllm` (`VLLM_CACHE_ROOT`) so `torch.compile`/Inductor/Triton/AOT artifacts survive across containers — otherwise every (re)start recompiles.

**Improvements:**
- [ ] Add a named volume `vllm-cache:/root/.cache/vllm` (host dir under `PROJECT_DIR` for portability) to the generated compose file.

### 2.5 Cold-start / JIT warmup not handled (Medium)

**Best practice** (blog): the **first request after boot** triggers Inductor + FlashInfer JIT codegen (~25 s), and large NVFP4 models take **10–15 min** to load weights.

**Improvements:**
- [ ] Raise `MAX_WAIT` from 120 s (or make it `VLLM_HEALTH_TIMEOUT`, default e.g. 900 s like the NVIDIA playbook's `timeout 900`). The current 120 s will always "time out" for models >~20 GB even though the server is loading fine.
- [ ] Add an optional post-health **warmup ping** (small `max_tokens=3` chat completion) so the first real user request isn't the JIT cold-start.
- [ ] Expose `--load-format fastsafetensors` (or a `VLLM_LOAD_FORMAT` var) — NVIDIA's recipes use it to cut the 10–15 min weight load.
- [ ] Mention `/metrics` (Prometheus) in the summary output for observing KV-cache usage, TTFT/ITL histograms.

### 2.6 Model-specific options only reachable via `VLLM_EXTRA_ARGS` (Medium)

Spark recipes rely on several flags the script has no first-class options for; squeezing them through `VLLM_EXTRA_ARGS` works but is undiscoverable:

- `--trust-remote-code` (required for Phi-4-multimodal and similar, per NVIDIA matrix)
- `--reasoning-parser <name>` / `--tool-call-parser <name>` / `--enable-auto-tool-choice` (agent-ready serving; e.g. `nemotron_v3`, `qwen3`, `qwen3_xml`)
- `--served-model-name` (clean client-facing model ID)
- `--speculative-config` (MTP speculative decoding for Nemotron-3-class models)
- `--load-format`
- `--attention-backend` / `--moe-backend` / `--linear-backend` (backend pins)

**Improvements:**
- [ ] Add optional env vars/flags for the most common ones: `VLLM_SERVED_MODEL_NAME`, `VLLM_TRUST_REMOTE_CODE`, `VLLM_REASONING_PARSER`, `VLLM_TOOL_CALL_PARSER`, `VLLM_ENABLE_AUTO_TOOL_CHOICE`, `VLLM_LOAD_FORMAT`, `VLLM_LOAD_PARALLEL` — emit the CLI flags only when set (existing pattern).
- [ ] Keep `VLLM_EXTRA_ARGS` for the long tail, but update the example block in `.env` with Spark-relevant examples (parser flags, `fastsafetensors`) instead of datacenter ones.
- [ ] Note in `.env`: for pre-quantized NVFP4/FP8 checkpoints leave `--quantization` **unset** (vLLM detects it from the model config); only set it for load-time quantization.

### 2.7 Review `sm_121`-specific env vars (Low)

**Current:** for `sm_121` the compose gets `TORCH_CUDA_ARCH_LIST=12.1a` and `VLLM_USE_FLASHINFER_MXFP4_MOE=1`.

**Best practice:** the vLLM blog states that older env vars for backend selection are **deprecated** (prefer CLI flags like `--moe-backend`/`--linear-backend`) and that FlashInfer overrides in Spark recipes are often **version-specific workarounds for a specific image tag**, not general requirements. `TORCH_CUDA_ARCH_LIST` mainly matters when building from source; official prebuilt images already target the right arch.

**Improvements:**
- [ ] Verify both vars against the chosen image tag; demote them to optional/opt-in (e.g. `VLLM_SPARK_EXTRA_ENV` or a `--spark-env-vars` flag) rather than always-on, and comment them as version-specific workarounds.

### 2.8 Pre-flight CUDA check tests the wrong thing for Docker (Low)

**Current:** the "Blackwell requires CUDA 13.0+" check parses `nvcc --version` from the **host**. With official Docker images the host CUDA *toolkit* is irrelevant — the image ships CUDA and the **driver** is the requirement.

**Improvements:**
- [ ] For the nvidia backend, check the **driver** version via `nvidia-smi --query-gpu=driver_version` (GB10 needs the CUDA-13-era driver) and check that the **NVIDIA Container Toolkit** is installed (it's a stated prerequisite in the NVIDIA playbook). The `nvcc` check can remain as a soft informational note.
- [ ] The playbook lists CUDA 13.0 toolkit + Python 3.12 as prerequisites — relevant only for source builds; note that the Docker path only needs Docker + NVIDIA Container Toolkit + a current driver.

### 2.9 Misc. smaller items (Low)

- [ ] **Non-root container:** official `vllm/vllm-openai` supports `--user 2000:0` (built-in `vllm` user). Offer an opt-in `VLLM_RUN_AS_NONROOT` (mount HF cache at `/home/vllm/.cache/huggingface`, group-writable). Low value on a single-purpose box, but cheap.
- [ ] **Metrics endpoint:** document `/metrics` in the "Useful commands" summary; optionally add a `--metrics-port` label behind Traefik if observability is desired.
- [ ] **Tensor parallel on single-node Spark:** `--tensor-parallel-size > 1` on a single Spark is meaningless (1 GPU); multi-Spark TP needs the Ray cluster path (`run_cluster.sh`, `--distributed-executor-backend ray`) which this script doesn't cover. Add a warning when `VLLM_TENSOR_PARALLEL > 1` on a single-GPU host, and point to the NVIDIA multi-Spark playbook for the supported path.
- [ ] **Model-size guidance:** include the directional guidance (from the blog/NVIDIA matrix): 100–130B MoE NVFP4 (~10–15B active) is the best Spark fit; up to ~200B NVFP4 fits the 128 GB pool; dense models are poorly matched. Useful in `--help` or a `docs` section; keep the NVIDIA model support matrix as a reference link.
- [ ] **`nvidia-smi` on Spark reports `N/A` for memory fields** (UMA) — the script's detection logic only uses `compute_cap`, so it's fine, but avoid adding memory-based logic.
- [ ] **Summary output:** print the resolved image tag (including pin/digest) and a "how to change the model" reminder.

## 3. Suggested implementation order

| # | Change | Priority | Effort |
|---|---|---|---|
| 1 | Lower `gpu-memory-utilization` default for `sm_121` + unified-memory docs | High | S |
| 2 | Image selection: official/pinned images, `VLLM_IMAGE` override, NGC auth pre-flight, Gemma tags | High | M |
| 3 | Spark-specific `.env` tuning comments (max-num-seqs, batched tokens, fp8 KV warning, prefix-caching default) | Medium | S |
| 4 | `VLLM_CACHE_ROOT` named volume persistence | Medium | S |
| 5 | Health-check timeout (900 s / configurable) + optional JIT warmup ping | Medium | S |
| 6 | First-class flags: served-model-name, trust-remote-code, parsers, load-format | Medium | M |
| 7 | Driver-based pre-flight check + NVIDIA Container Toolkit check | Low | S |
| 8 | Demote/review `sm_121` env-var workarounds | Low | S |
| 9 | TP>1 warning, non-root opt-in, metrics/`/metrics` docs, model-fit guidance | Low | S–M |

All changes must keep the script idempotent, keep `.env`/compose regeneration safe (backing up existing `.env`), and pass `shellcheck`.

---

## 4. Locked decisions (brainstorm 2026-07-06)

### 4.1 Scope

| # | Decision |
|---|---|
| 1 | Default image for `sm_121` (and all CUDA hosts): **pinned `vllm/vllm-openai:v0.27.1`** (arm64 + amd64 verified). No `:latest` defaults anywhere. ROCm: **pinned `vllm/vllm-openai-rocm:v0.27.1`** (verified). |
| 2 | `nvcr.io/nvidia/vllm` and `lharillo/...`: **no first-class support** — reachable only via explicit `VLLM_IMAGE` env var / `--image` flag. Pull pre-flight must surface NGC auth errors clearly. |
| 3 | `VLLM_GPU_UTIL` default: **0.80 on `sm_121`**, 0.90 other GPU backends. |
| 4 | Warmup ping: **default-on** for GPU backends after health passes; `--no-warmup` to skip. |
| 5 | Gemma auto-tag selection: **cut** (not needed). |
| 6 | Non-root container opt-in: **cut**. |
| 7 | `VLLM_LOAD_PARALLEL` promotion: **cut** (stays in `VLLM_EXTRA_ARGS`). |
| 8 | Everything else from §2: **in scope**, done in a single PR. |

### 4.2 Templating (new Theme E)

Per repo convention (`templates/<component>/`, ColQwen pattern — `envsubst` with explicit var list), the inline heredocs in `setup-vllm.sh` are replaced by:

- `templates/vllm/docker-compose.{nvidia,amd,cpu}.{direct,traefik}.yml` — **six complete template files** (backend × exposure), each valid, individually lintable YAML. No multi-line YAML fragment vars.
- `templates/vllm/env.template` — `.env` with Spark/datacenter comment branches (plain-text template; the only fragments are multi-line comment notes: `VLLM_GPU_UTIL_NOTE`, `VLLM_CONCURRENCY_NOTE`)

Backend-specific env vars (Spark `VLLM_SPARK_EXTRA_ENV`, CPU `VLLM_CPU_DISABLE_AVX512`) go to a second rendered **`extra-vars.env`** file (plain `KEY=VALUE`, no YAML constraints), referenced via `env_file: [".env", "extra-vars.env"]`.

Optional server flags are rendered as `VLLM_COMMAND_FLAGS` (one flag group per line, 6-space continuation indent) into the template's folded-scalar `command: >` block; the folded style joins the lines with spaces. `VLLM_MODEL` / `VLLM_GPU_UTIL` / `VLLM_EXTRA_ARGS` stay out of the envsubst var list on purpose — they remain `${...}` in the rendered compose file for compose-time substitution from `.env`.

The LM Studio models dir (`~/.lmstudio/models`) is `mkdir -p`'d and **always mounted** at `/lmstudio-models` (avoids a conditional volume line in the template; compose rejects an empty `"- \"\""` volume item).

**Why six files instead of fragment vars:** `envsubst` has no conditionals, and PyYAML/yamllint reject bare `${VAR}` placeholder lines in mapping positions (they scan as simple keys without colons); yamllint parser errors can't be suppressed with `# yamllint disable`. Complete per-combination templates keep every template individually `yamllint`-clean (same approach as `templates/openhands/`).

### 4.3 New env vars / flags

| Variable / flag | Purpose |
|---|---|
| `VLLM_IMAGE` / `--image` | Full image override (escape hatch for `nvcr.io`, `lharillo`, Gemma tags…) |
| `VLLM_HEALTH_TIMEOUT` / `--health-timeout` | Health-check wait; default 900 s (GPU) / 120 s (CPU) |
| `--no-warmup` | Skip the post-health warmup chat completion |
| `VLLM_SERVED_MODEL_NAME` | `--served-model-name` |
| `VLLM_TRUST_REMOTE_CODE` (true/false) | `--trust-remote-code` |
| `VLLM_LOAD_FORMAT` | `--load-format` (e.g. `fastsafetensors`) |
| `VLLM_REASONING_PARSER` | `--reasoning-parser` |
| `VLLM_TOOL_CALL_PARSER` | `--tool-call-parser` |
| `VLLM_ENABLE_AUTO_TOOL_CHOICE` (true/false) | `--enable-auto-tool-choice` |
| `VLLM_SPARK_EXTRA_ENV` | Opt-in `KEY=VALUE` env vars for `sm_121` (e.g. `TORCH_CUDA_ARCH_LIST=12.1a VLLM_USE_FLASHINFER_MXFP4_MOE=1`), commented as version-specific workarounds |

`TORCH_CUDA_ARCH_LIST` / `VLLM_USE_FLASHINFER_MXFP4_MOE` are **no longer always-on** for `sm_121`; they are examples documented in the help/env comments under `VLLM_SPARK_EXTRA_ENV`.

### 4.4 Other behavioral changes

- Pre-flight (nvidia): driver version via `nvidia-smi --query-gpu=driver_version` (error for `sm_121` if < 580 / CUDA-13 era; informational otherwise), NVIDIA Container Toolkit check via `docker info` runtimes; `nvcc` check demoted to soft informational note.
- Warning when `VLLM_TENSOR_PARALLEL > 1` on a single-GPU host (point to multi-Spark Ray playbook).
- vLLM compile cache: bind mount `${PROJECT_DIR}/.vllm-cache` → `/root/.cache/vllm`.
- `.env` comments: Spark/datacenter branch; remove `--enable-prefix-caching` example (V1 default); `kv-cache-dtype fp8` marked "only under memory pressure on Spark"; note to leave `--quantization` unset for pre-quantized NVFP4/FP8 checkpoints; `drop_caches` UMA workaround in Spark note.
- Summary: resolved image tag, `/metrics` documentation, model-fit guidance (100–130B MoE NVFP4 best fit for 128 GB; up to ~200B NVFP4; dense poorly matched) + NVIDIA model matrix link, "how to change the model" reminder.
- `:latest` in `VLLM_IMAGE` override → warning (non-reproducible).
- Help text gains a "Model fit (DGX Spark)" section.

### 4.5 Verification

- `shellcheck` on the script ✅, `yamllint` on all six templates ✅
- `--help` smoke-tested ✅
- Render dry-test for all 6 backend×exposure combinations, with and without optional flags: rendered output passes `yamllint` and `docker compose config`; command block expands to the expected flag list (compose-time `${VLLM_MODEL}`/`${VLLM_GPU_UTIL}`/`${VLLM_EXTRA_ARGS}` resolve from `.env`) ✅
- Idempotency: re-run with existing `.env` backs it up; `--force` re-render produces identical output for unchanged inputs
