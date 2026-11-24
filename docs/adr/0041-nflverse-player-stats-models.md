# 0041. Player stats as numeric columns keyed by nflverse name, one model per grain

- **Status:** Accepted
- **Date:** 2026-11-24
- **Issue:** #41

## Context

The `stats_player` release has one file per season for weekly lines (`stats_player_week_<season>.csv`,
regular and postseason games) and one for regular-season totals (`stats_player_reg_<season>.csv`).
Each has the same identity columns and more than a hundred stat columns, and nflverse adds columns
over time. M5-02 has to load these as models for `seasons:` / `last:` (ADR 0006), and the
acceptance criterion is that `last: 3` season-level stats load.

Two things had to be decided: which stat columns a model carries, and whether weekly and season
lines share one model.

## Decision

- **Stats are a Hash keyed by the nflverse column name** (`"passing_yards"`), holding every numeric
  cell that has a value. Blank and `NA` cells are left out, not stored as `nil`. Identity columns
  (`player_id`, `recent_team`, `week`, ...) are never in the hash.
- **Two models, one per grain:** `Nflverse::PlayerWeekStats` (one game) and
  `Nflverse::PlayerSeasonStats` (one regular season). They share the identity fields; the weekly
  model adds `season_type`, `week` and `opponent`.
- Reads go through `Nflverse::PlayerStats`, which parses each season's file through
  `ReleaseDownloader` (ADR 0040) and saves it to the processed cache under
  `nflverse/player_stats/{weekly,season}/<season>`.

## Alternatives considered

- **A typed field per stat.** Consumers get `stats.passing_yards` and typos fail early. But the
  list is more than a hundred columns, nflverse changes it, and every change would be a
  `SCHEMA_VERSION` bump. Adding a column would also break cached entries for no reason. A curated
  subset would drop columns consumers need, and a fantasy tool can't know in advance which ones.
- **One model with `week` nil for season rows.** Fewer classes, but a season total and a game line
  are different things. The weekly model would carry `opponent`, which has no meaning for a season,
  and the `week` field would be optional for a reason.
- **Keep the raw CSV rows.** No parsing, but every consumer re-does the NA handling and the integer
  versus float question, and it wouldn't match the models the other sources return.

## Consequences

- Stat names are the nflverse names, so consumers look them up as strings and get `nil` for a column
  that doesn't exist in their season (for example, `passing_yards` for a receiver). They can rely on
  the keys matching the nflverse data dictionary.
- A new nflverse column appears in `stats` on the next read with no code change and no schema bump.
  Keys and values round-trip through JSON, so the processed cache's round-trip check holds.
- Blank cells are indistinguishable from missing columns. That's fine for totals (no value means
  nothing happened), but a consumer who needs "zero versus unknown" has to check the column list.
- `season_type` is kept on weekly lines, so postseason games (`"POST"`) are told apart from the
  regular season without a second file.
