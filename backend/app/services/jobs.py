"""In-process async job queue: accepted jobs are processed in background tasks."""

from __future__ import annotations

import asyncio
import logging
import random
import uuid

from app.config import Settings
from app.models import AspectRatio, Quality, Style
from app.services.generator import render_image
from app.storage.db import Database

logger = logging.getLogger(__name__)


class JobService:
    """Runs generation jobs as asyncio tasks in the same process.

    Deliberately not Celery/Redis: the task asks for a mock that is honest about
    being single-instance, and job *state* lives in SQLite so it survives restarts.
    """

    def __init__(self, db: Database, settings: Settings) -> None:
        self._db = db
        self._settings = settings
        self._tasks: set[asyncio.Task] = set()

    def submit(
        self,
        user_id: str,
        prompt: str,
        style: Style,
        aspect_ratio: AspectRatio,
        quality: Quality,
    ) -> str:
        job_id = uuid.uuid4().hex
        self._db.create_job(
            job_id=job_id,
            user_id=user_id,
            prompt=prompt,
            style=style,
            aspect_ratio=aspect_ratio,
            quality=quality,
        )
        task = asyncio.create_task(
            self._run(job_id, prompt, style, aspect_ratio, quality)
        )
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        return job_id

    async def _run(
        self,
        job_id: str,
        prompt: str,
        style: Style,
        aspect_ratio: AspectRatio,
        quality: Quality,
    ) -> None:
        try:
            self._db.mark_processing(job_id)
            settings = self._settings
            lower = prompt.lower()

            if settings.timeout_keyword in lower:
                delay = settings.timeout_delay_seconds
            else:
                delay = random.uniform(
                    settings.min_delay_seconds, settings.max_delay_seconds
                )
            await asyncio.sleep(delay)

            if settings.fail_keyword in lower:
                self._db.mark_failed(
                    job_id,
                    error_code="generation_failed",
                    error_message=(
                        "The generator failed to produce an image for this prompt. "
                        "This is a simulated failure — remove 'fail' from the prompt to succeed."
                    ),
                )
                return

            if settings.flaky_rate > 0 and random.random() < settings.flaky_rate:
                self._db.mark_failed(
                    job_id,
                    error_code="generation_failed",
                    error_message="Transient generation error (flaky mode). Please retry.",
                )
                return

            image_path = settings.images_dir / f"{job_id}.png"
            render_image(
                prompt, style, aspect_ratio, quality, image_path, nonce=job_id
            )
            # Store an absolute path: the server may be started from a
            # different working directory later (the data dir is configurable),
            # and a relative path would then point to a non-existent file.
            self._db.mark_succeeded(job_id, str(image_path.resolve()))
        except Exception:
            logger.exception("job %s crashed", job_id)
            self._db.mark_failed(
                job_id,
                error_code="internal_error",
                error_message="Unexpected server error while generating the image.",
            )
