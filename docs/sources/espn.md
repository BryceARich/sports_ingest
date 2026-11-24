# ESPN Fantasy

- **Module:** `sports_ingest/espn` (M4), read-only
- **Last verified:** 2026-11-23 (M4-01): `/seasons/2027` returned 200 (cassette
  `espn/fhl_season_2027`); unknown league IDs returned 404 with the JSON below, and an ID too big for
  ESPN returned 400. A **private** league's 401 was not seen live (none on hand); the client relies
  only on the status.
- **Client:** `SportsIngest::ESPN::Client` (ADR 0032); filters with `SportsIngest::ESPN::Filter`
- **Default raw-cache TTL:** 900 seconds (`SPORTS_INGEST_TTL_ESPN`)

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
