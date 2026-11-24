# 0036. Read ESPN draft picks from the league view, and past seasons from leagueHistory

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #36

## Context

M4-05 needs a league's draft: the picks in order, and which of them are keepers. ESPN serves a
draft in two places: the `mDraftDetail` view of a league, which works for the season the league
is on, and `/leagueHistory/{leagueId}?seasonId=` for earlier seasons, with the same view.

## Decision

- **`ESPN::Drafts#fetch(league_id, season:)`** reads `mDraftDetail` from the league endpoint.
- **`ESPN::Drafts#history(league_id, season:)`** reads `leagueHistory/{id}?seasonId=...` with the
  same view and picks the entry whose `seasonId` matches. No matching entry raises `NotFound`.
- **Result is a `Draft` model** holding `DraftPick` models sorted by overall pick. A keeper is a
  pick with `keeper: true`, so `Draft#keepers` is a filter, not a second list.
- **IDs stay ESPN's.** `team_id` is the fantasy team's ID inside the league and `player_id` is
  ESPN's player ID. Neither is mapped to a name here; the player crosswalk (M3) and the player
  pool (M4-03) do that.
- **Parse errors are `SourceChangedError`** (source `:espn`), naming the missing key.

## Alternatives considered

- **Use `fetch` for past seasons too,** by passing an old `season:` to the league endpoint. ESPN
  doesn't keep every past season there; `leagueHistory` is the endpoint built for that.
- **Map player and team IDs to names inside the draft.** It would need the player pool and the
  league's teams in one call, which is M4-03's and M4-02's job. Keeping IDs here keeps this issue
  to one request per draft.
- **Separate `Keeper` model.** A keeper is a pick ESPN flags, so a second list would duplicate
  the picks and could drift from them.
