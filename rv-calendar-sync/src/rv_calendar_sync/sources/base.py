from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Iterable

import httpx

from ..ical_utils import parse_ical_feed
from ..models import Booking, Platform, Source


class CalendarSource(ABC):
    """Adapter for a single platform connection.

    `fetch` reads bookings FROM the remote platform into our DB-shaped dicts.
    `push` writes our merged view TO the remote platform (or returns False if
    the platform is iCal-pull-only, meaning the remote fetches our feed on
    its own schedule).
    """

    platform: Platform

    def __init__(self, source: Source):
        self.source = source

    @abstractmethod
    async def fetch(self, client: httpx.AsyncClient) -> list[dict]:
        """Return a list of normalized event dicts (see ical_utils.parse_ical_feed)."""

    async def push(
        self, client: httpx.AsyncClient, bookings: Iterable[Booking]
    ) -> tuple[bool, int]:
        """Push bookings to the remote.

        Returns (active, count). `active=False` means the platform is iCal-pull-only;
        the caller should rely on the hosted /ical feed instead. Default impl is pull-only.
        """
        return False, 0


class ICalPullSource(CalendarSource):
    """Default implementation for platforms that expose iCal export but no write API
    (the remote pulls our /ical feed on its own schedule)."""

    async def fetch(self, client: httpx.AsyncClient) -> list[dict]:
        if not self.source.ical_read_url:
            return []
        resp = await client.get(self.source.ical_read_url, timeout=30.0)
        resp.raise_for_status()
        return parse_ical_feed(resp.content, self.source.property_id, self.platform)
