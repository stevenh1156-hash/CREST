from __future__ import annotations

from ..models import Platform
from .base import ICalPullSource


class RVshareSource(ICalPullSource):
    """RVshare iCal sync.

    Read:  RVshare provides an iCal export URL per listing
           (Owner dashboard -> Listings -> Calendar -> Sync external calendars).
    Write: RVshare pulls our hosted iCal feed; paste the feed URL into
           'Import calendar' on the same screen.
    """

    platform = Platform.RVSHARE
