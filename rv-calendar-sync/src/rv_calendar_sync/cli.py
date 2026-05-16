from __future__ import annotations

import asyncio
import json
from datetime import date

import typer
import uvicorn

from .config import get_settings
from .db import Database
from .models import BookingStatus, Platform
from .sync import sync_all, sync_source

app = typer.Typer(help="RV calendar sync CLI", no_args_is_help=True)
prop_app = typer.Typer(help="Manage properties (one per RV)")
source_app = typer.Typer(help="Manage platform sources")
booking_app = typer.Typer(help="Manage bookings (manual entries)")
app.add_typer(prop_app, name="property")
app.add_typer(source_app, name="source")
app.add_typer(booking_app, name="booking")


def _db() -> Database:
    return Database(get_settings().db_path)


@app.command()
def serve(
    host: str | None = None,
    port: int | None = None,
    reload: bool = False,
) -> None:
    """Run the HTTP server (iCal feeds + admin API)."""
    s = get_settings()
    uvicorn.run(
        "rv_calendar_sync.server:app",
        host=host or s.host,
        port=port or s.port,
        reload=reload,
    )


@app.command()
def sync(property_id: str | None = None) -> None:
    """Trigger a sync across all enabled sources (or one property)."""
    results = asyncio.run(sync_all(_db(), property_id=property_id))
    typer.echo(json.dumps([r.model_dump(mode="json") for r in results], indent=2))


@source_app.command("sync")
def source_sync(source_id: str) -> None:
    result = asyncio.run(sync_source(_db(), source_id))
    typer.echo(json.dumps(result.model_dump(mode="json"), indent=2))


@prop_app.command("create")
def prop_create(name: str) -> None:
    p = _db().create_property(name=name)
    typer.echo(p.model_dump_json(indent=2))


@prop_app.command("list")
def prop_list() -> None:
    for p in _db().list_properties():
        typer.echo(f"{p.id}\t{p.name}")


@source_app.command("create")
def source_create(
    property_id: str,
    platform: Platform,
    name: str,
    ical_url: str | None = typer.Option(None, help="iCal export URL from the platform"),
    creds_json: str = typer.Option("{}", help="API credentials as JSON"),
) -> None:
    creds = json.loads(creds_json)
    src = _db().create_source(
        property_id=property_id,
        platform=platform,
        name=name,
        ical_read_url=ical_url,
        api_credentials=creds,
    )
    base = get_settings().public_base_url.rstrip("/")
    feed = f"{base}/ical/{property_id}/{platform.value}/{src.ical_feed_token}.ics"
    typer.echo(src.model_dump_json(indent=2))
    typer.echo(f"\nFeed URL to paste into {platform.value}'s 'Import calendar':\n  {feed}")


@source_app.command("list")
def source_list(property_id: str | None = None) -> None:
    for s in _db().list_sources(property_id=property_id):
        typer.echo(
            f"{s.id}\t{s.property_id}\t{s.platform.value}\t{s.name}\t"
            f"enabled={s.enabled}\tlast_sync={s.last_synced_at}"
        )


@source_app.command("feed-url")
def source_feed_url(source_id: str) -> None:
    s = _db().get_source(source_id)
    if s is None:
        raise typer.BadParameter("source not found")
    base = get_settings().public_base_url.rstrip("/")
    typer.echo(f"{base}/ical/{s.property_id}/{s.platform.value}/{s.ical_feed_token}.ics")


@booking_app.command("add")
def booking_add(
    property_id: str,
    start: str = typer.Argument(..., help="YYYY-MM-DD (inclusive)"),
    end: str = typer.Argument(..., help="YYYY-MM-DD (exclusive)"),
    status_: BookingStatus = typer.Option(BookingStatus.BLOCKED, "--status"),
    summary: str | None = None,
    guest_name: str | None = None,
) -> None:
    db = _db()
    s = date.fromisoformat(start)
    e = date.fromisoformat(end)
    if e <= s:
        raise typer.BadParameter("end must be after start")
    import uuid as _uuid

    b, _ = db.upsert_booking(
        property_id=property_id,
        source=Platform.MANUAL,
        source_uid=f"manual-{_uuid.uuid4().hex}",
        start=s,
        end=e,
        status=status_,
        summary=summary,
        guest_name=guest_name,
    )
    typer.echo(b.model_dump_json(indent=2))


@booking_app.command("list")
def booking_list(
    property_id: str,
    include_cancelled: bool = False,
) -> None:
    for b in _db().list_bookings(property_id, include_cancelled=include_cancelled):
        typer.echo(
            f"{b.id}\t{b.source.value}\t{b.start}->{b.end}\t{b.status.value}\t{b.summary or ''}"
        )


if __name__ == "__main__":
    app()
