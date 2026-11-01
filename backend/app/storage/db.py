"""SQLite persistence layer (stdlib sqlite3 — no ORM, on purpose)."""

from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from app.models import AspectRatio, JobStatus, Quality, Style, SubscriptionTier

SCHEMA_PATH = Path(__file__).parent / "schema.sql"


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Database:
    def __init__(self, db_path: Path) -> None:
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA foreign_keys = ON")
        self.init_schema()

    def init_schema(self) -> None:
        self._conn.executescript(SCHEMA_PATH.read_text())
        self._conn.commit()

    def close(self) -> None:
        self._conn.close()

    # -- users / subscription -------------------------------------------------

    def get_or_create_user(self, user_id: str) -> sqlite3.Row:
        row = self._conn.execute(
            "SELECT * FROM users WHERE user_id = ?", (user_id,)
        ).fetchone()
        if row is None:
            self._conn.execute(
                "INSERT INTO users (user_id, tier, created_at) VALUES (?, 'free', ?)",
                (user_id, utcnow()),
            )
            self._conn.commit()
            row = self._conn.execute(
                "SELECT * FROM users WHERE user_id = ?", (user_id,)
            ).fetchone()
        return row

    def set_subscription(self, user_id: str, tier: SubscriptionTier) -> sqlite3.Row:
        now = utcnow()
        upgraded_at = now if tier == SubscriptionTier.premium else None
        self._conn.execute(
            """
            INSERT INTO users (user_id, tier, created_at, upgraded_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET tier = excluded.tier, upgraded_at = excluded.upgraded_at
            """,
            (user_id, tier.value, now, upgraded_at),
        )
        self._conn.commit()
        return self.get_or_create_user(user_id)

    def get_subscription_tier(self, user_id: str) -> SubscriptionTier:
        row = self.get_or_create_user(user_id)
        return SubscriptionTier(row["tier"])

    # -- jobs ------------------------------------------------------------------

    def create_job(
        self,
        job_id: str,
        user_id: str,
        prompt: str,
        style: Style,
        aspect_ratio: AspectRatio,
        quality: Quality,
    ) -> sqlite3.Row:
        self._conn.execute(
            """
            INSERT INTO jobs (id, user_id, prompt, style, aspect_ratio, quality, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 'queued', ?)
            """,
            (job_id, user_id, prompt, style.value, aspect_ratio.value, quality.value, utcnow()),
        )
        self._conn.commit()
        return self.get_job(job_id)

    def get_job(self, job_id: str) -> sqlite3.Row | None:
        return self._conn.execute(
            "SELECT * FROM jobs WHERE id = ?", (job_id,)
        ).fetchone()

    def list_jobs(self, user_id: str, limit: int = 50) -> list[sqlite3.Row]:
        return self._conn.execute(
            "SELECT * FROM jobs WHERE user_id = ? ORDER BY created_at DESC LIMIT ?",
            (user_id, limit),
        ).fetchall()

    def mark_processing(self, job_id: str) -> None:
        self._conn.execute(
            "UPDATE jobs SET status = 'processing' WHERE id = ?", (job_id,)
        )
        self._conn.commit()

    def mark_succeeded(self, job_id: str, image_path: str) -> None:
        self._conn.execute(
            "UPDATE jobs SET status = 'succeeded', image_path = ?, finished_at = ? WHERE id = ?",
            (image_path, utcnow(), job_id),
        )
        self._conn.commit()

    def mark_failed(self, job_id: str, error_code: str, error_message: str) -> None:
        self._conn.execute(
            """
            UPDATE jobs SET status = 'failed', error_code = ?, error_message = ?, finished_at = ?
            WHERE id = ?
            """,
            (error_code, error_message, utcnow(), job_id),
        )
        self._conn.commit()

    def fail_inflight_jobs_on_startup(self) -> int:
        """Jobs left queued/processing by a crashed/restarted process are dead.

        The job queue lives in process memory, so anything not finished before a
        restart cannot resume — we fail it explicitly instead of lying "queued".
        """
        cur = self._conn.execute(
            """
            UPDATE jobs
            SET status = 'failed', error_code = 'server_restarted',
                error_message = 'Server restarted while the job was in flight. Please retry.',
                finished_at = ?
            WHERE status IN ('queued', 'processing')
            """,
            (utcnow(),),
        )
        self._conn.commit()
        return cur.rowcount
