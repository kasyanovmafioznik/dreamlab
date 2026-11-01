"""Domain models: generation options catalog and API schemas."""

from __future__ import annotations

from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field, field_validator

# ---------------------------------------------------------------------------
# Options catalog (single source of truth for premium checks and /v1/options)
# ---------------------------------------------------------------------------

class Style(str, Enum):
    photorealistic = "photorealistic"
    illustration = "illustration"
    minimal = "minimal"
    cinematic = "cinematic"
    cyberpunk = "cyberpunk"
    watercolor = "watercolor"


class AspectRatio(str, Enum):
    square_1_1 = "1:1"
    wide_16_9 = "16:9"
    tall_9_16 = "9:16"
    ultra_wide_21_9 = "21:9"


class Quality(str, Enum):
    standard = "standard"
    hd = "hd"
    ultra = "4k"


STYLES: dict[Style, dict] = {
    Style.photorealistic: {"label": "Photorealistic", "premium": False},
    Style.illustration: {"label": "Illustration", "premium": False},
    Style.minimal: {"label": "Minimal", "premium": False},
    Style.cinematic: {"label": "Cinematic", "premium": True},
    Style.cyberpunk: {"label": "Cyberpunk", "premium": True},
    Style.watercolor: {"label": "Watercolor", "premium": True},
}

ASPECT_RATIOS: dict[AspectRatio, dict] = {
    AspectRatio.square_1_1: {"label": "Square 1:1", "premium": False},
    AspectRatio.wide_16_9: {"label": "Wide 16:9", "premium": False},
    AspectRatio.tall_9_16: {"label": "Portrait 9:16", "premium": False},
    AspectRatio.ultra_wide_21_9: {"label": "Cinema 21:9", "premium": True},
}

QUALITIES: dict[Quality, dict] = {
    Quality.standard: {"label": "Standard (1024px)", "premium": False, "long_side": 1024},
    Quality.hd: {"label": "HD (2048px)", "premium": True, "long_side": 2048},
    Quality.ultra: {"label": "4K (4096px)", "premium": True, "long_side": 4096},
}

ASPECT_SHAPES: dict[AspectRatio, tuple[int, int]] = {
    AspectRatio.square_1_1: (1, 1),
    AspectRatio.wide_16_9: (16, 9),
    AspectRatio.tall_9_16: (9, 16),
    AspectRatio.ultra_wide_21_9: (21, 9),
}


def premium_options_used(
    style: Style, aspect_ratio: AspectRatio, quality: Quality
) -> list[str]:
    """Return human-readable names of premium options in the request."""
    used: list[str] = []
    if STYLES[style]["premium"]:
        used.append(f"style:{style.value}")
    if ASPECT_RATIOS[aspect_ratio]["premium"]:
        used.append(f"aspect_ratio:{aspect_ratio.value}")
    if QUALITIES[quality]["premium"]:
        used.append(f"quality:{quality.value}")
    return used


# ---------------------------------------------------------------------------
# API schemas
# ---------------------------------------------------------------------------

class SubscriptionTier(str, Enum):
    free = "free"
    premium = "premium"


class JobStatus(str, Enum):
    queued = "queued"
    processing = "processing"
    succeeded = "succeeded"
    failed = "failed"


class GenerateRequest(BaseModel):
    user_id: str = Field(min_length=8, max_length=64, description="Anonymous client UUID")
    prompt: str = Field(min_length=3, max_length=500)
    style: Style = Style.photorealistic
    aspect_ratio: AspectRatio = AspectRatio.square_1_1
    quality: Quality = Quality.standard

    @field_validator("user_id")
    @classmethod
    def _user_id_visible(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("user_id must not be blank")
        return v.strip()


class JobError(BaseModel):
    code: str
    message: str


class JobOut(BaseModel):
    id: str
    status: JobStatus
    prompt: str
    style: Style
    aspect_ratio: AspectRatio
    quality: Quality
    image_url: str | None = None
    error: JobError | None = None
    created_at: str
    finished_at: str | None = None


class GenerateAccepted(BaseModel):
    id: str
    status: JobStatus
    poll_url: str


class SubscriptionOut(BaseModel):
    user_id: str
    tier: SubscriptionTier
    upgraded_at: str | None = None


class OptionItem(BaseModel):
    id: str
    label: str
    premium: bool


class OptionsOut(BaseModel):
    styles: list[OptionItem]
    aspect_ratios: list[OptionItem]
    qualities: list[OptionItem]
    generation_delay_seconds: Literal["3-8"] = "3-8"


class ApiErrorBody(BaseModel):
    code: str
    message: str
    details: dict | None = None


class ErrorResponse(BaseModel):
    error: ApiErrorBody


class GenerationListOut(BaseModel):
    items: list[JobOut]
