"""HTTP API: health, options, generations (async jobs), subscription."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException, Query, Request, status
from fastapi.responses import FileResponse

from app.models import (
    ASPECT_RATIOS,
    QUALITIES,
    STYLES,
    AspectRatio,
    ErrorResponse,
    GenerateAccepted,
    GenerateRequest,
    GenerationListOut,
    JobOut,
    JobStatus,
    OptionItem,
    OptionsOut,
    Quality,
    Style,
    SubscriptionOut,
    SubscriptionTier,
    premium_options_used,
)
from app.storage.db import Database

router = APIRouter()


def _db(request: Request) -> Database:
    return request.app.state.db


def _job_out(row) -> JobOut:
    image_url = (
        f"/v1/generations/{row['id']}/image" if row["status"] == "succeeded" else None
    )
    error = None
    if row["status"] == "failed":
        error = {"code": row["error_code"] or "unknown", "message": row["error_message"] or ""}
    return JobOut(
        id=row["id"],
        status=JobStatus(row["status"]),
        prompt=row["prompt"],
        style=Style(row["style"]),
        aspect_ratio=AspectRatio(row["aspect_ratio"]),
        quality=Quality(row["quality"]),
        image_url=image_url,
        error=error,
        created_at=row["created_at"],
        finished_at=row["finished_at"],
    )


@router.get("/health")
def health() -> dict:
    return {"status": "ok"}


@router.get("/", include_in_schema=False)
def root() -> dict:
    return {
        "service": "mock-ai-image-generation",
        "docs": "/docs",
        "health": "/health",
        "options": "/v1/options",
    }


@router.get("/v1/options", response_model=OptionsOut)
def options() -> OptionsOut:
    return OptionsOut(
        styles=[
            OptionItem(id=s.value, label=meta["label"], premium=meta["premium"])
            for s, meta in STYLES.items()
        ],
        aspect_ratios=[
            OptionItem(id=a.value, label=meta["label"], premium=meta["premium"])
            for a, meta in ASPECT_RATIOS.items()
        ],
        qualities=[
            OptionItem(id=q.value, label=meta["label"], premium=meta["premium"])
            for q, meta in QUALITIES.items()
        ],
    )


@router.post(
    "/v1/generations",
    response_model=GenerateAccepted,
    status_code=status.HTTP_202_ACCEPTED,
    responses={402: {"model": ErrorResponse}, 422: {"model": ErrorResponse}},
)
async def create_generation(req: GenerateRequest, request: Request) -> GenerateAccepted:
    db = _db(request)
    tier = db.get_subscription_tier(req.user_id)

    if tier == SubscriptionTier.free:
        used = premium_options_used(req.style, req.aspect_ratio, req.quality)
        if used:
            raise HTTPException(
                status_code=status.HTTP_402_PAYMENT_REQUIRED,
                detail={
                    "code": "premium_required",
                    "message": "This request uses premium options. Upgrade your subscription to continue.",
                    "details": {"required_options": used, "upgrade_url": "/v1/users/" + req.user_id + "/subscription/upgrade"},
                },
            )

    job_id = request.app.state.jobs.submit(
        user_id=req.user_id,
        prompt=req.prompt,
        style=req.style,
        aspect_ratio=req.aspect_ratio,
        quality=req.quality,
    )
    return GenerateAccepted(
        id=job_id,
        status=JobStatus.queued,
        poll_url=f"/v1/generations/{job_id}",
    )


@router.get(
    "/v1/generations/{job_id}",
    response_model=JobOut,
    responses={404: {"model": ErrorResponse}},
)
def get_generation(
    job_id: str,
    request: Request,
    user_id: str | None = Query(default=None, min_length=8, max_length=64),
) -> JobOut:
    row = _db(request).get_job(job_id)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": f"Generation '{job_id}' does not exist."},
        )
    if user_id is not None and row["user_id"] != user_id:
        # The client sends its anonymous id on every request; a job that
        # belongs to somebody else must not be observable.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": f"Generation '{job_id}' does not exist."},
        )
    return _job_out(row)


@router.get("/v1/generations/{job_id}/image")
def get_generation_image(
    job_id: str,
    request: Request,
    user_id: str | None = Query(default=None, min_length=8, max_length=64),
) -> FileResponse:
    db = _db(request)
    row = db.get_job(job_id)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": f"Generation '{job_id}' does not exist."},
        )
    if user_id is not None and row["user_id"] != user_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": f"Generation '{job_id}' does not exist."},
        )
    if row["status"] != "succeeded" or not row["image_path"]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "image_not_ready",
                "message": f"Generation is '{row['status']}', image is not available yet.",
            },
        )
    path = Path(row["image_path"])
    if not path.is_absolute():
        # Legacy rows stored a relative path — resolve against the data dir.
        path = (request.app.state.settings.images_dir / path.name).resolve()
    if not path.exists():
        # DB row survived a restart but the image file did not (volume wiped).
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={
                "code": "image_expired",
                "message": "The image file is no longer available on the server.",
            },
        )
    return FileResponse(path, media_type="image/png")


@router.get("/v1/generations", response_model=GenerationListOut)
def list_generations(
    request: Request,
    user_id: str = Query(min_length=8, max_length=64),
    limit: int = Query(default=50, ge=1, le=100),
) -> GenerationListOut:
    rows = _db(request).list_jobs(user_id, limit=limit)
    return GenerationListOut(items=[_job_out(r) for r in rows])


@router.get("/v1/users/{user_id}/subscription", response_model=SubscriptionOut)
def get_subscription(user_id: str, request: Request) -> SubscriptionOut:
    row = _db(request).get_or_create_user(user_id)
    return SubscriptionOut(
        user_id=row["user_id"],
        tier=SubscriptionTier(row["tier"]),
        upgraded_at=row["upgraded_at"],
    )


@router.post("/v1/users/{user_id}/subscription/upgrade", response_model=SubscriptionOut)
def upgrade_subscription(user_id: str, request: Request) -> SubscriptionOut:
    row = _db(request).set_subscription(user_id, SubscriptionTier.premium)
    return SubscriptionOut(
        user_id=row["user_id"],
        tier=SubscriptionTier(row["tier"]),
        upgraded_at=row["upgraded_at"],
    )
