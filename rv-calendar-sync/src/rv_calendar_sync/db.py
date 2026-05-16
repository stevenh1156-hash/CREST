from __future__ import annotations

import json
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Iterator

from .models import Booking, BookingStatus, Platform, Property, Source

SCHEMA = """
CREATE TABLE IF NOT EXISTS property (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS source (
    id                TEXT PRIMARY KEY,
    property_id       TEXT NOT NULL REFERENCES property(id) ON DELETE CASCADE,
    platform          TEXT NOT NULL,
    name              TEXT NOT NULL,
    ical_read_url     TEXT,
    ical_feed_token   TEXT NOT NULL,
    api_credentials   TEXT NOT NULL DEFAULT '{}',
    last_synced_at    TEXT,
    last_pushed_at    TEXT,
    enabled           INTEGER NOT NULL DEFAULT 1,
    UNIQUE (property_id, platform, name)
);

CREATE TABLE IF NOT EXISTS booking (
    id            TEXT PRIMARY KEY,
    property_id   TEXT NOT NULL REFERENCES property(id) ON DELETE CASCADE,
    source        TEXT NOT NULL,
    source_uid    TEXT NOT NULL,
    start_date    TEXT NOT NULL,
    end_date      TEXT NOT NULL,
    status        TEXT NOT NULL,
    summary       TEXT,
    guest_name    TEXT,
    raw           TEXT NOT NULL DEFAULT '{}',
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    UNIQUE (property_id, source, source_uid)
);

CREATE INDEX IF NOT EXISTS idx_booking_property_dates
    ON booking (property_id, start_date, end_date);
"""


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_dt(s: str | None) -> datetime | None:
    return datetime.fromisoformat(s) if s else None


class Database:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        return conn

    @contextmanager
    def cursor(self) -> Iterator[sqlite3.Cursor]:
        conn = self._connect()
        try:
            cur = conn.cursor()
            cur.execute("BEGIN")
            yield cur
            cur.execute("COMMIT")
        except Exception:
            cur.execute("ROLLBACK")
            raise
        finally:
            conn.close()

    def _init_schema(self) -> None:
        conn = self._connect()
        try:
            conn.executescript(SCHEMA)
        finally:
            conn.close()

    # ---------- Property ----------

    def create_property(self, name: str) -> Property:
        prop = Property(id=str(uuid.uuid4()), name=name, created_at=datetime.now(timezone.utc))
        with self.cursor() as cur:
            cur.execute(
                "INSERT INTO property (id, name, created_at) VALUES (?, ?, ?)",
                (prop.id, prop.name, prop.created_at.isoformat()),
            )
        return prop

    def get_property(self, property_id: str) -> Property | None:
        conn = self._connect()
        try:
            row = conn.execute("SELECT * FROM property WHERE id = ?", (property_id,)).fetchone()
        finally:
            conn.close()
        return _row_to_property(row) if row else None

    def list_properties(self) -> list[Property]:
        conn = self._connect()
        try:
            rows = conn.execute("SELECT * FROM property ORDER BY name").fetchall()
        finally:
            conn.close()
        return [_row_to_property(r) for r in rows]

    # ---------- Source ----------

    def create_source(
        self,
        property_id: str,
        platform: Platform,
        name: str,
        ical_read_url: str | None = None,
        api_credentials: dict | None = None,
    ) -> Source:
        src = Source(
            id=str(uuid.uuid4()),
            property_id=property_id,
            platform=platform,
            name=name,
            ical_read_url=ical_read_url,
            ical_feed_token=uuid.uuid4().hex,
            api_credentials=api_credentials or {},
        )
        with self.cursor() as cur:
            cur.execute(
                """INSERT INTO source
                   (id, property_id, platform, name, ical_read_url, ical_feed_token,
                    api_credentials, enabled)
                   VALUES (?, ?, ?, ?, ?, ?, ?, 1)""",
                (
                    src.id,
                    src.property_id,
                    src.platform.value,
                    src.name,
                    src.ical_read_url,
                    src.ical_feed_token,
                    json.dumps(src.api_credentials),
                ),
            )
        return src

    def get_source(self, source_id: str) -> Source | None:
        conn = self._connect()
        try:
            row = conn.execute("SELECT * FROM source WHERE id = ?", (source_id,)).fetchone()
        finally:
            conn.close()
        return _row_to_source(row) if row else None

    def get_source_by_token(self, property_id: str, platform: Platform, token: str) -> Source | None:
        conn = self._connect()
        try:
            row = conn.execute(
                """SELECT * FROM source
                   WHERE property_id = ? AND platform = ? AND ical_feed_token = ?""",
                (property_id, platform.value, token),
            ).fetchone()
        finally:
            conn.close()
        return _row_to_source(row) if row else None

    def list_sources(self, property_id: str | None = None) -> list[Source]:
        conn = self._connect()
        try:
            if property_id:
                rows = conn.execute(
                    "SELECT * FROM source WHERE property_id = ? ORDER BY platform, name",
                    (property_id,),
                ).fetchall()
            else:
                rows = conn.execute("SELECT * FROM source ORDER BY platform, name").fetchall()
        finally:
            conn.close()
        return [_row_to_source(r) for r in rows]

    def mark_source_synced(self, source_id: str) -> None:
        with self.cursor() as cur:
            cur.execute(
                "UPDATE source SET last_synced_at = ? WHERE id = ?",
                (_utcnow(), source_id),
            )

    def mark_source_pushed(self, source_id: str) -> None:
        with self.cursor() as cur:
            cur.execute(
                "UPDATE source SET last_pushed_at = ? WHERE id = ?",
                (_utcnow(), source_id),
            )

    # ---------- Booking ----------

    def upsert_booking(
        self,
        property_id: str,
        source: Platform,
        source_uid: str,
        start: date,
        end: date,
        status: BookingStatus,
        summary: str | None = None,
        guest_name: str | None = None,
        raw: dict | None = None,
    ) -> tuple[Booking, bool]:
        """Upsert by (property_id, source, source_uid). Returns (booking, created)."""
        now = _utcnow()
        raw_json = json.dumps(raw or {})
        conn = self._connect()
        try:
            existing = conn.execute(
                """SELECT * FROM booking
                   WHERE property_id = ? AND source = ? AND source_uid = ?""",
                (property_id, source.value, source_uid),
            ).fetchone()
            if existing:
                conn.execute(
                    """UPDATE booking
                       SET start_date=?, end_date=?, status=?, summary=?, guest_name=?,
                           raw=?, updated_at=?
                       WHERE id=?""",
                    (
                        start.isoformat(),
                        end.isoformat(),
                        status.value,
                        summary,
                        guest_name,
                        raw_json,
                        now,
                        existing["id"],
                    ),
                )
                row = conn.execute(
                    "SELECT * FROM booking WHERE id = ?", (existing["id"],)
                ).fetchone()
                return _row_to_booking(row), False
            new_id = str(uuid.uuid4())
            conn.execute(
                """INSERT INTO booking
                   (id, property_id, source, source_uid, start_date, end_date,
                    status, summary, guest_name, raw, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    new_id,
                    property_id,
                    source.value,
                    source_uid,
                    start.isoformat(),
                    end.isoformat(),
                    status.value,
                    summary,
                    guest_name,
                    raw_json,
                    now,
                    now,
                ),
            )
            row = conn.execute("SELECT * FROM booking WHERE id = ?", (new_id,)).fetchone()
            return _row_to_booking(row), True
        finally:
            conn.close()

    def cancel_missing(
        self, property_id: str, source: Platform, seen_uids: set[str]
    ) -> int:
        """Mark bookings from this source/property as CANCELLED if they weren't in the latest fetch."""
        conn = self._connect()
        try:
            rows = conn.execute(
                """SELECT id, source_uid FROM booking
                   WHERE property_id = ? AND source = ? AND status != ?""",
                (property_id, source.value, BookingStatus.CANCELLED.value),
            ).fetchall()
            stale = [r["id"] for r in rows if r["source_uid"] not in seen_uids]
            if not stale:
                return 0
            now = _utcnow()
            conn.executemany(
                "UPDATE booking SET status=?, updated_at=? WHERE id=?",
                [(BookingStatus.CANCELLED.value, now, bid) for bid in stale],
            )
            return len(stale)
        finally:
            conn.close()

    def list_bookings(
        self,
        property_id: str,
        exclude_source: Platform | None = None,
        include_cancelled: bool = False,
    ) -> list[Booking]:
        conn = self._connect()
        try:
            q = "SELECT * FROM booking WHERE property_id = ?"
            args: list = [property_id]
            if exclude_source is not None:
                q += " AND source != ?"
                args.append(exclude_source.value)
            if not include_cancelled:
                q += " AND status != ?"
                args.append(BookingStatus.CANCELLED.value)
            q += " ORDER BY start_date"
            rows = conn.execute(q, args).fetchall()
        finally:
            conn.close()
        return [_row_to_booking(r) for r in rows]

    def get_booking(self, booking_id: str) -> Booking | None:
        conn = self._connect()
        try:
            row = conn.execute("SELECT * FROM booking WHERE id = ?", (booking_id,)).fetchone()
        finally:
            conn.close()
        return _row_to_booking(row) if row else None

    def delete_booking(self, booking_id: str) -> bool:
        with self.cursor() as cur:
            cur.execute("DELETE FROM booking WHERE id = ?", (booking_id,))
            return cur.rowcount > 0


# ----- row converters -----

def _row_to_property(row: sqlite3.Row) -> Property:
    return Property(
        id=row["id"],
        name=row["name"],
        created_at=datetime.fromisoformat(row["created_at"]),
    )


def _row_to_source(row: sqlite3.Row) -> Source:
    return Source(
        id=row["id"],
        property_id=row["property_id"],
        platform=Platform(row["platform"]),
        name=row["name"],
        ical_read_url=row["ical_read_url"],
        ical_feed_token=row["ical_feed_token"],
        api_credentials=json.loads(row["api_credentials"] or "{}"),
        last_synced_at=_parse_dt(row["last_synced_at"]),
        last_pushed_at=_parse_dt(row["last_pushed_at"]),
        enabled=bool(row["enabled"]),
    )


def _row_to_booking(row: sqlite3.Row) -> Booking:
    return Booking(
        id=row["id"],
        property_id=row["property_id"],
        source=Platform(row["source"]),
        source_uid=row["source_uid"],
        start=date.fromisoformat(row["start_date"]),
        end=date.fromisoformat(row["end_date"]),
        status=BookingStatus(row["status"]),
        summary=row["summary"],
        guest_name=row["guest_name"],
        raw=json.loads(row["raw"] or "{}"),
        created_at=datetime.fromisoformat(row["created_at"]),
        updated_at=datetime.fromisoformat(row["updated_at"]),
    )
