from __future__ import annotations

from ..models import Platform
from .base import ICalPullSource


class BookingDotComSource(ICalPullSource):
    """Booking.com partner iCal sync.

    Read:  fetch the iCal export URL from the Booking.com Extranet
           (Property -> Calendar & Pricing -> Sync calendars -> Export calendar).
    Write: Booking.com pulls our hosted iCal feed on its own schedule. Configure
           the feed URL in the Extranet's 'Import calendar' section.
    """

    platform = Platform.BOOKING
