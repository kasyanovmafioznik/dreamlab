# Backend — Mock AI Image Generation API

> Полное описание проекта (продукт, граница клиент/сервер, решения, работа с AI) —
> в [README.md](../README.md) в корне репозитория. Этот файл — справочник по
> самому сервису.

FastAPI + SQLite + Pillow. No external services, no API keys, no internet required —
"generation" is a local PNG render with a configurable delay.

## Run

### Docker (recommended for verification)

The compose file lives in the **repository root** (build context = `./backend`):

```bash
docker compose up --build            # add --wait to block until the healthcheck passes
# → http://localhost:8000  (interactive docs at /docs)
```

State (SQLite + generated images) lives in `backend/data/` via a bind mount —
it survives `docker compose down` / restarts. The container listens on
`0.0.0.0:8000`, so it is reachable from the host as `http://localhost:8000`
(and from a real iOS device via the Mac's LAN IP).

### Local (no Docker)

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --reload --port 8000
```

### Tests

```bash
.venv/bin/python -m pytest tests/ -q          # locally — 14 passed
docker compose run --rm api pytest tests/ -q   # inside the image
```

## API

Interactive docs: `GET /docs` (OpenAPI auto-generated).

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness `{"status":"ok"}` |
| GET | `/v1/options` | Option catalog (styles / aspect ratios / qualities, `premium` flags). The client renders pickers from this — it does not hardcode the catalog. |
| POST | `/v1/generations` | Accept a job → `202 {id, poll_url}` |
| GET | `/v1/generations/{id}?user_id=` | Poll job status → `queued \| processing \| succeeded \| failed` (+ `image_url` or `error`). A job belonging to another `user_id` is reported as `not_found` |
| GET | `/v1/generations/{id}/image?user_id=` | PNG bytes (only when `succeeded`) |
| GET | `/v1/generations?user_id=` | Server-side history for a user |
| GET | `/v1/users/{id}/subscription` | `{tier: free\|premium}` (defaults to `free`) |
| POST | `/v1/users/{id}/subscription/upgrade` | Mock purchase — no billing |

### Error envelope

All errors are `{"error": {"code", "message", "details"?}}`.

### API style: async job + polling (202 + poll)

Chosen over SSE/websockets: polling survives mobile network blips without
reconnect logic, job state lives in SQLite and is therefore restart-safe, and
it is trivial to reason about from any client. The client polls with a small
interval (e.g. 0.5 s → 2 s backoff).

## Reproduce errors on purpose

| Scenario | How to trigger | What you get |
|---|---|---|
| Generation failure | Put the word **`fail`** anywhere in the prompt | Job → `failed`, `error.code = "generation_failed"`, retryable |
| Server too slow (client timeout) | Put the word **`timeout`** in the prompt | Job stays `processing` for `TIMEOUT_DELAY_SECONDS` (default 30 s) — longer than any sane client timeout |
| Premium gate | Free user sends premium style/quality/aspect | **402** `premium_required` with `details.required_options` and `upgrade_url` |
| Random failures | Start with `FLAKY_RATE=0.2 docker compose up` | ~20 % of jobs fail with a transient error |
| Restart kills in-flight jobs | Restart the server while a job is `processing` | Job becomes `failed` with `error.code = "server_restarted"` (history/subscription survive — see tests) |
| Malformed/unknown ids | `GET /v1/generations/doesnotexist` | 404 `not_found` |
| Foreign job | `GET /v1/generations/<id>?user_id=<other>` | 404 `not_found` — history is isolated per anonymous id |
| Invalid body | `prompt` shorter than 3 chars | 422 `validation_error` with per-field messages |

Env knobs: `DATA_DIR`, `MIN_DELAY_SECONDS` (3), `MAX_DELAY_SECONDS` (8),
`FAIL_KEYWORD` (`fail`), `TIMEOUT_KEYWORD` (`timeout`), `TIMEOUT_DELAY_SECONDS` (30),
`FLAKY_RATE` (0).

## Design decisions

- **SQLite** — the task is single-instance; a file DB survives restarts with zero
  ops. No Postgres on purpose (would be over-engineering for a mock).
- **In-process asyncio queue, not Celery** — same reason. Durability comes from
  the DB: on startup any `queued`/`processing` rows are explicitly failed
  (`server_restarted`) instead of pretending they will resume.
- **Premium is enforced server-side only** — the client hiding a button is
  cosmetic; `POST /v1/generations` checks the user's tier against the catalog
  and returns 402 before any work starts.
- **Procedural art engine (Pillow only)** — no diffusion model, but not a flat
  gradient either: layered fBm noise, per-style scenes (sunset landscapes with
  water reflections, cyberpunk skylines with neon grids, watercolor washes,
  geometric illustration/minimal), prompt keywords (`forest`, `city`, `night`,
  `water`, `sunset`, `moon`, `stars`…) pick the elements. Deterministic per
  (prompt, style, aspect, quality); a per-request nonce (job id) makes every
  generation a fresh variation. The image embeds the prompt and options in
  a glass caption so you can verify the round trip. Renders in ~0.5–2 s even
  at 4K — no new dependencies beyond Pillow.
