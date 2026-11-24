# 0043. Cross-source player IDs from the nflverse `players` release, keyed by GSIS ID

- **Status:** Accepted
- **Date:** 2026-11-24
- **Issue:** #43

## Context

ESPN Fantasy, Sleeper and PFR each number players their own way. The nflverse stats (ADR 0041)
are keyed by GSIS ID, so a fantasy roster from ESPN has to be joined to them through a lookup
table. M5-04 needs the acceptance criterion "an ESPN id → gsis_id lookup works".

Two things had to be decided: where the table comes from, and what a lookup returns when an ID
doesn't map to exactly one player.

## Decision

- **Source:** the `players.csv` file of the `players` release, fetched through `ReleaseDownloader`
  (ADR 0040). It already carries `gsis_id` beside `espn_id`, `sleeper_id` and `pfr_id`, so no
  other source is needed.
- **Model:** `Nflverse::PlayerId`, one per row with a GSIS ID, holding the name, position and a hash
  of the source IDs the player has (`{"espn" => "1002"}`). A source with no ID is left out of the
  hash rather than stored as `nil`, the same way blank stat cells are left out of ADR 0041.
- **Lookup:** `Nflverse::IdMap#gsis_id(source:, id:)` returns the GSIS ID, or `nil` when no player
  has that ID, the ID is blank, or the source is one the table doesn't know (which raises
  `ArgumentError`, since that's a caller bug, not missing data).
- **Ambiguity:** an ID two or more GSIS IDs share returns `nil` rather than the first match. A
  guess would silently attach one player's stats to another, which is worse than no match.
- **Cache:** the table is saved to the processed cache under `nflverse/id_map`.

## Alternatives considered

- **Use the `ffverse` player ID file.** It has the same mapping, but it's a second release to fetch,
  track and keep in step with the stats files. The `players` release is already downloaded for the
  rest of the nflverse work and is the one nflverse keys its stats to.
- **Return the first GSIS ID when an ID is shared.** Simpler, and right most of the time. But the
  error is silent, and it can't be seen downstream, so a fantasy tool would show the wrong player
  with no sign anything went wrong.
- **Raise on a shared ID.** Makes the problem visible, but one upstream duplicate would make every
  lookup fail, not just the one ID. Returning `nil` for that ID alone keeps the rest of the table
  working.
- **Store one model per source ID, not one per player.** Each lookup becomes a row, but the player's
  name and position would repeat for each source, and the cross-source view a consumer wants
  (ESPN ID and Sleeper ID for one player) would need a join.

## Consequences

- Lookups are built once per `IdMap` instance, from the parsed table, so repeated calls don't reparse
  the file.
- A player with no ID in a source is missing from that source's lookup. A consumer that needs to
  tell "no ID" from "shared ID" has to check the player's `ids` hash.
- Only `espn`, `sleeper` and `pfr` are wired in. Adding a source is one line in
  `Nflverse::IdMap::ID_COLUMNS`, plus a schema-free change, since `ids` is a hash.
