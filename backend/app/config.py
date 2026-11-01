"""Application settings loaded from environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    data_dir: Path = field(default_factory=lambda: Path(os.environ.get("DATA_DIR", "data")))
    min_delay_seconds: float = field(default_factory=lambda: _env_float("MIN_DELAY_SECONDS", 3.0))
    max_delay_seconds: float = field(default_factory=lambda: _env_float("MAX_DELAY_SECONDS", 8.0))
    # Prompt containing this word makes the job fail deterministically.
    fail_keyword: str = field(default_factory=lambda: os.environ.get("FAIL_KEYWORD", "fail"))
    # Prompt containing this word simulates a slow provider (client timeout).
    timeout_keyword: str = field(default_factory=lambda: os.environ.get("TIMEOUT_KEYWORD", "timeout"))
    timeout_delay_seconds: float = field(default_factory=lambda: _env_float("TIMEOUT_DELAY_SECONDS", 30.0))
    # Probability [0..1] of a random failure; 0 disables flakiness.
    flaky_rate: float = field(default_factory=lambda: _env_float("FLAKY_RATE", 0.0))

    @property
    def db_path(self) -> Path:
        return self.data_dir / "app.db"

    @property
    def images_dir(self) -> Path:
        return self.data_dir / "images"
