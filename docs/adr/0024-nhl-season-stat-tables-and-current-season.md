# 0024. NHL season stat tables: one `SeasonTotal` per player per season, current season turns over in October

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #24

## Context

M2-09 reads skater and goalie season totals from the stats REST API (`skater/summary`,
`goalie/summary`) for `seasons: [...]` or `last: N` (default 3). ADR 0006 asked for a shared
season-resolution helper and a per-sport "current season" that takes the date as input; ADR 0023
left that to this issue. The API returns at most 100 rows a page, so a regular season of skaters
is about ten requests, and its rows are keyed by NHL player ID with a team list rather than a team.

## Decision

- **Core helper:** `SportsIngest::Seasons.resolve(seasons:, last:, current:, default_last:)` turns
  the keywords into sorted start years. Each source supplies `current`.
- **NHL current season:** `NHL::Season.current(date)` is the date's year from October 1 on, the
  year before until then. Through the summer `last: N` still counts the season that just ended.
- **Model:** `NHL::SeasonTotal` holds `player_id`, `full_name`, `position` (`"G"` for goalies),
  `teams` (every team that season, as the API lists them) and `stats`, the `NHL::StatLine` from
  ADR 0023 with `league: "NHL"` and no `team_name`. Skaters and goalies share it.
- **Requests:** one filtered query per season and game type (`seasonId=... and gameTypeId=...`),
  sorted by `playerId` so pages don't shift, paged until `total` or an empty page. Each season is
  saved to the processed cache under `nhl/season_stats/<skaters|goalies>/<season ID>/<game type>`.
- **Game types:** `:regular` (default) or `:playoffs`, one per call.

## Alternatives considered

- **Current season from the NHL** (`/season`, or the season `/game-log/now` resolves to). Always
  right, but an extra request on every call and no way to keep specs on a fixed date. The date rule
  is wrong only between October 1 and opening night, when the new season is empty.
- **Turn over in September** (preseason, or July after the draft). `last: 3` would then include a
  season with no regular-season games for one to three months.
- **One query for the whole span** (`seasonId>=... and seasonId<=...`). Fewer requests at the
  boundaries, but a cache entry per span instead of per season, so `last: 3` and `last: 5` couldn't
  share work, and a re-fetch of the current season re-reads finished ones.
- **Flatten the stats onto the row** (`row.points`). Shorter to read, but a second copy of
  `StatLine`'s 30 fields to keep in step.
- **`game_type: :all`.** Callers can make two calls; a mixed list invites summing regular season
  and playoffs by accident.

## Consequences

- nflverse and ESPN spans (M4-03, M5-02) reuse `Seasons.resolve` with their own current-season rule.
- A first `last: 5` skater call is ~50 requests at the NHL's rate limit; the raw cache serves
  repeats within the TTL.
- `last: N` returns an empty current season for the first days of October.
- Rows carry only the NHL ID; matching to the canonical ID is the crosswalk's job (M3).
