from __future__ import annotations

import hashlib
from datetime import date, datetime, timezone
from typing import Iterable

from icalendar import Calendar, Event

from .models import Booking, BookingStatus, Platform


def _as_date(value) -> date:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        # iCal DATE form YYYYMMDD or YYYY-MM-DD
        s = value.replace("-", "")
        return date(int(s[0:4]), int(s[4:6]), int(s[6:8]))
    raise ValueError(f"Cannot convert {value!r} to date")


def parse_ical_feed(
    body: bytes | str,
    property_id: str,
    source: Platform,
) -> list[dict]:
    """Parse an iCal feed body and return a list of normalized event dicts.

    Each event dict has keys: source_uid, start, end, status, summary, guest_name, raw.
    """
    cal = Calendar.from_ical(body)
    events: list[dict] = []
    for component in cal.walk("VEVENT"):
        dtstart = component.get("DTSTART")
        dtend = component.get("DTEND")
        if not dtstart or not dtend:
            continue
        start = _as_date(dtstart.dt)
        end = _as_date(dtend.dt)
        if end <= start:
            # Some platforms emit single-day all-day events with DTEND == DTSTART;
            # treat as one-night stay.
            end = date.fromordinal(start.toordinal() + 1)

        raw_status = str(component.get("STATUS", "") or "").upper()
        if raw_status == "CANCELLED":
            status = BookingStatus.CANCELLED
        elif raw_status == "TENTATIVE":
            status = BookingStatus.TENTATIVE
        else:
            status = BookingStatus.CONFIRMED

        summary = str(component.get("SUMMARY", "") or "") or None
        uid = str(component.get("UID", "") or "").strip()
        if not uid:
            # Synthesize a stable UID from source + dates + summary
            material = f"{source.value}|{property_id}|{start.isoformat()}|{end.isoformat()}|{summary or ''}"
            uid = hashlib.sha1(material.encode("utf-8")).hexdigest() + "@synth"

        events.append(
            {
                "source_uid": uid,
                "start": start,
                "end": end,
                "status": status,
                "summary": summary,
                "guest_name": _extract_guest_name(summary),
                "raw": {
                    "description": str(component.get("DESCRIPTION", "") or "") or None,
                    "location": str(component.get("LOCATION", "") or "") or None,
                },
            }
        )
    return events


def _extract_guest_name(summary: str | None) -> str | None:
    if not summary:
        return None
    # Common platform patterns: "Reserved - Jane Doe", "CLOSED - Not available", etc.
    for sep in (" - ", ": ", " | "):
        if sep in summary:
            after = summary.split(sep, 1)[1].strip()
            if after and "not available" not in after.lower() and "closed" not in after.lower():
                return after
    return None


def build_ical_feed(
    bookings: Iterable[Booking],
    property_name: str,
    platform: Platform,
    feed_prodid: str = "-//rv-calendar-sync//EN",
) -> bytes:
    """Build an iCal feed of bookings, suitable for a remote platform to import.

    Cancelled bookings are emitted with STATUS:CANCELLED so platforms can release blocks.
    The summary is intentionally generic ("Reserved" / "Blocked") to avoid leaking guest
    PII to third-party platforms.
    """
    cal = Calendar()
    cal.add("prodid", feed_prodid)
    cal.add("version", "2.0")
    cal.add("x-wr-calname", f"{property_name} - {platform.value}")
    cal.add("calscale", "GREGORIAN")
    cal.add("method", "PUBLISH")

    now = datetime.now(timezone.utc)
    for b in bookings:
        ev = Event()
        ev.add("uid", f"{b.id}@rv-calendar-sync")
        ev.add("dtstamp", now)
        ev.add("dtstart", b.start)
        ev.add("dtend", b.end)
        if b.status == BookingStatus.CANCELLED:
            ev.add("status", "CANCELLED")
        elif b.status == BookingStatus.TENTATIVE:
            ev.add("status", "TENTATIVE")
        else:
            ev.add("status", "CONFIRMED")

        if b.status == BookingStatus.BLOCKED:
            label = "Blocked"
        else:
            label = "Reserved"
        ev.add("summary", f"{label} ({b.source.value})")
        ev.add("transp", "OPAQUE")
        cal.add_component(ev)

    return cal.to_ical()
