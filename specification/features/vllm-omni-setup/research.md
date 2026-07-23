# Research — vllm-omni-setup

> **Information sources:** [vllm-project/vllm-omni](https://github.com/vllm-project/vllm-omni) README, the project docs at
> `https://docs.vllm.ai/projects/vllm-omni/en/latest/` (Installation & Quickstart), the repo's `docker/` and
> `requirements/` directories, and Docker Hub tag listings for `vllm/vllm-omni` and `vllm/vllm-omni-rocm`.
> Verified 2026-07-24.

## What vLLM-Omni Is

`vllm-omni` is an **official vLLM sub-project** (announced by the vLLM community in November 2025, Apache-2.0)
that extends vLLM from text-only autoregressive generation to **omni-modality** inference and serving:

- **Modalities:** text, image, audio, video, and action/robot-policy data — inputs *and* generated outputs.
- **Architectures beyond AR:** Diffusion Transformers (DiT) and other parallel/non-autoregressive generators,
  in addition to vLLM's existing AR support with its KV-cache management.
- **Model families:** TTS/speech (MOSS-TTS, MiniCPM-o), diffusion image/video generation, text-to-image
  (e.g. `Tongyi-MAI/Z-Image-Turbo`), world models (NVIDIA Cosmos3), and any-to-any omni models (Qwen3-Omni),
  BAGEL, HunyuanImage, robot-policy models.
- **API:** OpenAI-compatible, served through the standard `vllm serve` entrypoint.

Release lines track vLLM's: `v0.22.0`, `v0.24.0` (latest tagged, July 2026), with docs referencing the 0.25 line.

## How It Is Deployed (the fact that shapes this feature)

**Prebuilt Docker images already exist** — no local build is required. This lets the feature mirror the
existing [`setup-vllm.sh`](../../../tasks/setup-vllm.sh) pattern (pull image → generate config → run) almost 1:1.

| Registry / repo | Tags observed on Docker Hub | Use |
|---|---|---|
| `vllm/vllm-omni` | `latest`, `latest-x86_64`, `latest-aarch64`, `v0.24.0`, `v0.24.0-x86_64`, `v0.24.0-aarch64`, `v0.22.0`, `cosmos3`, `cosmos3-x86_64`, `cosmos3-arm64` | NVIDIA CUDA (amd64 & arm64/Grace) and CPU |
| `vllm/vllm-omni-rocm` | (ROCm image) | AMD ROCm (amd64 only) |

The upstream `docker/Dockerfile.cuda` builds `FROM vllm/vllm-openai:v0.25.0` and installs the `vllm-omni`
package on top (`uv pip install .`). We rely on the **published** image instead of building.

Backends with requirements files / Dockerfiles upstream: `cuda`, `rocm`, `xpu`, `npu`, `musa`, `cpu`.
For this feature only **NVIDIA (CUDA)** and **AMD (ROCm)** are in scope; XPU/NPU/MUSA are niche and excluded.

## Serving Interface

The server is the **same `vllm serve` CLI**, gated by an `--omni` flag. From the quickstart:

```bash
# Text-to-image example from the official quickstart
vllm serve Tongyi-MAI/Z-Image-Turbo --omni --port 8091

# Request (OpenAI-compatible)
curl -s http://localhost:8091/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"a cup of coffee on the table"}]}'
```

- Endpoint: `POST /v1/chat/completions`; health: `GET /health` (same as vLLM).
- Standard vLLM server flags pass through (e.g. `--gpu-memory-utilization`, `--tensor-parallel-size`,
  `--max-model-len`); generative/diffusion models may ignore some, but the flags are accepted.
- Models are fetched from HuggingFace, so mounting the host HF cache (as `setup-vllm.sh` does) works unchanged.

## Constraints Noted

- Prerequisites (pip path, informational): Python 3.12, Linux. We deploy via Docker, so host Python is irrelevant.
- CPU execution is technically supported but impractical for diffusion/generative workloads — warn, do not block.
- ROCm image is amd64-only (no arm64), consistent with the existing `setup-vllm.sh` guard.

## Implications for the Design

1. Reuse the `setup-vllm.sh` structure verbatim where possible; only the image, the `--omni` flag, the default
   port, and the env-var namespace change.
2. Use a **separate `VLLM_OMNI_*` env namespace** and a separate `/srv/vllm-omni` project dir so the two stacks
   coexist on one host without collision.
3. Default port `8091` (from the quickstart) to avoid the `8000` used by `setup-vllm.sh`.
4. Backend auto-detection and arch-aware image tags map cleanly onto the published tag matrix above.
