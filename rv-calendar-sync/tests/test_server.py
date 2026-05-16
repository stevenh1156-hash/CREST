from __future__ import annotations

from datetime import date

import pytest
from fastapi.testclient import TestClient

from rv_calendar_sync import server as server_module
from rv_calendar_sync.config import Settings
from rv_calendar_sync.db import Database
from rv_calendar_sync.models import BookingStatus, Platform


@pytest.fixture
def client(tmp_path, monkeypatch):
    settings = Settings(
        db_path=tmp_path / "srv.sqlite",
        admin_token="testtoken",
        public_base_url="http://test",
        interval_minutes=0,
    )
    monkeypatch.setattr("rv_calendar_sync.config._settings", settings)

    def fake_db() -> Database:
        return Database(settings.db_path)

    server_module.app.dependency_overrides[server_module.get_db] = fake_db
    try:
        yield TestClient(server_module.app), fake_db()
    finally:
        server_module.app.dependency_overrides.clear()


def _auth(token: str = "testtoken") -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_create_property_and_booking_and_feed(client):
    c, db = client

    r = c.post("/api/properties", params={"name": "Sprinter Van"}, headers=_auth())
    assert r.status_code == 200
    prop_id = r.json()["id"]

    r = c.post(
        f"/api/properties/{prop_id}/sources",
        params={"platform": "rvshare", "name": "RVshare main"},
        headers=_auth(),
    )
    assert r.status_code == 200
    source = r.json()
    token = source["ical_feed_token"]

    # Create a manual booking
    r = c.post(
        f"/api/properties/{prop_id}/bookings",
        json={
            "property_id": prop_id,
            "start": "2026-06-01",
            "end": "2026-06-05",
            "status": "blocked",
            "summary": "Owner trip",
        },
        headers=_auth(),
    )
    assert r.status_code == 201, r.text

    # Fetch the iCal feed for the RVshare source (no auth - token-protected)
    r = c.get(f"/ical/{prop_id}/rvshare/{token}.ics")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/calendar")
    body = r.text
    assert "BEGIN:VCALENDAR" in body
    assert "DTSTART;VALUE=DATE:20260601" in body


def test_feed_excludes_same_source(client):
    c, db = client
    prop = db.create_property(name="X")
    src_rvshare = db.create_source(prop.id, Platform.RVSHARE, "rvshare", None)
    src_outdoorsy = db.create_source(prop.id, Platform.OUTDOORSY, "outdoorsy", None)

    db.upsert_booking(
        prop.id, Platform.RVSHARE, "r1", date(2026, 6, 1), date(2026, 6, 5),
        BookingStatus.CONFIRMED,
    )
    db.upsert_booking(
        prop.id, Platform.OUTDOORSY, "o1", date(2026, 7, 1), date(2026, 7, 5),
        BookingStatus.CONFIRMED,
    )

    r = c.get(f"/ical/{prop.id}/rvshare/{src_rvshare.ical_feed_token}.ics")
    body = r.text
    # RVshare feed should NOT contain the rvshare-sourced booking
    assert "DTSTART;VALUE=DATE:20260601" not in body
    # ...but SHOULD contain the outdoorsy-sourced one
    assert "DTSTART;VALUE=DATE:20260701" in body

    r = c.get(f"/ical/{prop.id}/outdoorsy/{src_outdoorsy.ical_feed_token}.ics")
    body = r.text
    assert "DTSTART;VALUE=DATE:20260601" in body
    assert "DTSTART;VALUE=DATE:20260701" not in body


def test_admin_endpoints_require_auth(client):
    c, _ = client
    r = c.get("/api/properties")
    assert r.status_code == 401
    r = c.get("/api/properties", headers=_auth("wrong-token"))
    assert r.status_code == 401
    r = c.get("/api/properties", headers=_auth())
    assert r.status_code == 200


def test_health(client):
    c, _ = client
    r = c.get("/health")
    assert r.status_code == 200
    assert r.json() == {"ok": True}


def test_invalid_feed_token_returns_404(client):
    c, db = client
    prop = db.create_property(name="X")
    r = c.get(f"/ical/{prop.id}/rvshare/bogus.ics")
    assert r.status_code == 404
