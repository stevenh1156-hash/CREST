from __future__ import annotations

import httpx
import pytest
import respx

from rv_calendar_sync.models import BookingStatus, Platform
from rv_calendar_sync.sync import sync_source

RVSHARE_FEED = b"""BEGIN:VCALENDAR
PRODID:-//RVshare//EN
VERSION:2.0
BEGIN:VEVENT
UID:rvshare-1@rvshare.com
DTSTAMP:20260101T000000Z
DTSTART;VALUE=DATE:20260801
DTEND;VALUE=DATE:20260805
SUMMARY:Reserved - Sam Smith
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR
"""

RVSHARE_FEED_AFTER_CANCEL = b"""BEGIN:VCALENDAR
PRODID:-//RVshare//EN
VERSION:2.0
BEGIN:VEVENT
UID:rvshare-2@rvshare.com
DTSTAMP:20260101T000000Z
DTSTART;VALUE=DATE:20260901
DTEND;VALUE=DATE:20260905
SUMMARY:Reserved - New Guest
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR
"""


@pytest.mark.asyncio
@respx.mock
async def test_sync_ical_pull_source_creates_then_cancels(db):
    prop = db.create_property(name="Test RV")
    src = db.create_source(
        property_id=prop.id,
        platform=Platform.RVSHARE,
        name="RVshare main",
        ical_read_url="https://rvshare.example/cal.ics",
    )

    respx.get("https://rvshare.example/cal.ics").mock(
        return_value=httpx.Response(200, content=RVSHARE_FEED)
    )
    result1 = await sync_source(db, src.id)
    assert result1.fetched == 1
    assert result1.created == 1
    assert result1.cancelled == 0
    assert result1.errors == []

    bookings = db.list_bookings(prop.id)
    assert len(bookings) == 1
    assert bookings[0].source == Platform.RVSHARE
    assert bookings[0].status == BookingStatus.CONFIRMED

    # Second sync - first booking is gone, second appears
    respx.get("https://rvshare.example/cal.ics").mock(
        return_value=httpx.Response(200, content=RVSHARE_FEED_AFTER_CANCEL)
    )
    result2 = await sync_source(db, src.id)
    assert result2.created == 1
    assert result2.cancelled == 1

    active = db.list_bookings(prop.id)
    assert len(active) == 1
    assert active[0].source_uid == "rvshare-2@rvshare.com"

    all_inc = db.list_bookings(prop.id, include_cancelled=True)
    assert len(all_inc) == 2


@pytest.mark.asyncio
@respx.mock
async def test_sync_ical_pull_push_is_noop(db):
    """iCal-pull-only sources should not error on push; they just report 0."""
    prop = db.create_property(name="Test RV")
    src = db.create_source(
        property_id=prop.id,
        platform=Platform.OUTDOORSY,
        name="Outdoorsy",
        ical_read_url="https://outdoorsy.example/cal.ics",
    )
    respx.get("https://outdoorsy.example/cal.ics").mock(
        return_value=httpx.Response(200, content=b"BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//x//EN\nEND:VCALENDAR\n")
    )
    result = await sync_source(db, src.id)
    assert result.errors == []
    assert result.pushed == 0


@pytest.mark.asyncio
@respx.mock
async def test_sync_fetch_error_recorded_but_does_not_crash(db):
    prop = db.create_property(name="Test RV")
    src = db.create_source(
        property_id=prop.id,
        platform=Platform.BOOKING,
        name="Booking.com",
        ical_read_url="https://booking.example/cal.ics",
    )
    respx.get("https://booking.example/cal.ics").mock(
        return_value=httpx.Response(500)
    )
    result = await sync_source(db, src.id)
    assert result.errors and "fetch" in result.errors[0]
    assert result.fetched == 0
