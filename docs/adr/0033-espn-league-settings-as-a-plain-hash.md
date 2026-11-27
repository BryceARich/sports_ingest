# 0033. Return ESPN league settings as a plain Hash, with hand-checked ID dictionaries

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #33

## Context

M4-02 asks for a league's scoring settings (stat ID → points), roster slots and teams "as a plain
hash plus a stat-id dictionary per sport". The first consumer is C2-01, which turns them into
scoring-rules JSON and compares them with the ScoringSystem tab of a draft spreadsheet. ESPN
doesn't document stat or slot IDs. A scoring item can also score a stat differently per lineup
slot (`pointsOverrides`): ESPN's defaults give D/ST points-allowed tiers 0 points and put the real
values under slot 16. Team `owners` are member IDs, the same GUIDs as the `SWID` cookie, which is
a secret (ADR 0010).

## Decision

- `SportsIngest::ESPN::LeagueSettings#fetch(league_id, season:)` asks for `mSettings` and
  `mTeam` and returns a Hash with Symbol keys: `league_id`, `season`, `game`, `name`, `size`,
  `scoring_type`, `scoring` (Integer stat ID => Float points), `scoring_by_slot` (slot name =>
  {stat ID => points}), `reverse_stat_ids`, `roster_slots` (slot name => count, zero counts
  dropped) and `teams` (`id`, `abbrev`, `name`, `owners` as display names).
- Member IDs are left out of the result. Owners are display names.
- Nothing goes to the processed cache: the result isn't a model collection, and the raw cache
  already holds the response for its TTL.
- `StatIds` (`id => {abbrev:, name:}`) and `LineupSlots` (`id => name`) hold the dictionaries
  for football and hockey as Ruby constants. They list only IDs we checked (`docs/sources/espn.md`
  says how); an unknown stat ID has no name, an unknown slot is named `"slot_<id>"`.
  Abbreviations are unique per sport so a consumer can map names back to IDs.

## Alternatives considered

- **Models (`Model.define`) for settings, scoring items and teams.** Gets the processed cache and
  typed fields, but the issue asks for a plain Hash, the shape differs between points and
  category leagues, and C2-01 will reshape it anyway. A model can wrap the Hash later.
- **Slots by ID instead of name.** Matches player `eligibleSlots`, but names read directly
  against a spreadsheet; `LineupSlots.for(game)` maps back.
- **Folding per-slot points into `scoring`.** One Hash, but a stat would score differently
  depending on who earns it, which a flat stat ID => points can't say.
- **A full stat dictionary copied from community libraries.** More IDs, but several of their
  entries disagree with each other and with ESPN's data; a wrong label is worse than a missing one.

## Consequences

- C2-01 reads `scoring` plus `scoring_by_slot["D/ST"]` to build its rules.
- The dictionaries need additions when a league scores a stat we haven't checked; the spec
  requires every entry to have a unique abbreviation.
- The acceptance check against the maintainer's football league needs their cookies, so it's a
  manual step, not a spec.
