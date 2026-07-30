# ColQwen2.5 embedding service image.
# NGC_PYTORCH_TAG and COLPALI_VERSION are supplied as build args by
# docker-compose from the generated .env - edit .env and rebuild to change
# them. Model weights are NEVER part of this image (mounted at runtime).
ARG NGC_PYTORCH_TAG=25.10-py3

FROM nvcr.io/nvidia/pytorch:${NGC_PYTORCH_TAG}

ARG COLPALI_VERSION=0.3.13

WORKDIR /app

COPY requirements.txt /app/requirements.txt
# torchao ships with the NGC image but is unused here; peft>=0.19 raises an
# ImportError on NGC's torchao build (instead of ignoring it), which aborts
# LoRA-adapter injection. Removing it makes peft skip its torchao dispatch.
RUN pip uninstall -y torchao \
    && pip install --no-cache-dir -r /app/requirements.txt \
    && pip install --no-cache-dir "colpali-engine==${COLPALI_VERSION}"

COPY app/ /app/

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
