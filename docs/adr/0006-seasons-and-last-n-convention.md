# 0006. One time-range convention: `seasons:` or `last: N`

- **Status:** Accepted
- **Date:** 2026-11-22
- **Issue:** #2

## Context

Many calls load a span of seasons: NHL season stat tables (M2-09), ESPN player pools (M4-03),
nflverse weekly and season stats (M5-02). Sources spell seasons differently: the NHL uses
`20242025`, ESPN and nflverse use a single year. Fantasy use usually wants "the last three
seasons", while analysis wants specific ones. Without a rule, each adapter would grow its own
keyword arguments (`from:`, `to:`, `years:`, `season_count:`).

## Decision

Every method that loads a span of seasons accepts exactly one of:

- `seasons: [2024, 2025]` — an explicit list, or
- `last: N` — the N most recent seasons, counting the current one.

A season is named by the calendar year it **starts** in (`2024` means 2024-25 for the NHL and the
2024 NFL season). Adapters convert to each source's own format internally. Passing both keywords,
or neither when the method has no default, raises `ArgumentError`. A method may define a default
(for example `last: 3` for NHL season tables) and documents it in YARD.

## Alternatives considered

- **Date ranges (`from:` / `to:`).** Precise, but seasons don't align with calendar dates across
  sports, and callers think in seasons.
- **A `Range` (`2022..2024`).** Neat, but can't express non-contiguous lists and still needs a
  separate way to say "last N".
- **Each source uses its native format.** Least work per adapter, most confusion for consumers
  who mix sources.

## Consequences

- Consumers learn one pattern for every source.
- Every adapter needs a small, shared season-resolution helper (current season per sport, start
  year to native format), tested once in core.
- "Current season" depends on the date and the sport (an NHL season starts in October), so the
  helper must take the date as an input to keep specs deterministic.
- Single-game or single-day calls (schedule, scoreboard) use dates, not this convention.
