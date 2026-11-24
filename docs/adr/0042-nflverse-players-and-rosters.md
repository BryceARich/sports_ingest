# 0042. Load nflverse players and season rosters keyed by gsis_id, skipping rows without one

- **Status:** Accepted
- **Date:** 2026-11-24
- **Issue:** #42

## Context

M5-03 needs the football player records that the player crosswalk (M3) and the fantasy player pool
(M4-03) join on. nflverse publishes two files for this, both as release assets
(`docs/sources/nflverse.md`): `players.csv` from the `players` release, one row per player, and
`roster_<season>.csv` from the `rosters` release, one row per roster entry per season. Both carry
`gsis_id`, nflverse's player ID, which ADR 0004 makes the canonical football ID and ADR 0026 keeps
in the `Identity::PlayerRef` format (`00-0033873`).

Some rows have no `gsis_id`, mostly rostered players who never got one. Those can't be keyed.

## Decision

- **`Nflverse::Players#fetch`** and **`Nflverse::Rosters#fetch(season)`** download their file through
  `ReleaseDownloader` (ADR 0040), so the file is reused until upstream changes, and return models.
- **Rows with a blank `gsis_id` are skipped**, not raised. Those players have no canonical ID, and
  one missing ID shouldn't stop the rest of the file from loading.
- **A `gsis_id` that isn't nflverse's format is a `SourceChangedError`**, as is a missing column
  or a row that doesn't fit its model (for example a birth date that isn't ISO 8601). Those mean the
  file's shape changed; partial data would hide that.
- **Results go to the processed cache** (ADR 0010) under `nflverse/players` and
  `nflverse/rosters/<season>`, with `fetched_at` taken from the download.
- **Roster entries keep one row per file row.** A player who moved teams in a season has two
  entries, and the file's order is kept. Nothing is collapsed to one row per player; that is a
  choice for the consumer.
- **Season is the one asked for**, not the file's `season` column, so a blank cell can't put a nil
  into a model.

## Alternatives considered

- **Fail the whole load on a blank `gsis_id`.** Strict, but a single unkeyed row would block every
  season, and nflverse leaves the ID blank for real players.
- **Key rows on a name or another source's ID when `gsis_id` is blank.** That is matching, which is
  M3's job; keying here would invent identities the crosswalk should decide.
- **Read the whole CSV into memory with a streaming parser.** Season files are a few megabytes;
  `CSV.parse` is simpler and fast enough for a one-off load into the processed cache.
