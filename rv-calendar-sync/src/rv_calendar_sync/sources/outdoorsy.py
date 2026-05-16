from __future__ import annotations

from ..models import Platform
from .base import ICalPullSource


class OutdoorsySource(ICalPullSource):
    """Outdoorsy iCal sync.

    Read:  Outdoorsy provides an iCal export URL per RV
           (Dashboard -> RV -> Calendar -> Sync -> Export).
    Write: Outdoorsy pulls our hosted iCal feed; paste it into the 'Import
           external calendar' field.
    """

    platform = Platform.OUTDOORSY
