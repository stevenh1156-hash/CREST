from __future__ import annotations

from ..models import Platform
from .base import CalendarSource
from .booking import BookingDotComSource
from .manual import ManualSource
from .outdoorsy import OutdoorsySource
from .rvshare import RVshareSource
from .wix_hotels import WixHotelsSource

REGISTRY: dict[Platform, type[CalendarSource]] = {
    Platform.BOOKING: BookingDotComSource,
    Platform.RVSHARE: RVshareSource,
    Platform.OUTDOORSY: OutdoorsySource,
    Platform.WIX_HOTELS: WixHotelsSource,
    Platform.MANUAL: ManualSource,
}


def get_source_class(platform: Platform) -> type[CalendarSource]:
    return REGISTRY[platform]


__all__ = [
    "CalendarSource",
    "REGISTRY",
    "get_source_class",
    "BookingDotComSource",
    "RVshareSource",
    "OutdoorsySource",
    "WixHotelsSource",
    "ManualSource",
]
