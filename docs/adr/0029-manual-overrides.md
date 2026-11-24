# 0029. Manual identity overrides in a YAML file, checked before every tier

- **Status:** Proposed
- **Date:** 2026-11-24
- **Issue:** #29

## Context

The tiered matcher ([ADR 0028](0028-tiered-player-matcher.md)) stops at ambiguity, so some source
records end up `:ambiguous` or `:no_match`, and a few automatic matches are simply wrong. A person
needs a way to say "this record is that player". The decision has to beat the automatic result,
or the same wrong match keeps coming back, and it has to live outside the repo, since it is
derived from the person's own use of licensed or personal data.

## Decision

`SportsIngest::Identity::Overrides` reads a YAML list (`Overrides.load(path)`). Each entry has
`source`, `canonical_id` and exactly one of `source_id` or `source_name`:

```yaml
- source: evolving_hockey
  source_id: ELIAS.PETTERSSON2
  canonical_id: 8483678
- source: puckpedia
  source_name: Sebastian Aho
  canonical_id: 8478427
```

- `Matcher.new(players, overrides:)` checks the overrides first, before tier 1. A match is
  `reason: :override`, confidence `:exact`, and its detail names the override.
- An ID override beats a name override for the same source.
- A name override applies to every record from that source with the same name key
  ([ADR 0027](0027-name-match-keys.md)), whatever its birth date, position or team. It's the
  coarse option, so the file's docs say to prefer `source_id`.
- An override may name a player who isn't among the matcher's known players (a roster is one
  team, say). The result is a ref built from the canonical ID alone, with the source's ID added.
- Overrides are validated when they're read: unknown keys, a missing or doubled `source_id` /
  `source_name`, a malformed source name, and two entries that give one key different players all
  raise `ArgumentError`. The matcher also checks every canonical ID against its sport when it's
  built.
- The file lives wherever the caller says. It's a person's data, so it stays out of the repo, the
  same as the licensed exports.

## Alternatives considered

- **Overrides as a constructor argument on `Match` results, applied after matching.** Simpler, but
  the override would have to undo a tier's result. Checking first means an override can't lose to
  a tier and the matcher never reports the wrong reason.
- **Overrides in `SportsIngest.configure`.** Ties a player decision to global configuration and
  means every caller shares one file. Passing the object keeps the matcher usable in tests and by
  any consumer that has its own file.
- **A database table.** The library has no database ([CLAUDE.md](../../CLAUDE.md)). A file the
  person edits by hand also gives them a diff to review.
- **Name-only overrides.** Two players can share a name in one source, so name-only overrides
  would silently merge them. ID overrides are the default; name overrides exist only for sources
  with no IDs.
- **Matching the override's position or team too.** Makes an override stop applying when a player
  moves team, the same problem the tiers exist to avoid. An override is a decision about a record,
  not a guess about a player.
