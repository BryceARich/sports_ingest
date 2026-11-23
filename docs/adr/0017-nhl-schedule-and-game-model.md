# 0017. Read the NHL schedule by week and keep games as a small `NHL::Game`

- **Status:** Accepted
- **Date:** 2026-11-23
- **Issue:** #17

## Context

M2-02 needs games by date, date range and team. The web API offers several ways to get them:
`/schedule/{date}` (the week starting on that date, with `nextStartDate`), `/score/{date}` (one
day, with live detail, M2-03), and `/club-schedule-season/{TEAM}/{season}` (one team's whole
season). Each game payload carries far more than a schedule needs: TV broadcasts, betting odds,
ticket links, logos, highlight links. The first NHL model also sets the pattern for M2-03 to
M2-05, so its field types matter.

## Decision

- `NHL::Schedule` reads `/schedule/{date}` for dates and ranges, following `nextStartDate` (one
  request per week), and `/club-schedule-season/{TEAM}/{season}` for `team:` plus `season:`.
  `team:` with a date or range filters those results. `NHL.schedule(...)` picks the form from its
  keywords. Seasons are start years (ADR 0006), so `season: 2026` reads `20262027`.
- `NHL::Game` (schema 1) keeps only what a schedule answers: ID, season, game type, game date
  (local to the venue), UTC start, state, schedule state, how a finished game ended, venue,
  neutral site, and both sides as `NHL::GameTeam` (team ID, tri-code, score). IDs are Strings, as
  in `Team` and `PlayerRef`. NHL codes become symbols (`gameType` 2 → `:regular`, `gameState`
  `OFF` → `:final`, `gameOutcome.lastPeriodType` `OT` → `:overtime`).
- An unknown code or a missing field raises `SourceChangedError` rather than returning partial
  data. `GameTeam#team` resolves the side through `Teams.find_by_source_id(:nhl, id)`.
- The NHL client (`NHL::Client`) is a thin `get_json(path)` over `Cache::Raw`, for this and the
  later M2 adapters.

## Alternatives considered

- **`/score/{date}` per day for ranges.** One request per day instead of per week, and it carries
  live detail the schedule doesn't need. M2-03 uses it for scores.
- **Keep the NHL's raw codes (`"OFF"`, `2`) in the model.** Less mapping, but consumers would
  each learn that `OFF` and `FINAL` both mean over, and a code change would pass through silently.
- **Embed the full `Team` in each game.** Convenient, but it repeats the team table in every
  cached game; `GameTeam#team` looks it up when needed.
- **Fetch a team's dates by filtering weekly schedules.** Works for short ranges; for a season it
  takes about 30 requests where the club endpoint takes one.

## Consequences

- Live-state detail (clock, period, goals) belongs to M2-03 and M2-04, which can reuse `Game` and
  `GameTeam` or extend them with a schema bump.
- A range costs one request per week; a whole season by date is about 30 requests, cached by the
  raw cache.
- New NHL codes (a new `gameScheduleState`, say) fail loudly until they're added to the maps.
- Recorded week payloads are large (about 200 KB each), so specs share one cassette of two weeks.
