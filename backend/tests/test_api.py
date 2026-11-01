"""API tests: happy path, payment gate, error triggers, restart persistence."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

USER = "11111111-2222-3333-4444-555555555555"


@pytest.fixture()
def client(tmp_path):
    settings = Settings(
        data_dir=tmp_path,
        min_delay_seconds=0.05,
        max_delay_seconds=0.1,
        timeout_delay_seconds=5.0,
        flaky_rate=0.0,
    )
    app = create_app(settings)
    with TestClient(app) as c:
        yield c


def poll_until_done(client: TestClient, job_id: str, timeout: float = 5.0) -> dict:
    import time

    deadline = time.time() + timeout
    while time.time() < deadline:
        r = client.get(f"/v1/generations/{job_id}")
        assert r.status_code == 200
        body = r.json()
        if body["status"] in ("succeeded", "failed"):
            return body
        time.sleep(0.05)
    pytest.fail("job did not finish in time")


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_options_catalog(client):
    body = client.get("/v1/options").json()
    assert any(o["premium"] for o in body["styles"])
    assert any(not o["premium"] for o in body["qualities"])
    assert {o["id"] for o in body["aspect_ratios"]} == {"1:1", "16:9", "9:16", "21:9"}


def test_generate_happy_path(client):
    r = client.post(
        "/v1/generations",
        json={"user_id": USER, "prompt": "a red fox in snow", "style": "illustration"},
    )
    assert r.status_code == 202
    job_id = r.json()["id"]
    assert r.json()["poll_url"] == f"/v1/generations/{job_id}"

    body = poll_until_done(client, job_id)
    assert body["status"] == "succeeded"
    assert body["image_url"] == f"/v1/generations/{job_id}/image"

    img = client.get(body["image_url"])
    assert img.status_code == 200
    assert img.headers["content-type"] == "image/png"
    assert img.content[:8] == b"\x89PNG\r\n\x1a\n"


def test_premium_option_rejected_for_free_user(client):
    r = client.post(
        "/v1/generations",
        json={
            "user_id": USER,
            "prompt": "neon city",
            "style": "cyberpunk",  # premium style
        },
    )
    assert r.status_code == 402
    err = r.json()["error"]
    assert err["code"] == "premium_required"
    assert "style:cyberpunk" in err["details"]["required_options"]
    assert "upgrade_url" in err["details"]


def test_premium_allowed_after_upgrade(client):
    client.post(f"/v1/users/{USER}/subscription/upgrade")
    r = client.post(
        "/v1/generations",
        json={"user_id": USER, "prompt": "neon city", "style": "cyberpunk", "quality": "hd"},
    )
    assert r.status_code == 202
    body = poll_until_done(client, r.json()["id"])
    assert body["status"] == "succeeded"
    assert body["quality"] == "hd"


def test_subscription_defaults_to_free(client):
    body = client.get(f"/v1/users/{USER}/subscription").json()
    assert body["tier"] == "free"
    assert body["upgraded_at"] is None


def test_fail_keyword_trigger(client):
    r = client.post(
        "/v1/generations",
        json={"user_id": USER, "prompt": "please fail this on purpose"},
    )
    assert r.status_code == 202
    body = poll_until_done(client, r.json()["id"])
    assert body["status"] == "failed"
    assert body["error"]["code"] == "generation_failed"


def test_timeout_keyword_keeps_job_processing(client):
    r = client.post(
        "/v1/generations",
        json={"user_id": USER, "prompt": "timeout after a while"},
    )
    job_id = r.json()["id"]
    import time

    time.sleep(0.5)  # far below timeout_delay_seconds=5
    body = client.get(f"/v1/generations/{job_id}").json()
    assert body["status"] in ("queued", "processing")


def test_unknown_job_404(client):
    r = client.get("/v1/generations/deadbeef")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "not_found"


def test_job_of_another_user_is_not_visible(client):
    """The client sends its anonymous id on every request — a foreign job
    must look like it does not exist."""
    other = "99999999-8888-4777-8666-555555555555"
    job_id = client.post(
        "/v1/generations",
        json={"user_id": USER, "prompt": "private picture", "style": "minimal"},
    ).json()["id"]
    poll_until_done(client, job_id)

    own = client.get(f"/v1/generations/{job_id}", params={"user_id": USER})
    assert own.status_code == 200

    foreign = client.get(f"/v1/generations/{job_id}", params={"user_id": other})
    assert foreign.status_code == 404
    assert foreign.json()["error"]["code"] == "not_found"

    foreign_img = client.get(
        f"/v1/generations/{job_id}/image", params={"user_id": other}
    )
    assert foreign_img.status_code == 404


def test_validation_error_shape(client):
    r = client.post("/v1/generations", json={"user_id": USER, "prompt": "x"})
    assert r.status_code == 422
    err = r.json()["error"]
    assert err["code"] == "validation_error"
    assert any(f["field"] == "prompt" for f in err["details"]["fields"])


def test_list_generations(client):
    for prompt in ("first one", "second one"):
        client.post("/v1/generations", json={"user_id": USER, "prompt": prompt})
    items = client.get("/v1/generations", params={"user_id": USER}).json()["items"]
    assert len(items) == 2
    # other users' history is not visible
    other = client.get(
        "/v1/generations", params={"user_id": "99999999-0000-0000-0000-000000000000"}
    ).json()["items"]
    assert other == []


def test_state_survives_restart(tmp_path):
    """Same DATA_DIR + new app instance: history and subscription persist;
    in-flight jobs are failed explicitly (honest about the lost queue)."""
    s = Settings(data_dir=tmp_path, min_delay_seconds=0.05, max_delay_seconds=0.1)
    with TestClient(create_app(s)) as c1:
        c1.post(f"/v1/users/{USER}/subscription/upgrade")
        r = c1.post("/v1/generations", json={"user_id": USER, "prompt": "persist me"})
        job_id = r.json()["id"]
        poll_until_done(c1, job_id)

    with TestClient(create_app(s)) as c2:
        sub = c2.get(f"/v1/users/{USER}/subscription").json()
        assert sub["tier"] == "premium"
        items = c2.get("/v1/generations", params={"user_id": USER}).json()["items"]
        assert len(items) == 1
        assert items[0]["id"] == job_id
        assert items[0]["status"] == "succeeded"
        img = c2.get(items[0]["image_url"])
        assert img.status_code == 200


def test_inflight_job_fails_after_restart(tmp_path):
    s = Settings(data_dir=tmp_path, min_delay_seconds=30, max_delay_seconds=60)
    with TestClient(create_app(s)) as c1:
        r = c1.post(
            "/v1/generations", json={"user_id": USER, "prompt": "a very slow one"}
        )
        job_id = r.json()["id"]

    with TestClient(create_app(s)) as c2:
        body = c2.get(f"/v1/generations/{job_id}").json()
        assert body["status"] == "failed"
        assert body["error"]["code"] == "server_restarted"
