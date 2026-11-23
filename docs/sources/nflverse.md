# nflverse

- **Module:** `sports_ingest/nflverse` (M5)
- **Last verified:** 2026-11-22: the release tags and assets below exist and download, and
  `stats_player/timestamp.json` was updated the same day.
- **Default raw-cache TTL:** 86400 seconds (`SPORTS_INGEST_TTL_NFLVERSE`)

Files, not an API: CSV (and other formats) attached to GitHub releases of
[`nflverse/nflverse-data`](https://github.com/nflverse/nflverse-data). Each data set is one
release tag.

## Endpoints used

Download: `https://github.com/nflverse/nflverse-data/releases/download/{tag}/{file}`

| Tag | Files we read | Issue |
|---|---|---|
| `stats_player` | `stats_player_week_{season}.csv`, `stats_player_reg_{season}.csv` | M5-02 |
| `players` | `players.csv` | M5-03 |
| `rosters` / `weekly_rosters` | per-season roster files | M5-03 |
| every tag | `timestamp.json`: `{"last_updated": "YYYY-MM-DD HH:MM:SS EST"}` | M5-01 |

List a tag's assets: `https://api.github.com/repos/nflverse/nflverse-data/releases/tags/{tag}`.

The ffverse ID map (M5-04) lives elsewhere; add its location here when that issue lands.

## Auth

None.

## Rate limits

Asset downloads redirect (`302`) to `release-assets.githubusercontent.com` and aren't limited in
practice. The GitHub REST API (listing assets) allows 60 unauthenticated requests an hour per IP,
so prefer the direct download URL and `timestamp.json` over listing.

## Known quirks

- **Check `timestamp.json` before downloading** a season file; it's tiny and says whether the
  cached copy is stale (M5-01).
- **`player_stats` is the old tag.** Its `timestamp.json` stopped at 2025-05-07; current player
  stats are under `stats_player`. Don't read `player_stats`.
- **Season files appear as the season goes**: `stats_player_week_2026.csv` exists during the 2026
  season and grows weekly.
- Downloads follow a redirect; the HTTP client must follow it.

## Terms of use

The repository is licensed CC-BY-4.0: reuse is fine with attribution to nflverse. Credit nflverse
in anything we publish that shows this data.
