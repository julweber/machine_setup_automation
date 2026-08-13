"""ColQwen2.5 embedding service.

Loads the model once at startup from MODEL_PATH and keeps it in memory for
the container lifetime. Serves multi-vector embeddings for images and text
queries. Fully offline - models are mounted read-only, nothing is downloaded.
"""

import os
import sys
from contextlib import asynccontextmanager
from typing import Annotated

import torch
from colpali_engine.models import ColQwen2_5, ColQwen2_5_Processor
from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image
from pydantic import BaseModel

# HF model ID (resolved offline from the mounted cache via HF_HOME) or an
# absolute path to a model directory inside the mounted model dir.
MODEL_REF = os.environ.get("COLQWEN_MODEL", "")

state = {}


def _fail(message: str):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def _verify_adapter_loaded(model):
    """Fail hard if LoRA adapter weights were silently dropped.

    peft initializes lora_B with zeros; trained adapters have non-zero
    lora_B weights. If the model carries LoRA modules but ALL lora_B are
    still zero after loading, the checkpoint's adapter weights were not
    applied (e.g. key-mapping mismatch between the checkpoint and the
    installed transformers version) and the service would silently serve
    base-model embeddings.
    """
    lora_b = [p for n, p in model.named_parameters() if "lora_B" in n]
    if lora_b and not any(bool((p != 0).any()) for p in lora_b):
        _fail(f"model '{MODEL_REF}' loaded, but all LoRA lora_B weights "
              "are zero - the adapter weights were dropped during loading "
              "(key-mapping mismatch between checkpoint and transformers "
              "version). Embeddings would be base-model only. Check the "
              "COLPALI_VERSION / NGC_PYTORCH_TAG combination in .env.")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if not MODEL_REF:
        _fail("COLQWEN_MODEL is not set. Set it in the .env file next to "
              "docker-compose.yml.")
    if MODEL_REF.startswith("/") and not os.path.isdir(MODEL_REF):
        _fail(f"model directory '{MODEL_REF}' does not exist or is not "
              "readable. Check COLQWEN_MODEL_DIR / COLQWEN_MODEL in the "
              ".env file.")
    try:
        state["model"] = ColQwen2_5.from_pretrained(
            MODEL_REF,
            torch_dtype=torch.bfloat16,
            device_map="cuda:0",
        ).eval()
        state["processor"] = ColQwen2_5_Processor.from_pretrained(MODEL_REF)
    except Exception as exc:  # noqa: BLE001 - fail loud with full context
        _fail(f"failed to load model '{MODEL_REF}': {exc}\n"
              "The service runs fully offline - the model (and, for LoRA "
              "adapters, the base model referenced by adapter_config.json) "
              "must be available under the mounted COLQWEN_MODEL_DIR.")
    _verify_adapter_loaded(state["model"])
    yield


app = FastAPI(title="ColQwen2.5 embedding service", lifespan=lifespan)


class QueriesRequest(BaseModel):
    queries: list[str]


def _embed(batch) -> list[list[list[float]]]:
    """Run the model on a processed batch, one multi-vector list per input.

    Padding vectors are stripped via the attention mask so every input gets
    exactly its own sequence of embedding vectors, in input order.
    """
    model = state["model"]
    batch = batch.to(model.device)
    with torch.no_grad():
        embeddings = model(**batch)
    return [
        emb[mask.bool()].float().cpu().tolist()
        for emb, mask in zip(embeddings, batch["attention_mask"])
    ]


# Requests are only served after the lifespan startup (= model load)
# completed, so a 200 here means the model is ready. Used as readiness
# probe by reverse proxies such as llama-swap (default checkEndpoint).
@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/embed/queries")
async def embed_queries(request: QueriesRequest):
    if not request.queries:
        raise HTTPException(
            status_code=400, detail="'queries' must not be empty"
        )
    batch = state["processor"].process_queries(request.queries)
    return {"embeddings": _embed(batch)}


@app.post("/embed/images")
async def embed_images(files: Annotated[list[UploadFile], File()] = []):
    if not files:
        raise HTTPException(
            status_code=400, detail="at least one image file is required"
        )
    images = []
    for upload in files:
        try:
            image = Image.open(upload.file)
            image.load()
        except OSError as exc:
            raise HTTPException(
                status_code=400,
                detail=f"file '{upload.filename}' is not a readable image",
            ) from exc
        images.append(image.convert("RGB"))
    batch = state["processor"].process_images(images)
    return {"embeddings": _embed(batch)}
