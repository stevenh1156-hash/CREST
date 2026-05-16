from __future__ import annotations

import logging

import httpx

from .db import Database
from .models import BookingStatus, Platform, SyncResult
from .sources import get_source_class

log = logging.getLogger(__name__)


async def sync_source(db: Database, source_id: str) -> SyncResult:
    """Pull from a single source, upsert into DB, then push the merged calendar back."""
    src = db.get_source(source_id)
    if src is None:
        raise ValueError(f"Source {source_id} not found")

    result = SyncResult(source_id=src.id, platform=src.platform)
    if not src.enabled:
        result.errors.append("source disabled")
        return result

    adapter = get_source_class(src.platform)(src)

    async with httpx.AsyncClient(follow_redirects=True) as client:
        # ---- PULL ----
        try:
            events = await adapter.fetch(client)
        except Exception as e:  # surface fetch errors but continue with push
            log.exception("fetch failed for %s", src.id)
            result.errors.append(f"fetch: {e}")
            events = []

        result.fetched = len(events)
        seen_uids: set[str] = set()
        for ev in events:
            seen_uids.add(ev["source_uid"])
            _, created = db.upsert_booking(
                property_id=src.property_id,
                source=src.platform,
                source_uid=ev["source_uid"],
                start=ev["start"],
                end=ev["end"],
                status=ev["status"],
                summary=ev.get("summary"),
                guest_name=ev.get("guest_name"),
                raw=ev.get("raw") or {},
            )
            if created:
                result.created += 1
            else:
                result.updated += 1

        if events:
            # Only cancel-prune when the fetch succeeded with at least one event;
            # an empty fetch could be a transient error and we don't want to nuke
            # every confirmed booking.
            result.cancelled = db.cancel_missing(
                property_id=src.property_id, source=src.platform, seen_uids=seen_uids
            )

        db.mark_source_synced(src.id)

        # ---- PUSH ----
        # Other-source bookings get pushed to this platform (so its calendar
        # blocks the dates). Exclude this platform's own bookings to avoid loops.
        outbound = [
            b
            for b in db.list_bookings(src.property_id, exclude_source=src.platform)
            if b.status != BookingStatus.CANCELLED
        ]
        try:
            active, count = await adapter.push(client, outbound)
            if active:
                result.pushed = count
                db.mark_source_pushed(src.id)
        except Exception as e:
            log.exception("push failed for %s", src.id)
            result.errors.append(f"push: {e}")

    return result


async def sync_all(db: Database, property_id: str | None = None) -> list[SyncResult]:
    sources = db.list_sources(property_id=property_id)
    results: list[SyncResult] = []
    for src in sources:
        if src.platform == Platform.MANUAL:
            # Manual has nothing to fetch and nothing to push - it's an origin only.
            continue
        results.append(await sync_source(db, src.id))
    return results
