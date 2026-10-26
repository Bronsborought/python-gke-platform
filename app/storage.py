import logging
import os
import tempfile
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter()
logger = logging.getLogger(__name__)


class DataPayload(BaseModel):
    content: str = Field(max_length=100_000)


def storage_dir():
    directory = Path(os.getenv("DATA_DIR", "./data"))
    directory.mkdir(parents=True, exist_ok=True)
    return directory


@router.get("/ready")
def ready():
    try:
        with tempfile.TemporaryFile(dir=storage_dir()) as probe:
            probe.write(b"ready")
            probe.flush()
            probe.seek(0)
            if probe.read() != b"ready":
                raise OSError("Storage verification failed")
    except OSError:
        logger.exception("Readiness storage check failed")
        raise HTTPException(status_code=503, detail="Storage unavailable")

    return {"status": "ready"}


@router.post("/data")
def write_data(payload: DataPayload):
    temporary_path = None
    try:
        directory = storage_dir()
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=directory,
            delete=False,
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)
            temporary_file.write(payload.content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())

        temporary_path.replace(directory / "payload.txt")
    except OSError:
        logger.exception("Data write failed")
        raise HTTPException(status_code=503, detail="Storage unavailable")
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)

    return {"status": "saved"}


@router.get("/data")
def read_data():
    try:
        content = (storage_dir() / "payload.txt").read_text(encoding="utf-8")
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="No data saved yet")
    except OSError:
        logger.exception("Data read failed")
        raise HTTPException(status_code=503, detail="Storage unavailable")

    return {"content": content}
