from __future__ import annotations

from datetime import date, datetime, timezone

from rv_calendar_sync.ical_utils import build_ical_feed, parse_ical_feed
from rv_calendar_sync.models import Booking, BookingStatus, Platform

SAMPLE = b"""BEGIN:VCALENDAR
PRODID:-//RVshare//EN
VERSION:2.0
BEGIN:VEVENT
UID:rvshare-12345@rvshare.com
DTSTAMP:20260101T000000Z
DTSTART;VALUE=DATE:20260601
DTEND;VALUE=DATE:20260605
SUMMARY:Reserved - Jane Doe
STATUS:CONFIRMED
END:VEVENT
BEGIN:VEVENT
UID:rvshare-67890@rvshare.com
DTSTAMP:20260101T000000Z
DTSTART;VALUE=DATE:20260701
DTEND;VALUE=DATE:20260705
SUMMARY:CLOSED - Not available
STATUS:CANCELLED
END:VEVENT
END:VCALENDAR
"""


def test_parse_ical_feed_extracts_events():
    events = parse_ical_feed(SAMPLE, property_id="prop-1", source=Platform.RVSHARE)
    assert len(events) == 2

    a, b = events
    assert a["source_uid"] == "rvshare-12345@rvshare.com"
    assert a["start"] == date(2026, 6, 1)
    assert a["end"] == date(2026, 6, 5)
    assert a["status"] == BookingStatus.CONFIRMED
    assert a["guest_name"] == "Jane Doe"

    assert b["status"] == BookingStatus.CANCELLED
    # "Not available" should not be extracted as a guest name
    assert b["guest_name"] is None


def test_parse_ical_synthesizes_uid_when_missing():
    body = b"""BEGIN:VCALENDAR\r
VERSION:2.0\r
PRODID:-//x//EN\r
BEGIN:VEVENT\r
DTSTART;VALUE=DATE:20260601\r
DTEND;VALUE=DATE:20260605\r
SUMMARY:Blocked\r
END:VEVENT\r
END:VCALENDAR\r
"""
    events = parse_ical_feed(body, property_id="prop-1", source=Platform.BOOKING)
    assert len(events) == 1
    assert events[0]["source_uid"].endswith("@synth")


def test_build_ical_feed_roundtrip():
    bookings = [
        Booking(
            id="b1",
            property_id="prop-1",
            source=Platform.MANUAL,
            source_uid="manual-1",
            start=date(2026, 6, 1),
            end=date(2026, 6, 5),
            status=BookingStatus.BLOCKED,
            summary="Owner trip",
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        ),
        Booking(
            id="b2",
            property_id="prop-1",
            source=Platform.BOOKING,
            source_uid="bdc-99",
            start=date(2026, 7, 10),
            end=date(2026, 7, 15),
            status=BookingStatus.CONFIRMED,
            summary="Reservation",
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        ),
    ]
    body = build_ical_feed(bookings, property_name="Big Sky RV", platform=Platform.RVSHARE)
    parsed = parse_ical_feed(body, property_id="prop-1", source=Platform.RVSHARE)
    assert len(parsed) == 2
    uids = {e["source_uid"] for e in parsed}
    assert "b1@rv-calendar-sync" in uids
    assert "b2@rv-calendar-sync" in uids


def test_build_ical_feed_marks_cancelled():
    bookings = [
        Booking(
            id="b1",
            property_id="prop-1",
            source=Platform.RVSHARE,
            source_uid="rvshare-1",
            start=date(2026, 6, 1),
            end=date(2026, 6, 5),
            status=BookingStatus.CANCELLED,
            summary=None,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        ),
    ]
    body = build_ical_feed(bookings, property_name="X", platform=Platform.OUTDOORSY)
    assert b"STATUS:CANCELLED" in body
