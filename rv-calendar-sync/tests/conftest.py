from __future__ import annotations

import pytest

from rv_calendar_sync.db import Database


@pytest.fixture
def db(tmp_path) -> Database:
    return Database(tmp_path / "test.sqlite")
