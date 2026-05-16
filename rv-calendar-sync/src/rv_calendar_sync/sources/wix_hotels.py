from __future__ import annotations

import hashlib
from datetime import date
from typing import Iterable

import httpx

from ..config import get_settings
from ..ical_utils import parse_ical_feed
from ..models import Booking, BookingStatus, Platform
from .base import CalendarSource


class WixHotelsSource(CalendarSource):
    """Wix Hotels via the Wix REST API.

    Configure `api_credentials` on the Source with:
      - room_type_id: the Wix Hotels room type identifier for this RV
      - (optional) ical_read_url: iCal export URL from Wix Hotels (fallback for read)

    Auth is taken from environment (WIX_API_KEY / WIX_SITE_ID / WIX_ACCOUNT_ID).
    """

    platform = Platform.WIX_HOTELS

    BASE_URL = "https://www.wixapis.com"
    RESERVATIONS_PATH = "/hotels-reservations/v1/reservations"

    def _auth_headers(self) -> dict[str, str]:
        s = get_settings()
        headers = {
            "Authorization": s.wix_api_key,
            "Content-Type": "application/json",
        }
        if s.wix_site_id:
            headers["wix-site-id"] = s.wix_site_id
        if s.wix_account_id:
            headers["wix-account-id"] = s.wix_account_id
        return headers

    def _room_type_id(self) -> str | None:
        return self.source.api_credentials.get("room_type_id")

    async def fetch(self, client: httpx.AsyncClient) -> list[dict]:
        settings = get_settings()

        # Prefer the REST API if credentials are configured.
        if settings.wix_api_key and self._room_type_id():
            return await self._fetch_via_api(client)

        # Fallback: iCal export URL from Wix Hotels.
        if self.source.ical_read_url:
            resp = await client.get(self.source.ical_read_url, timeout=30.0)
            resp.raise_for_status()
            return parse_ical_feed(resp.content, self.source.property_id, self.platform)
        return []

    async def _fetch_via_api(self, client: httpx.AsyncClient) -> list[dict]:
        room_type_id = self._room_type_id()
        payload = {
            "query": {
                "filter": {"roomTypeId": room_type_id},
                "paging": {"limit": 100},
            }
        }
        resp = await client.post(
            f"{self.BASE_URL}{self.RESERVATIONS_PATH}/query",
            json=payload,
            headers=self._auth_headers(),
            timeout=30.0,
        )
        resp.raise_for_status()
        data = resp.json()
        events: list[dict] = []
        for r in data.get("reservations", []):
            check_in = r.get("checkIn") or r.get("startDate")
            check_out = r.get("checkOut") or r.get("endDate")
            if not check_in or not check_out:
                continue
            status_raw = (r.get("status") or "").upper()
            if status_raw in ("CANCELED", "CANCELLED"):
                status = BookingStatus.CANCELLED
            elif status_raw == "TENTATIVE":
                status = BookingStatus.TENTATIVE
            else:
                status = BookingStatus.CONFIRMED
            guest = r.get("guest") or {}
            guest_name = " ".join(
                filter(None, [guest.get("firstName"), guest.get("lastName")])
            ) or None
            events.append(
                {
                    "source_uid": str(r.get("id") or r.get("reservationId")),
                    "start": date.fromisoformat(check_in[:10]),
                    "end": date.fromisoformat(check_out[:10]),
                    "status": status,
                    "summary": f"Wix Hotels reservation {r.get('id', '')}".strip(),
                    "guest_name": guest_name,
                    "raw": r,
                }
            )
        return events

    async def push(
        self, client: httpx.AsyncClient, bookings: Iterable[Booking]
    ) -> tuple[bool, int]:
        settings = get_settings()
        room_type_id = self._room_type_id()
        if not (settings.wix_api_key and room_type_id):
            # No API credentials -> Wix should pull our hosted iCal feed.
            return False, 0

        # We push owner-blocks (other-platform bookings + manual blocks) as
        # "BLOCK"-type reservations so Wix's calendar marks them unavailable.
        # We dedupe by a deterministic external id so re-runs are idempotent.
        pushed = 0
        for b in bookings:
            ext_id = self._external_id(b)
            payload = {
                "reservation": {
                    "externalId": ext_id,
                    "roomTypeId": room_type_id,
                    "checkIn": b.start.isoformat(),
                    "checkOut": b.end.isoformat(),
                    "type": "BLOCK",
                    "note": (b.summary or f"Synced from {b.source.value}")[:200],
                }
            }
            resp = await client.post(
                f"{self.BASE_URL}{self.RESERVATIONS_PATH}",
                json=payload,
                headers=self._auth_headers(),
                timeout=30.0,
            )
            if resp.status_code in (200, 201, 409):
                # 409 = already exists (idempotent re-push); treat as success.
                pushed += 1
            else:
                resp.raise_for_status()
        return True, pushed

    @staticmethod
    def _external_id(b: Booking) -> str:
        return "rvsync-" + hashlib.sha1(
            f"{b.id}|{b.source.value}|{b.source_uid}".encode("utf-8")
        ).hexdigest()[:24]
