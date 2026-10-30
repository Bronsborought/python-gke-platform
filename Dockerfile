FROM python:3.14-slim@sha256:cd89c30eda26ee911a4611b18680086e0ea42e6f5f8cbe653d07fa7958c9cec8 AS builder

WORKDIR /build

COPY requirements.txt .
RUN python -m pip wheel \
    --no-cache-dir \
    --only-binary=:all: \
    --wheel-dir=/wheels \
    -r requirements.txt


FROM python:3.14-slim@sha256:cd89c30eda26ee911a4611b18680086e0ea42e6f5f8cbe653d07fa7958c9cec8 AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    APP_ENV=production \
    LOG_LEVEL=INFO \
    DATA_DIR=/data \
    PORT=8000

WORKDIR /app

COPY requirements.txt .
RUN --mount=type=bind,from=builder,source=/wheels,target=/wheels \
    python -m pip install \
        --no-compile \
        --no-index \
        --find-links=/wheels \
        -r requirements.txt \
    && python -m pip check

RUN groupadd --gid 10001 appuser \
    && useradd --uid 10001 --gid appuser \
        --no-create-home --shell /usr/sbin/nologin appuser \
    && mkdir /data \
    && chown appuser:appuser /data

COPY app/ ./app/

USER 10001:10001

EXPOSE 8000

CMD ["sh", "-c", "exec python -m uvicorn app.main:app --host 0.0.0.0 --port \"$PORT\""]
