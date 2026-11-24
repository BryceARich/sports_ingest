# 0034. ESPN player pool: actual season totals as raw stat lines, with a per-season NotFound

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #34

## Context

Fantasy tools need every player's actual season numbers from ESPN, with the same `seasons:` /
`last: N` convention as the NHL (ADR 0006). ESPN's `kona_player_info` view of the player pool carries
a `stats` array per player, with a row for each stat source (actual, projected), each split (season,
week, last 7 days, ...) and scoring period. Two things were unclear from the docs: which row is the
season total, and how ESPN signals a season it doesn't keep.

Both were checked against the live endpoint on 2026-11-23, reading only the response's shape:

- The season total is `statSourceId` 0, `statSplitTypeId` 0, `scoringPeriodId` 0. Both games have
  non-empty rows under that key; projections (`statSourceId` 1) and weekly rows are different.
- ESPN answers **200** for any season it has and **404** for one it doesn't (hockey 2005, football
  2000 are 404; hockey 2008, football 2005 are 200). A 404 is the only signal, so an error can only
  name the season that failed.
- Hockey seasons are named by the year they end (2026-27 is `2027`), football by the year they start.

## Decision

- **`SportsIngest::ESPN::PlayerPool.new(game: :hockey | :football)`** with `actual_stats(seasons:, last:,
  limit:)`. `last: 3` by default, counted from the current season, as in ADR 0006.
- **One season total per player per season.** The row with `statSourceId` 0, `statSplitTypeId` 0 and
  `scoringPeriodId` 0 is returned; players without a non-empty one are left out.
- **Raw stat lines.** The model's `stats` is ESPN's stat-ID map exactly as sent (strings such as
  `"13"`), with no `appliedTotal`. Scoring belongs to the league, which the gem doesn't know.
- **Season IDs and current season are per game**: hockey ESPN ID = start year + 1, rolling over in
  October; football ESPN ID = start year, rolling over in August (training camps).
- **A 404 on a season raises `NotFound`** that names the season and the ESPN season ID.
- **`limit:`** sends `X-Fantasy-Filter` (ADR 0032) when given; with no limit, ESPN's own default applies.
- **Processed cache** is optional (`processed:`), keyed `espn/player_stats/<game>/<ESPN season ID>/actual`.

## Alternatives considered

- **Probe `/seasons/{id}` first to find ESPN's range.** It answers for every season tried, so it can't
  tell which seasons have player data. An extra request per call that gives no answer.
- **Map ESPN's stat IDs to names (`"25"` → `goals`).** The IDs aren't documented and the mapping
  wasn't checked against a league's scoring settings. Keeping them raw is honest; a later issue can
  add names once they are verified.
- **Return ESPN's `appliedTotal`.** That's points under the default scoring, not the actual stat
  lines, and it changes with the league. The task asked for raw lines.
- **Fetch every player with no `limit`, always.** The unfiltered pool is 1–3 MB per season. `limit:`
  leaves the choice to the caller.

## Consequences

- Adapters that need a league's points apply the scoring themselves from `stats`.
- `ESPN::PlayerStats` is a new model (`schema_version` 1); its `stats` keys are ESPN's, so
  consumers should not expect names.
- The season-total selector and the 404 floors are observed values, not documented ones. They should be
  re-checked when ESPN changes its data (`docs/sources/espn.md` records the date).
