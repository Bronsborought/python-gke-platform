import logging
import os
import socket

from fastapi import FastAPI

from app.metrics import setup_metrics
from app.storage import router

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

app = FastAPI(title="Python GKE Platform")
app.include_router(router)
setup_metrics(app)


@app.get("/")
def root():
    return {
        "status": "ok",
        "environment": os.getenv("APP_ENV", "local"),
        "pod_name": os.getenv("POD_NAME") or socket.gethostname(),
    }


@app.get("/healthz")
def healthz():
    return {"status": "healthy"}
