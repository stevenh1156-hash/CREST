from __future__ import annotations

from datetime import date, datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class Platform(str, Enum):
    BOOKING = "booking"
    RVSHARE = "rvshare"
    OUTDOORSY = "outdoorsy"
    WIX_HOTELS = "wix_hotels"
    MANUAL = "manual"


class BookingStatus(str, Enum):
    CONFIRMED = "confirmed"
    TENTATIVE = "tentative"
    CANCELLED = "cancelled"
    BLOCKED = "blocked"  # owner-initiated unavailability


class Property(BaseModel):
    id: str
    name: str
    created_at: datetime


class Source(BaseModel):
    """A configured platform connection for a specific property."""

    id: str
    property_id: str
    platform: Platform
    name: str
    ical_read_url: str | None = None
    ical_feed_token: str  # token in our outbound feed URL
    api_credentials: dict[str, Any] = Field(default_factory=dict)
    last_synced_at: datetime | None = None
    last_pushed_at: datetime | None = None
    enabled: bool = True


class Booking(BaseModel):
    id: str  # our internal UUID
    property_id: str
    source: Platform
    source_uid: str  # the platform's UID for the event (stable across syncs)
    start: date
    end: date  # exclusive (iCal convention for DATE values)
    status: BookingStatus = BookingStatus.CONFIRMED
    summary: str | None = None
    guest_name: str | None = None
    raw: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class BookingCreate(BaseModel):
    property_id: str
    start: date
    end: date
    status: BookingStatus = BookingStatus.BLOCKED
    summary: str | None = None
    guest_name: str | None = None


class SyncResult(BaseModel):
    source_id: str
    platform: Platform
    fetched: int = 0
    created: int = 0
    updated: int = 0
    cancelled: int = 0
    pushed: int = 0
    errors: list[str] = Field(default_factory=list)
