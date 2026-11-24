# 0031. Persisted crosswalk: a dedicated JSON file of matched links, outside the processed tier

- **Status:** Accepted
- **Date:** 2026-11-24
- **Issue:** #31

## Context

The tiered matcher ([ADR 0028](0028-tiered-player-matcher.md)) does fuzzy work: name keys,
birth dates, positions and teams are compared for every record. Matching a whole import again on
every run repeats that work for players who were already resolved, and a player's canonical ID
shouldn't move between runs. The crosswalk stores what the matcher decided so a record is matched
once. Manual overrides ([ADR 0029](0029-manual-overrides.md)) sit in front of every tier and can be
edited at any time.

## Decision

`SportsIngest::Identity::Crosswalk` wraps a `Matcher` for one sport:

- `resolve(...)` takes the same arguments as `Matcher#match`, in this order: an override (via the new
  `Matcher#override_for`), then a stored link, then `Matcher#match`. Only matched, non-override results
  are stored. A stored link returns its original reason, with `crosswalk:` added to the detail.
- A link is keyed by the record's raw fields: source, source ID, name, birth date, position and team.
  The same record always gives the same key.
- Unmatched results (`:ambiguous`, `:no_match`) are not stored. The known pool may grow, so they are
  retried.
- Overrides are not stored. Every lookup checks them first, so changing the overrides file takes
  effect at once, and a link stored before an override can't beat it.
- The file is one JSON document per sport, `<cache_dir>/crosswalk/<sport>.json`, with a format
  version. It's written by `save` (or `resolve_all`, which saves once at the end). Each write is
  atomic, through `Cache::DiskStore`. A file for another sport or format version is ignored. A
  damaged link is matched again.
- `clear` deletes the file, for when the matching rules change ([ADR 0027](0027-name-match-keys.md)).

## Alternatives considered

- **Store the links in the processed cache** (`Cache::Processed#write` of `PlayerRef`s). That
  fits the existing tier, but a processed entry holds one model class and needs a `PlayerRef`
  per matched player, so the source-record keys would have to live somewhere else anyway. It is
  also dropped when `processed_cache = :off`, which would silently re-run every match.
- **Store the overrides' results too, and return them without checking the file.** Avoids one
  lookup, but a stored override result would then beat a later edit to the overrides file, which
  is the opposite of ADR 0029.
- **Store unmatched results.** Speeds up re-runs, but a record that's ambiguous today matches
  tomorrow once the missing player is known, and the stored result would hide that.
- **Key links by canonical ID and source ID only.** Not enough for name-only sources (PuckPedia
  names with no IDs), where the birth date or position is what tells two players apart.
- **A database table.** The library has no database ([ADR 0002](0002-no-database-in-library.md)).

## Consequences

- The second import of a file does no fuzzy matching: `Matcher#match` isn't called for a record that
  already has a link. Specs check this with a spy.
- A stored link keeps its reason even if the matching rules later change. Use `clear` (or delete the
  file) after changing them, as ADR 0027 notes.
- Matches derived from licensed exports are stored under the crosswalk's directory, which defaults to
  outside the repo, as [ADR 0005](0005-licensed-data-never-committed.md) requires.
