# ESPN Fantasy

- **Module:** `sports_ingest/espn` (M4), read-only
- **Last verified:** 2026-11-23 (M4-01, M4-02 stat IDs): `/seasons/2027` returned 200 (cassette
  `espn/fhl_season_2027`); unknown league IDs returned 404 with the JSON below, and an ID too big for
  ESPN returned 400. A **private** league's 401 was not seen live (none on hand); the client relies
  only on the status.
- **Client:** `SportsIngest::ESPN::Client` (ADR 0032); filters with `SportsIngest::ESPN::Filter`
- **League settings:** `SportsIngest::ESPN::LeagueSettings`, `StatIds`, `LineupSlots` (ADR 0033)
- **Default raw-cache TTL:** 900 seconds (`SPORTS_INGEST_TTL_ESPN`)

## Usage

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

League settings come back as a plain Hash: scoring as stat ID => points, per-slot points (ESPN
keeps D/ST points-allowed tiers there), roster slots and teams. `StatIds` and `LineupSlots` name
the IDs.

```ruby
settings = SportsIngest::ESPN::LeagueSettings.new(game: :football).fetch(12_345, season: 2026)
settings[:scoring].to_h { |id, points| [SportsIngest::ESPN::StatIds.abbrev(:football, id), points] }
# => {"PY" => 0.04, "PTD" => 4.0, "INT" => -2.0, "REC" => 1.0, ...}
settings[:scoring_by_slot]["D/ST"] # => {89 => 5.0, 90 => 4.0, ...}
settings[:roster_slots]            # => {"QB" => 1, "RB" => 2, ..., "FLEX" => 1}
settings[:teams].first             # => {id: 1, abbrev: "PUCK", name: "...", owners: ["..."]}
```

## Endpoints used

Base: `https://lm-api-reads.fantasy.espn.com/apis/v3/games/{game}`, where `game` is `fhl`
(hockey) or `ffl` (football). ESPN's season ID is the year the season **ends** for hockey
(2026-27 is `2027`) and the year it starts for football (`2026`).

| Path | Returns | Issue |
|---|---|---|
| `/seasons/{year}` | game metadata for the season | M4-01 |
| `/seasons/{year}/segments/0/leagues/{leagueId}?view=...` | a league, shaped by `view` | M4-02, M4-05, M4-06 |
| `/seasons/{year}/players?view=kona_player_info` | the player pool, filtered by `X-Fantasy-Filter` | M4-03, M4-04 |
| `/leagueHistory/{leagueId}?seasonId={year}` | past seasons of a league | M4-05 |
| `/seasons/{year}/segments/0/leaguedefaults/{n}?view=mSettings` | ESPN's default settings for a league type, public (`ffl` 1 = standard, 3 = PPR; `fhl` 1 = points, 3 = H2H categories) | M4-02 (checking IDs only) |

`view` values come up per issue (`mSettings`, `mTeam`, `mRoster`, `mDraftDetail`, ...); add each one
here with what it returns when an adapter starts using it.

- **`mDraftDetail`** (M4-05) adds `draftDetail` to the league and to each `leagueHistory` entry:
  `drafted`, `inProgress` and `picks`. Each pick has `overallPickNumber`, `roundId`,
  `roundPickNumber`, `teamId` (the fantasy team in that league), `playerId` (ESPN's player ID) and
  `keeper`. `SportsIngest::ESPN::Drafts` reads it; the shape is from ESPN's undocumented responses
  and has not been checked against a live league yet (see the M4-05 note in the PR).

Players carry a `proTeamId` (0 means free agent). It's ESPN's team ID, and maps to a team through
`SportsIngest::Teams.find_by_source_id(:espn, id)`; checked against the player pool on 2026-11-22.
ESPN's abbreviations differ from the NHL's for `LA`, `NJ`, `SJ`, `TB` and `UTAH`.

Pass views as `views: [...]`; the client sends each as its own `view=` parameter.

### League settings (`mSettings` + `mTeam`, M4-02)

- `settings.scoringSettings.scoringItems[]`: `statId`, `points`, `isReverseItem` (lower is
  better, category leagues) and `pointsOverrides` (lineup slot ID => points). ESPN's football
  defaults score D/ST points- and yards-allowed tiers **only** through `pointsOverrides["16"]`,
  with `points` 0. `scoringType` is `H2H_POINTS`, `H2H_CATEGORY`, ...
- `settings.rosterSettings.lineupSlotCounts`: slot ID (String) => count, zero for unused slots.
- `teams[]`: `id`, `abbrev`, `name` (older seasons: `location` + `nickname`), `owners` (member
  IDs). `members[]`: `id`, `displayName`. Member IDs are SWIDs, so `LeagueSettings` drops them.

### Stat and slot IDs

ESPN doesn't publish them. `ESPN::StatIds` and `ESPN::LineupSlots` list only IDs checked on
2026-11-23 this way:

- **Scoring IDs:** the public `leaguedefaults` settings above, against ESPN's well-known default
  points (PY 0.04, PTD 4, INT -2, REC 1, FG0 3, FG40 4, FG50 5, FG60 6, the D/ST tiers).
- **Football stat IDs:** 345 players' 2025 season totals (`kona_player_info` on
  `leaguedefaults/3` with `filterStatsForExternalIds: [2025]`, `filterStatsForSourceIds: [0]`,
  `filterStatsForSplitTypeIds: [0]`) matched to nflverse `stats_player_reg_2025.csv`. Field-goal
  attempt and miss IDs (75, 76, 78, 79, 81, 82, 199, 200, 202, 203) agree for most kickers;
  blocked kicks seem to be counted differently.
- **Hockey stat IDs:** McDavid, Celebrini, Makar, Kucherov and Vasilevskiy's 2025-26 totals
  matched to `api-web.nhle.com` and the stats REST API. 8 and 26 are seconds; 27 is seconds per
  game.
- **Inferred, not matched:** football 121, 122 and 131 (points-allowed 18-21, 22-27 and yards
  allowed 300-349) fill the gaps between matched tiers.
- **Slots:** player `eligibleSlots` by position, and the default `lineupSlotCounts`. Hockey 3 is
  `F` (ESPN's default is 9 F, 5 D, 2 G, 1 UTIL). Football 1, 19, 22, 24 and 25 (25 shows up on
  2026 rookies) are unknown.
- **Seen but unnamed:** hockey 5, 12, 25, 34; football 5-18, 27-38, 40, 45-52, 54-61, 65-71,
  155-186, 211-234 and others. Name them only after checking.

The `X-Fantasy-Filter` header is JSON, e.g. `{"players":{"limit":50}}`. Build it with
`ESPN::Filter.players(limit:, offset:, ids:, status:, slot_ids:, sort_percent_owned:)` (keys
`limit`, `offset`, `filterIds`, `filterStatus` with `FREEAGENT` / `WAIVERS` / `ONTEAM`,
`filterSlotIds`, `sortPercOwned`), or `ESPN::Filter.new(hash)` for other keys.

```bash
curl -s -H 'X-Fantasy-Filter: {"players":{"limit":1}}' \
  'https://lm-api-reads.fantasy.espn.com/apis/v3/games/fhl/seasons/2027/players?view=kona_player_info'
```

## Auth

Public leagues need none. Private leagues need the `espn_s2` and `SWID` cookies from a logged-in
browser, set through `SPORTS_INGEST_ESPN_S2` / `SPORTS_INGEST_ESPN_SWID` or `SportsIngest.configure`
(ADR 0010). They are secrets: redacted in `inspect` and logs, scrubbed from cassettes. The client
sends `Cookie: espn_s2=...; SWID=...` on every request when both are set, and none when either is
missing. `SWID` keeps its braces, `{...}`, as the browser shows it.

## Rate limits

None published. Keep calls few and cached; the player pool is large, so filter it.

## Known quirks

- **Cookies expire.** Auth failures on a league that worked before mean fresh `espn_s2` / `SWID`
  values are needed (`SportsIngest::AuthError`).
- **League IDs too big for ESPN's integer return `400`** (`Invalid parameter for 'leagueId'`),
  which surfaces as `SportsIngest::HTTPError`.
- **Unknown league IDs return `404`** with `{"messages":["Not Found"], ...}`; map to
  `SportsIngest::NotFound`.
- **Read-only.** Never call write endpoints; `ESPN::Write` is reserved behind an explicit opt-in
  (M4-08).
- The `lm-api-reads` host replaced the older `fantasy.espn.com/apis/v3` host for reads; if it
  moves again, record the date here.

## Terms of use

The API is undocumented and unsupported. ESPN's terms of use
(<https://disneytermsofuse.com/>) apply. Our reading: reading your own leagues for personal use
is fine; don't scrape other people's private leagues, don't share cookies, and don't hammer it.
