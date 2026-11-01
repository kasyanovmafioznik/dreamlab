PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS users (
    user_id      TEXT PRIMARY KEY,
    tier         TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'premium')),
    created_at   TEXT NOT NULL,
    upgraded_at  TEXT
);

CREATE TABLE IF NOT EXISTS jobs (
    id           TEXT PRIMARY KEY,
    user_id      TEXT NOT NULL,
    prompt       TEXT NOT NULL,
    style        TEXT NOT NULL,
    aspect_ratio TEXT NOT NULL,
    quality      TEXT NOT NULL,
    status       TEXT NOT NULL CHECK (status IN ('queued', 'processing', 'succeeded', 'failed')),
    error_code   TEXT,
    error_message TEXT,
    image_path   TEXT,
    created_at   TEXT NOT NULL,
    finished_at  TEXT
);

CREATE INDEX IF NOT EXISTS idx_jobs_user_created ON jobs (user_id, created_at DESC);
