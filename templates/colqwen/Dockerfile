# ColQwen2.5 embedding service image.
# NGC_PYTORCH_TAG and COLPALI_VERSION are supplied as build args by
# docker-compose from the generated .env - edit .env and rebuild to change
# them. Model weights are NEVER part of this image (mounted at runtime).
ARG NGC_PYTORCH_TAG=26.07-py3

FROM nvcr.io/nvidia/pytorch:${NGC_PYTORCH_TAG}

ARG COLPALI_VERSION=0.3.17

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt \
    && pip install --no-cache-dir "colpali-engine==${COLPALI_VERSION}"

COPY app/ /app/

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
