# nflverse

- **Module:** `sports_ingest/nflverse` (M5)
- **Last verified:** 2026-11-22: the release tags and assets below exist and download, and
  `stats_player/timestamp.json` was updated the same day.
- **Default raw-cache TTL:** 86400 seconds (`SPORTS_INGEST_TTL_NFLVERSE`)

Files, not an API: CSV (and other formats) attached to GitHub releases of
[`nflverse/nflverse-data`](https://github.com/nflverse/nflverse-data). Each data set is one
release tag.

## Usage

### nflverse release files

```ruby
require "sports_ingest/nflverse"

downloader = SportsIngest::Nflverse::ReleaseDownloader.new
release = downloader.fetch("stats_player", "stats_player_week_2025.csv")
release.path         # a local file under <cache_dir>/releases/nflverse/stats_player/
release.last_updated # => "2026-11-22 05:12:43 EST", from the tag's timestamp.json
```

A file is downloaded once and reused until the tag's `timestamp.json` changes, which is checked at
most once per nflverse TTL (`SPORTS_INGEST_TTL_NFLVERSE`, a day by default). Offline, the last copy
comes back with `stale: true`. nflverse data is CC-BY-4.0: credit nflverse wherever you show it.

### nflverse player stats

```ruby
stats = SportsIngest::Nflverse::PlayerStats.new
stats.weekly(last: 3)  # => [PlayerWeekStats, ...] one per player per game, incl. playoffs
stats.season(seasons: [2025]) # => [PlayerSeasonStats, ...] regular-season totals
stats.season(last: 3).first.stats["passing_yards"]
```

`seasons:` or `last:` work as everywhere else, `last: 3` by default. Stats are numeric columns keyed
by their nflverse names (`"passing_yards"`, `"fantasy_points_ppr"`); blank and `NA` cells are left out
([ADR 0041](docs/adr/0041-nflverse-player-stats-models.md)). A season whose file doesn't exist yet
raises `SportsIngest::NotFound`.

### players and rosters

```ruby
require "sports_ingest/nflverse"

SportsIngest::Nflverse::Players.new.fetch.first.id         # => "00-0033873"
SportsIngest::Nflverse::Rosters.new.fetch(2025).first.team  # => "PIT"
```

Players come from `players.csv` and rosters from `roster_<season>.csv`, both through the release
downloader (so a file is reused until upstream changes). Models are keyed by `gsis_id`, the
canonical football ID (ADR 0042). Rows without a `gsis_id` are skipped; a malformed `gsis_id`, a
missing column or a bad birth date raises `SourceChangedError`. Results are also written to the
processed cache under `nflverse/players` and `nflverse/rosters/<season>`.

## Endpoints used

Download: `https://github.com/nflverse/nflverse-data/releases/download/{tag}/{file}`

| Tag | Files we read | Issue |
|---|---|---|
| `stats_player` | `stats_player_week_{season}.csv`, `stats_player_reg_{season}.csv` | M5-02 |
| `players` | `players.csv` | M5-03 |
| `rosters` | `roster_{season}.csv` | M5-03 |
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
  cached copy is stale. `Nflverse::ReleaseDownloader` (M5-01) does this: the timestamp goes through
  the raw cache (so it's checked once per TTL), the asset is saved to
  `<cache_dir>/releases/nflverse/<tag>/<file>` with a `<file>.meta.json` recording the
  `last_updated` it matches, and it's downloaded again only when that value changes
  ([ADR 0040](../adr/0040-nflverse-release-files-on-disk.md)).
- **`last_updated` is compared as a string**, never parsed: it's US Eastern time with an `EST`
  suffix, and we only need to know whether it changed. Checked 2026-11-23 for `stats_player` and
  `players`.
- **Weekly and season files differ in shape.** `stats_player_week_<season>.csv` has a `week` and
  `season_type` (`REG` or `POST`) column and `opponent_team`; `stats_player_reg_<season>.csv` is
  regular season only, with no `week`. Both key players by GSIS `player_id`. Stat cells can be `NA`
  (a stat that doesn't apply to the position), which `PlayerStats` reads as missing
  ([ADR 0041](../adr/0041-nflverse-player-stats-models.md)). Column names were not checked
  against a live download when M5-02 was written; the specs use
  invented fixtures in `spec/fixtures/nflverse/` with this layout. Check the header of a real file
  before relying on a column name.
- **`player_stats` is the old tag.** Its `timestamp.json` stopped at 2025-05-07; current player
  stats are under `stats_player`. Don't read `player_stats`.
- **Season files appear as the season goes**: `stats_player_week_2026.csv` exists during the 2026
  season and grows weekly.
- **`gsis_id` is blank for some rows** in both `players.csv` and the roster files. Those rows are
  skipped, since they have no canonical ID (ADR 0042). Checked 2026-11-24 against `players` and
  `rosters` (`roster_2025.csv`): the column names and the blank cells are as described.
- Downloads follow a redirect; the HTTP client must follow it.

## Terms of use

The repository is licensed CC-BY-4.0: reuse is fine with attribution to nflverse. Credit nflverse
in anything we publish that shows this data.
