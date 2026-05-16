from __future__ import annotations

import logging
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import Depends, FastAPI, HTTPException, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import get_settings
from .db import Database
from .ical_utils import build_ical_feed
from .models import (
    Booking,
    BookingCreate,
    BookingStatus,
    Platform,
    Property,
    Source,
    SyncResult,
)
from .sync import sync_all, sync_source

log = logging.getLogger(__name__)
_bearer = HTTPBearer(auto_error=False)


def get_db() -> Database:
    return Database(get_settings().db_path)


def require_admin(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> None:
    expected = get_settings().admin_token
    if not creds or creds.credentials != expected:
        raise HTTPException(status_code=401, detail="invalid admin token")


@asynccontextmanager
async def _lifespan(app: FastAPI):
    settings = get_settings()
    scheduler: AsyncIOScheduler | None = None
    if settings.interval_minutes > 0:
        scheduler = AsyncIOScheduler(timezone="UTC")
        scheduler.add_job(
            _scheduled_sync,
            "interval",
            minutes=settings.interval_minutes,
            next_run_time=datetime.now(timezone.utc),
        )
        scheduler.start()
        log.info("scheduler started: every %s min", settings.interval_minutes)
    try:
        yield
    finally:
        if scheduler:
            scheduler.shutdown(wait=False)


async def _scheduled_sync() -> None:
    db = get_db()
    try:
        results = await sync_all(db)
        log.info("scheduled sync done: %s sources", len(results))
    except Exception:
        log.exception("scheduled sync failed")


app = FastAPI(title="RV Calendar Sync", version="0.1.0", lifespan=_lifespan)


# ---------- Public iCal feeds (no auth - secured by per-source token) ----------

@app.get(
    "/ical/{property_id}/{platform}/{token}.ics",
    response_class=Response,
    tags=["ical"],
)
def get_ical_feed(
    property_id: str,
    platform: Platform,
    token: str,
    db: Database = Depends(get_db),
):
    """The iCal feed a remote platform should subscribe to.

    Excludes bookings that originated from `platform` itself (avoids feedback loops).
    """
    src = db.get_source_by_token(property_id, platform, token)
    if src is None:
        raise HTTPException(status_code=404, detail="feed not found")
    prop = db.get_property(property_id)
    if prop is None:
        raise HTTPException(status_code=404, detail="property not found")
    bookings = db.list_bookings(
        property_id, exclude_source=platform, include_cancelled=True
    )
    body = build_ical_feed(bookings, prop.name, platform)
    return Response(
        content=body,
        media_type="text/calendar; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{prop.name}-{platform.value}.ics"'},
    )


# ---------- Admin: properties ----------

@app.post(
    "/api/properties",
    response_model=Property,
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
def create_property(name: str, db: Database = Depends(get_db)) -> Property:
    return db.create_property(name=name)


@app.get(
    "/api/properties",
    response_model=list[Property],
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
def list_properties(db: Database = Depends(get_db)) -> list[Property]:
    return db.list_properties()


# ---------- Admin: sources ----------

@app.post(
    "/api/properties/{property_id}/sources",
    response_model=Source,
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
def create_source(
    property_id: str,
    platform: Platform,
    name: str,
    ical_read_url: str | None = None,
    api_credentials: dict | None = None,
    db: Database = Depends(get_db),
) -> Source:
    if db.get_property(property_id) is None:
        raise HTTPException(status_code=404, detail="property not found")
    return db.create_source(
        property_id=property_id,
        platform=platform,
        name=name,
        ical_read_url=ical_read_url,
        api_credentials=api_credentials,
    )


@app.get(
    "/api/properties/{property_id}/sources",
    response_model=list[Source],
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
def list_sources(property_id: str, db: Database = Depends(get_db)) -> list[Source]:
    return db.list_sources(property_id=property_id)


@app.get(
    "/api/properties/{property_id}/sources/{source_id}/feed-url",
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
def feed_url(property_id: str, source_id: str, db: Database = Depends(get_db)) -> dict:
    src = db.get_source(source_id)
    if src is None or src.property_id != property_id:
        raise HTTPException(status_code=404, detail="source not found")
    base = get_settings().public_base_url.rstrip("/")
    return {
        "url": f"{base}/ical/{property_id}/{src.platform.value}/{src.ical_feed_token}.ics",
        "instructions": (
            f"Paste this URL into the 'Import calendar' field on {src.platform.value}."
        ),
    }


# ---------- Admin: bookings ----------

@app.get(
    "/api/properties/{property_id}/bookings",
    response_model=list[Booking],
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
def list_bookings(
    property_id: str,
    include_cancelled: bool = False,
    db: Database = Depends(get_db),
) -> list[Booking]:
    return db.list_bookings(property_id, include_cancelled=include_cancelled)


@app.post(
    "/api/properties/{property_id}/bookings",
    response_model=Booking,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
def create_manual_booking(
    property_id: str,
    payload: BookingCreate,
    db: Database = Depends(get_db),
) -> Booking:
    if payload.property_id != property_id:
        raise HTTPException(status_code=400, detail="property_id mismatch")
    if payload.end <= payload.start:
        raise HTTPException(status_code=400, detail="end must be after start")
    booking, _ = db.upsert_booking(
        property_id=property_id,
        source=Platform.MANUAL,
        source_uid=f"manual-{uuid.uuid4().hex}",
        start=payload.start,
        end=payload.end,
        status=payload.status or BookingStatus.BLOCKED,
        summary=payload.summary,
        guest_name=payload.guest_name,
    )
    return booking


@app.delete(
    "/api/bookings/{booking_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
def delete_booking(booking_id: str, db: Database = Depends(get_db)) -> Response:
    b = db.get_booking(booking_id)
    if b is None:
        raise HTTPException(status_code=404, detail="booking not found")
    if b.source != Platform.MANUAL:
        # For non-manual bookings, deletion is unsafe (they'd reappear on next sync).
        # Mark as cancelled instead - this is preserved in the outbound feed.
        db.upsert_booking(
            property_id=b.property_id,
            source=b.source,
            source_uid=b.source_uid,
            start=b.start,
            end=b.end,
            status=BookingStatus.CANCELLED,
            summary=b.summary,
            guest_name=b.guest_name,
            raw=b.raw,
        )
    else:
        db.delete_booking(booking_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------- Admin: sync ----------

@app.post(
    "/api/sync",
    response_model=list[SyncResult],
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
async def trigger_sync(
    property_id: str | None = None, db: Database = Depends(get_db)
) -> list[SyncResult]:
    return await sync_all(db, property_id=property_id)


@app.post(
    "/api/sources/{source_id}/sync",
    response_model=SyncResult,
    dependencies=[Depends(require_admin)],
    tags=["admin"],
)
async def trigger_source_sync(
    source_id: str, db: Database = Depends(get_db)
) -> SyncResult:
    return await sync_source(db, source_id)


@app.get("/health", tags=["meta"])
def health() -> dict:
    return {"ok": True}
