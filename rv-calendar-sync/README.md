# rv-calendar-sync

Two-way calendar sync for RV rentals across **Booking.com**, **RVshare**, **Outdoorsy**, **Wix Hotels**, and **manual** owner entries.

It pulls bookings from every configured platform, stores them in a local SQLite DB, and exposes a per-platform iCal feed that the other platforms subscribe to — so a booking on Outdoorsy automatically blocks the same dates on RVshare, Booking.com, and Wix. Wix Hotels additionally gets bookings pushed via its REST API when credentials are configured.

## How sync actually works

Each platform uses the same loop:

1. **Pull**: fetch the platform's iCal export URL (or REST API for Wix) → upsert into our DB, keyed by `(property_id, source, source_uid)`.
2. **Cancel-prune**: if a booking we previously saw from this source is no longer in the feed, mark it `CANCELLED` (instead of deleting — its `STATUS:CANCELLED` event in the outbound feed tells consumers to release the block).
3. **Push**: every *other* platform sees the merged calendar. Bookings sourced from platform X are excluded from X's outbound feed so we don't create feedback loops.

| Platform     | Read                         | Write                              |
|--------------|------------------------------|------------------------------------|
| Booking.com  | iCal export URL              | Hosted iCal feed (platform pulls)  |
| RVshare      | iCal export URL              | Hosted iCal feed (platform pulls)  |
| Outdoorsy    | iCal export URL              | Hosted iCal feed (platform pulls)  |
| Wix Hotels   | REST API → iCal fallback     | REST API → iCal fallback           |
| Manual       | n/a (origin only)            | Appears in every outbound feed     |

## Install

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e .[dev]
cp .env.example .env  # then edit
```

Set `RV_SYNC_PUBLIC_BASE_URL` to a URL the rental platforms can reach. For local development use [ngrok](https://ngrok.com) or [cloudflared](https://github.com/cloudflare/cloudflared) to expose `http://localhost:8000`.

## Quickstart

```bash
# 1. Create a property (one per RV)
rv-sync property create "Sprinter 4x4"
# → prints the property id, e.g. 7a1c...

# 2. Register each platform connection
rv-sync source create <PROPERTY_ID> rvshare "RVshare listing" \
  --ical-url "https://rvshare.com/calendar/abc123.ics"
# → prints the FEED URL to paste into RVshare's "Import calendar" field

rv-sync source create <PROPERTY_ID> outdoorsy "Outdoorsy listing" \
  --ical-url "https://outdoorsy.com/rv/xyz/availability.ics"

rv-sync source create <PROPERTY_ID> booking "Booking.com" \
  --ical-url "https://admin.booking.com/hotel/hoteladmin/.../ical.ics"

rv-sync source create <PROPERTY_ID> wix_hotels "Wix Hotels" \
  --creds-json '{"room_type_id": "rt_abc123"}'

# 3. (Optional) Add a manual block - e.g. owner uses the RV
rv-sync booking add <PROPERTY_ID> 2026-06-01 2026-06-05 \
  --summary "Owner trip" --status blocked

# 4. Run a sync
rv-sync sync

# 5. Or run the server (scheduled sync + iCal feeds + admin API)
rv-sync serve
```

## HTTP endpoints

Public (token-protected, no admin auth):

- `GET /ical/{property_id}/{platform}/{token}.ics` — outbound iCal feed. Paste the URL into the matching platform's "Import calendar" field.

Admin (require `Authorization: Bearer <RV_SYNC_ADMIN_TOKEN>`):

- `POST /api/properties?name=...`
- `GET  /api/properties`
- `POST /api/properties/{pid}/sources?platform=...&name=...&ical_read_url=...`
- `GET  /api/properties/{pid}/sources`
- `GET  /api/properties/{pid}/sources/{sid}/feed-url`
- `GET  /api/properties/{pid}/bookings`
- `POST /api/properties/{pid}/bookings` (manual entries)
- `DELETE /api/bookings/{id}` (manual: hard delete; external: cancel)
- `POST /api/sync` (trigger full sync)
- `POST /api/sources/{sid}/sync` (trigger one source)

Interactive docs at `http://localhost:8000/docs`.

## Platform-specific setup

### Booking.com (partner / extranet)
- Extranet → *Property* → *Calendar & Pricing* → *Sync calendars*.
- "Export calendar": copy the iCal URL → pass to `--ical-url`.
- "Import calendar": paste **our** feed URL (printed by `source create`).

### RVshare
- Owner dashboard → *Listings* → *Calendar* → *Sync external calendars*.
- "Export" URL → `--ical-url`. "Import external calendar" → our feed URL.

### Outdoorsy
- Dashboard → RV → *Calendar* → *Sync*.
- "Export" URL → `--ical-url`. "Import external calendar" → our feed URL.

### Wix Hotels
- For **REST API mode** (recommended): set `WIX_API_KEY`, `WIX_SITE_ID`, `WIX_ACCOUNT_ID`, and pass the room type id as `--creds-json '{"room_type_id": "..."}'`. Generates blocking reservations via `POST /hotels-reservations/v1/reservations`.
- For **iCal fallback**: leave `WIX_API_KEY` empty and pass an iCal export URL via `--ical-url`; then paste our feed URL into Wix's iCal import.

## Architecture

```
src/rv_calendar_sync/
├── config.py          # Settings (env-driven)
├── db.py              # SQLite layer, schema, row converters
├── models.py          # Pydantic models + enums
├── ical_utils.py      # iCal parse / serialize
├── sync.py            # Pull → upsert → cancel-prune → push
├── server.py          # FastAPI app + APScheduler
├── cli.py             # Typer CLI (`rv-sync ...`)
└── sources/
    ├── base.py        # CalendarSource ABC + ICalPullSource default
    ├── booking.py     # iCal pull/host
    ├── rvshare.py     # iCal pull/host
    ├── outdoorsy.py   # iCal pull/host
    ├── wix_hotels.py  # REST API push + iCal fallback
    └── manual.py      # origin-only
```

Adding a new platform = subclassing `CalendarSource`, implementing `fetch()` (and optionally `push()`), and registering it in `sources/__init__.py:REGISTRY`.

## Tests

```bash
pytest
```

Tests don't hit the network — HTTP calls are mocked with `respx`.

## Android app

A Jetpack Compose front end lives in [`android/`](./android). It talks to this server's REST API to manage properties, sources, and bookings, and lets you trigger sync from your phone. See `android/README.md`.

## License

MIT.
