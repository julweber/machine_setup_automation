"""ColQwen2.5 embedding service.

Loads the model once at startup from MODEL_PATH and keeps it in memory for
the container lifetime. Serves multi-vector embeddings for images and text
queries. Fully offline - models are mounted read-only, nothing is downloaded.
"""

import os
import sys
from contextlib import asynccontextmanager

import torch
from colpali_engine.models import ColQwen2_5, ColQwen2_5_Processor
from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel

MODEL_PATH = os.environ.get("MODEL_PATH", "/models/colqwen2.5-v0.2")

state = {}


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if not os.path.isdir(MODEL_PATH):
        print(
            f"ERROR: model directory '{MODEL_PATH}' does not exist or is not "
            "readable. Place the model in the mounted model directory and "
            "check COLQWEN_MODEL_DIR / COLQWEN_MODEL_NAME in the .env file.",
            file=sys.stderr,
        )
        sys.exit(1)
    state["model"] = ColQwen2_5.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.bfloat16,
        device_map="cuda:0",
    ).eval()
    state["processor"] = ColQwen2_5_Processor.from_pretrained(MODEL_PATH)
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


@app.post("/embed/queries")
async def embed_queries(request: QueriesRequest):
    if not request.queries:
        raise HTTPException(
            status_code=400, detail="'queries' must not be empty"
        )
    batch = state["processor"].process_queries(request.queries)
    return {"embeddings": _embed(batch)}


@app.post("/embed/images")
async def embed_images(files: list[UploadFile] = File(default=[])):
    if not files:
        raise HTTPException(
            status_code=400, detail="at least one image file is required"
        )
    images = []
    for upload in files:
        try:
            image = Image.open(upload.file)
            image.load()
        except (UnidentifiedImageError, OSError) as exc:
            raise HTTPException(
                status_code=400,
                detail=f"file '{upload.filename}' is not a readable image",
            ) from exc
        images.append(image.convert("RGB"))
    batch = state["processor"].process_images(images)
    return {"embeddings": _embed(batch)}
