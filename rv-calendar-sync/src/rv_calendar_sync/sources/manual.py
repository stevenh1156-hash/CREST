from __future__ import annotations

import httpx

from ..models import Platform
from .base import CalendarSource


class ManualSource(CalendarSource):
    """Manual bookings created via the local API/CLI.

    There is nothing to fetch - manual entries originate in our own DB. push() is
    a no-op for the same reason; downstream platforms see manual blocks via the
    hosted /ical feeds.
    """

    platform = Platform.MANUAL

    async def fetch(self, client: httpx.AsyncClient) -> list[dict]:
        return []
