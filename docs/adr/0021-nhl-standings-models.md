# 0021. Model NHL standings as typed rows with the team ID from the team table

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #21

## Context

The web API's `/standings/{date}` returns one flat row per team: about 80 keys, names localized
(`{"default": ..., "fr": ...}`), the same nine counts repeated with `home`, `road` and `l10`
prefixes, and ranks for every split (`leagueHomeSequence`, `divisionL10Sequence`, ...). It has no
team ID, a `placeName` that differs from the team table for the New York teams, and an 8-digit
`seasonId`. This is the first NHL adapter, so it also has to decide how the NHL code reaches HTTP.

## Decision

We will:

- add one `NHL::Client` with `get_json(path)` and `stats_json(path, params:)` for the two hosts,
  raw-cached with the `:nhl` TTL, shaped like `ESPN::Client`, for every NHL adapter to share;
- map each row to an `NHL::Standing` model with named fields (`division_rank`, `ot_losses`,
  `point_pct`, ...) and three nested `NHL::Record`s (`home`, `road`, `last_10`), keeping only the
  `default` name and the overall ranks;
- fill `team_id` from `SportsIngest::Teams` by tri-code (ADR 0016), `nil` when the table doesn't
  know the code, instead of failing the whole table;
- turn `seasonId` 20262027 into `season: 2026` (ADR 0006), `wildcardSequence` 0 into `nil`;
- raise `SourceChangedError` when a field the model reads is missing or of the wrong type.

## Alternatives considered

- **Keep the raw row as a Hash.** No mapping to maintain, but consumers would learn the NHL's
  key names and the processed cache would store whatever shape the NHL sends that season.
- **Every split rank** (`divisionHomeSequence`, ...) **and French names.** Cheap to add, but
  nothing needs them yet; adding fields later is a `SCHEMA_VERSION` bump, not a redesign.
- **Raise on an unknown tri-code.** Stricter, but a new or relocated team would break standings
  until the table catches up; a `nil` ID is visible and the rest of the table stays usable.
- **One client per host, or calls straight to `HTTP::Client` from each adapter.** Either works;
  one small client keeps the base URLs, `NotFound` / `ParseError` mapping and caching in one place.

## Consequences

- Other M2 adapters (schedule, scores, rosters) should use `NHL::Client` rather than add their own.
- The standings aren't yet written to the processed cache; that's for whoever first needs them
  across processes.
- Split ranks and localized names are dropped; recover them from the raw cache if a consumer asks.
