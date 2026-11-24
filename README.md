# sports_ingest

A Ruby gem for **reading** sports data and turning it into clean, cached Ruby models that other
projects (fantasy tools, dashboards, a future API) consume.

> **Status:** early development (M1 Foundation). The gem skeleton exists; no source adapters yet.
> See [`docs/RESUME.md`](docs/RESUME.md) for current status and the next issues.

## Goals

- **One place to read sports data.** Consumers `require` the gem instead of re-implementing
  fetching, parsing, caching and player matching in every project.
- **Clean models.** Every source becomes immutable Ruby value objects with a schema version.
- **One player identity.** Each player gets a canonical ID, and every source maps to it through
  a crosswalk.
- **Cached and offline-friendly.** A raw HTTP cache (served stale when the network fails) and a
  processed cache of normalized models, both JSON on disk. No database.
- **Load only what you use.** `require "sports_ingest/nhl"` loads core plus NHL, nothing else.
- **Runs on a Raspberry Pi.** Core has no native-extension dependencies.
- **Respect licensed data.** Evolving-Hockey and PuckPedia exports are read from files you export
  yourself and never enter git.

## Sources

| Source | Module | Notes |
|---|---|---|
| NHL (`api-web.nhle.com`, `api.nhle.com/stats/rest`) | `sports_ingest/nhl` | public, no auth |
| ESPN Fantasy | `sports_ingest/espn` | read-only; private leagues need `espn_s2` + `SWID` cookies |
| nflverse releases | `sports_ingest/nflverse` | GitHub release files |
| Evolving-Hockey + PuckPedia | `sports_ingest/advanced_hockey` | licensed, manually exported files only |

They arrive in milestones M2 to M6. So far: the Evolving-Hockey skater GAR import, the ESPN
Fantasy client and nflverse release downloads (below).

## Usage

```ruby
require "sports_ingest"

SportsIngest::VERSION # => "0.1.0"
```

Each source loads on its own, with core but no other source:

```ruby
require "sports_ingest/nhl" # SportsIngest::NHL, nothing from ESPN, nflverse or CSV
```

Teams resolve from any source's code, in core:

```ruby
team = SportsIngest::Teams.fetch("T.B")    # the advanced-stats code; "TBL", "TB" work too
team.tri_code                              # => "TBL"
team.division                              # => "Atlantic"
SportsIngest::Teams.find("UTAH", source: :espn).name # => "Utah Mammoth"
```

### NHL schedule

```ruby
require "sports_ingest/nhl"

games = SportsIngest::NHL.schedule(date: "2026-11-23")
game = games.first
"#{game.away_team.tri_code} @ #{game.home_team.tri_code}" # => "CBJ @ NJD"
game.start_time     # => 2026-11-24 00:00:00 UTC; game.date is the local date, 2026-11-23
game.state          # => :scheduled, then :pregame, :live, :final

SportsIngest::NHL.schedule(from: "2026-11-23", to: "2026-11-30", team: "TOR") # a range, one team
SportsIngest::NHL.schedule(team: "TOR", month: "2026-11")
SportsIngest::NHL.schedule(team: "TOR", season: 2026) # 2026-27, preseason and playoffs included
```

### NHL scores

One request for all of today's games, light enough to poll from a Pi:

```ruby
scores = SportsIngest::NHL.scores # today, by the NHL's date; or scores(date: "2026-11-22")
live = scores.find(&:live?)
"#{live.away_team.tri_code} #{live.away_team.score} @ #{live.home_team.tri_code} #{live.home_team.score}"
live.period         # => 1 (4 is overtime, 5 a shootout in the regular season)
live.clock          # => "08:16"; also seconds_remaining, clock_running, in_intermission
live.game           # => the NHL::Game, as the schedule returns it
```

Each is an `NHL::GameScore`. Scores stay fresh in the raw cache for 30 seconds
(`NHL::Scoreboard::TTL`), not the hour schedules get.

### NHL standings

```ruby
require "sports_ingest/nhl"

standings = SportsIngest::NHL::Standings.fetch(date: "2026-11-22") # no date: today
car = standings.find("CAR")
car.record                     # => "18-3-3"
car.points                     # => 39
car.home.wins                  # => 8
standings.division("Metropolitan").map(&:tri_code)
```

Each `Standing` carries `team_id` from `SportsIngest::Teams`, ranks, the clinch letter and
`home` / `road` / `last_10` records. Other NHL paths go through `SportsIngest::NHL::Client`
(`get_json`, `stats_json`).

### NHL rosters

```ruby
require "sports_ingest/nhl"

rosters = SportsIngest::NHL::Rosters.new
players = rosters.fetch("EDM")             # current season; any team code works
rosters.fetch("EDM", season: 2024)         # 2024-25 as it stood after the season, offseason trades included

mcdavid = players.find { it.last_name == "McDavid" }
mcdavid.id          # => "8478402", the NHL ID and canonical ID
mcdavid.position    # => "C" (C, L, R, D or G); also forward?, defense?, goalie?
mcdavid.birth_date  # => #<Date: 1997-01-13>
```

Each roster is also saved to the processed cache under `nhl/rosters/<TEAM>/<20242025 or current>`.

### NHL player details and game logs

```ruby
require "sports_ingest/nhl"

mcdavid = SportsIngest::NHL.player(8478402)
mcdavid.player.birth_date               # => #<Date: 1997-01-13>; the same Player a roster gives
mcdavid.player.shoots_catches           # => "L"
mcdavid.draft.overall_pick              # => 1
mcdavid.career_regular_season.points    # career NHL totals; also career_playoffs
mcdavid.nhl_seasons.map(&:season)       # one StatLine per NHL season and team; seasons has every league

log = SportsIngest::NHL.game_log(8478402, season: 2025)  # 2025-26 regular season, oldest game first
SportsIngest::NHL.game_log(8478402, season: 2025, game_type: :playoffs)
SportsIngest::NHL.game_log(8478402)                      # the NHL's current log (this season, or the playoffs)
log.first.toi_seconds                   # skater and goalie stats share GameLogEntry; the rest are nil
```

Details are saved to the processed cache under `nhl/players/<id>`, game logs under
`nhl/game_logs/<id>/<20252026>/<regular or playoffs>`.

### Evolving-Hockey skater GAR

Download EH's skater GAR table as CSV (`EH_gar_sk_stats_regular_<date>.csv`) into a folder
**outside the repo**. EH groups it by season or by team and season; both import the same way:

```ruby
require "sports_ingest/advanced_hockey"
include SportsIngest::AdvancedHockey

rows = SkaterGarImport.read("~/hockey/EH_gar_sk_stats_regular_2026-11-23.csv")
rows.first.season # => 2026 (the 26-27 season, named by its start year)
rows.first.teams  # => ["N.J", "WPG"] for a traded player, grouped by season
rows.first.war    # => 0.9

SkaterGar.combine(rows) # one row per player and season, whichever grouping you exported
```

Grouped by team, a traded player has a row per team, but EH drops short stints from that view, so
use the season grouping for exact totals. Columns are matched by name (`EVO_GAR` or `EVO GAR`), so
a spreadsheet tab saved as CSV works too; a missing column raises
`SportsIngest::SourceChangedError` listing the columns it found.

### ESPN Fantasy

Read-only. Public leagues need nothing; for a private league, set the `espn_s2` and `SWID` cookies
from a logged-in browser in `SPORTS_INGEST_ESPN_S2` / `SPORTS_INGEST_ESPN_SWID` (or
`SportsIngest.configure`). Without them, a private league raises `SportsIngest::AuthError`.

```ruby
require "sports_ingest/espn"

espn = SportsIngest::ESPN::Client.new(game: :hockey) # or :football
league = espn.league(12_345, season: 2027, views: %w[mSettings mTeam])
league.dig("settings", "name")

espn.get_json("seasons/2027/players", views: ["kona_player_info"],
  filter: SportsIngest::ESPN::Filter.players(limit: 50, status: :free_agent, sort_percent_owned: true))
```

Hockey seasons are named by the year they end (2026-27 is `2027`), football by the year it starts.

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

## Development

Ruby is pinned in `.ruby-version` and installed with [mise](https://mise.jdx.dev).
Full setup for Mac and Raspberry Pi is in [`docs/RESUME.md`](docs/RESUME.md).

```bash
mise install          # Ruby from .ruby-version
bundle install
bundle exec rspec     # tests, fully offline
bundle exec rubocop   # lint (Standard Ruby)
bundle exec yard doc  # API docs into doc/
bundle exec rake yard:coverage  # doc coverage; CI fails below 90%
bin/console           # IRB with the gem loaded
```

Rules for contributing (branches, commits, PRs, the Definition of Done) are in
[`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CLAUDE.md`](CLAUDE.md). The architecture is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), decisions in [`docs/adr/`](docs/adr/README.md), and
per-source endpoints, limits and terms in [`docs/sources/`](docs/sources/README.md).

## License

The code is available under the [MIT License](LICENSE.txt). The license covers this code only:
data you read with it stays under each source's own terms, and Evolving-Hockey and PuckPedia
exports are licensed to you personally and never belong in this repo.
