# 0004. Canonical player IDs with a per-source crosswalk

- **Status:** Accepted
- **Date:** 2026-11-22
- **Issue:** #2 (detailed in M3-01, #26)

## Context

Every source identifies players differently: NHL player IDs, ESPN player IDs, nflverse `gsis_id`
and others, and EH and PuckPedia exports that only have names (with inconsistent accents,
nicknames and suffixes). Joining a player's stats, fantasy value and contract needs one stable key.
Fuzzy name matching is slow and occasionally wrong, so it should happen once per player, with a
way to correct mistakes by hand.

## Decision

We will give every player a canonical ID, borrowed from the most authoritative source per sport:

- **Hockey:** the NHL player ID.
- **Football:** the nflverse `gsis_id`.

A `PlayerRef` model holds the canonical ID plus each source's own ID. Each source maps to the
canonical ID through a crosswalk (M3): name normalizer, tiered matcher (exact ID, then exact
normalized name plus team/birth date, then fuzzy), manual overrides that always win, an unmatched
report, and a persisted JSON map so matching runs once per player.

## Alternatives considered

- **Our own generated IDs (UUIDs).** Independent of any source, but we would have to mint and
  store them, and every consumer would need the crosswalk just to talk to the NHL API.
- **Match on name at query time.** No stored state, but slow, non-deterministic across runs, and
  impossible to correct by hand.
- **A third-party ID registry (for example a public player-ID map).** Useful as an input to the
  matcher, but coverage and update timing are outside our control, so it can't be the key itself.

## Consequences

- Canonical IDs are meaningful outside the library (you can call the NHL API with one).
- A player who never appears in the authoritative source (rare edge cases, other leagues) has no
  canonical ID; the matcher reports them as unmatched rather than inventing one.
- The crosswalk is persisted data and needs care: overrides are reviewed, and matches derived from
  licensed exports follow [ADR 0005](0005-licensed-data-never-committed.md).
- M3-01 refines the details (the `PlayerRef` shape, other sports). If it changes the decision, it
  supersedes this ADR with a new one.
