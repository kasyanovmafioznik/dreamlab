"""FastAPI application factory and lifespan."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.routes import router
from app.config import Settings
from app.services.jobs import JobService
from app.storage.db import Database

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _error_response(status_code: int, code: str, message: str, details: dict | None = None) -> JSONResponse:
    body: dict = {"error": {"code": code, "message": message}}
    if details is not None:
        body["error"]["details"] = details
    return JSONResponse(status_code=status_code, content=body)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        settings.data_dir.mkdir(parents=True, exist_ok=True)
        settings.images_dir.mkdir(parents=True, exist_ok=True)
        db = Database(settings.db_path)
        orphans = db.fail_inflight_jobs_on_startup()
        if orphans:
            logger.info("marked %d in-flight job(s) as failed after restart", orphans)
        app.state.db = db
        app.state.jobs = JobService(db, settings)
        app.state.settings = settings
        yield
        db.close()

    app = FastAPI(
        title="Mock AI Image Generation API",
        version="1.0.0",
        description=(
            "Async mock image generation. No external services, no API keys — "
            "images are rendered locally with Pillow. See README for error triggers."
        ),
        lifespan=lifespan,
    )

    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(request: Request, exc: StarletteHTTPException):
        detail = exc.detail
        if isinstance(detail, dict):
            return _error_response(exc.status_code, detail.get("code", "error"), detail.get("message", ""), detail.get("details"))
        return _error_response(exc.status_code, "error", str(detail))

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(request: Request, exc: RequestValidationError):
        errors = [
            {"field": ".".join(str(loc) for loc in e["loc"] if loc != "body"), "message": e["msg"]}
            for e in exc.errors()
        ]
        return _error_response(
            422,
            "validation_error",
            "Request validation failed.",
            {"fields": errors},
        )

    app.include_router(router)
    return app


app = create_app()
