from __future__ import annotations

from datetime import date

from rv_calendar_sync.models import BookingStatus, Platform


def test_create_property_and_source(db):
    prop = db.create_property(name="Sprinter Van")
    src = db.create_source(
        property_id=prop.id,
        platform=Platform.RVSHARE,
        name="RVshare listing",
        ical_read_url="https://example.com/cal.ics",
    )
    assert src.ical_feed_token
    assert db.get_source(src.id).id == src.id

    looked_up = db.get_source_by_token(prop.id, Platform.RVSHARE, src.ical_feed_token)
    assert looked_up is not None
    assert looked_up.id == src.id


def test_upsert_booking_idempotent(db):
    prop = db.create_property(name="Sprinter Van")
    b1, created1 = db.upsert_booking(
        property_id=prop.id,
        source=Platform.BOOKING,
        source_uid="abc",
        start=date(2026, 6, 1),
        end=date(2026, 6, 5),
        status=BookingStatus.CONFIRMED,
    )
    assert created1 is True
    b2, created2 = db.upsert_booking(
        property_id=prop.id,
        source=Platform.BOOKING,
        source_uid="abc",
        start=date(2026, 6, 2),
        end=date(2026, 6, 5),
        status=BookingStatus.CONFIRMED,
    )
    assert created2 is False
    assert b2.id == b1.id
    assert b2.start == date(2026, 6, 2)


def test_cancel_missing(db):
    prop = db.create_property(name="X")
    for uid in ("a", "b", "c"):
        db.upsert_booking(
            property_id=prop.id,
            source=Platform.OUTDOORSY,
            source_uid=uid,
            start=date(2026, 6, 1),
            end=date(2026, 6, 5),
            status=BookingStatus.CONFIRMED,
        )
    cancelled = db.cancel_missing(prop.id, Platform.OUTDOORSY, seen_uids={"a"})
    assert cancelled == 2
    active = db.list_bookings(prop.id)
    assert {b.source_uid for b in active} == {"a"}
    all_inc = db.list_bookings(prop.id, include_cancelled=True)
    assert len(all_inc) == 3


def test_list_excludes_source(db):
    prop = db.create_property(name="X")
    db.upsert_booking(
        prop.id, Platform.RVSHARE, "r1", date(2026, 6, 1), date(2026, 6, 5),
        BookingStatus.CONFIRMED,
    )
    db.upsert_booking(
        prop.id, Platform.OUTDOORSY, "o1", date(2026, 7, 1), date(2026, 7, 5),
        BookingStatus.CONFIRMED,
    )
    filtered = db.list_bookings(prop.id, exclude_source=Platform.RVSHARE)
    assert len(filtered) == 1
    assert filtered[0].source == Platform.OUTDOORSY
