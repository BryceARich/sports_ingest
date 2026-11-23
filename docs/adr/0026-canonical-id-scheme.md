# 0026. Store canonical IDs as sport-scoped strings in a `PlayerRef` model

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #26

## Context

[ADR 0004](0004-canonical-player-ids.md) chose the canonical ID per sport (the NHL player ID for
hockey, the nflverse `gsis_id` for football) and said a `PlayerRef` model holds it plus each
source's own ID. It left the details to M3-01: how IDs are typed, how hockey and football IDs are
kept apart, what `PlayerRef` validates, and how a new source or sport is added. The normalizer,
matcher, overrides and persisted crosswalk (M3-02 to M3-06) all build on this shape, and the
persisted crosswalk will be JSON ([ADR 0002](0002-no-database-in-library.md)).

The IDs differ in type: NHL IDs are integers (`8478402`), `gsis_id`s are strings with a leading
zero and a dash (`00-0033873`), ESPN IDs are integers, Evolving-Hockey uses strings like
`CONNOR.MCDAVID`.

## Decision

We will add `SportsIngest::Identity::PlayerRef`, a model ([ADR 0011](0011-models-on-ruby-data.md))
with three fields:

- `sport`: a Symbol, `:hockey` or `:football` (strings are accepted and converted, so JSON
  round-trips).
- `canonical_id`: a **String**, whatever type the source uses. It must match the sport's format:
  digits with no leading zero for hockey, `NN-NNNNNNN` for football. Integers are accepted and
  converted.
- `source_ids`: a Hash from source name (lowercase snake_case Symbol, such as `:espn` or
  `:evolving_hockey`) to that source's ID as a String. The canonical source's entry (`:nhl` or
  `:nflverse`) is always present, filled in from `canonical_id`; a conflicting entry raises
  `ArgumentError`. Keys are sorted so equal refs serialize identically.

Canonical IDs are unique within a sport only. `PlayerRef#key` (`"hockey:8478402"`) is the
cross-sport key, for maps that hold both. `with_source_id` returns a copy with one source added,
which is how the matcher will grow a ref. Invalid input raises `ArgumentError`, like every model
constructor.

A new source needs no code change here: it picks a source name and adds its IDs. A new sport adds
an entry to `PlayerRef::CANONICAL_SOURCES` and `PlayerRef::ID_FORMATS`, plus an ADR naming its
authoritative source.

## Alternatives considered

- **Keep each source's native type (Integer for NHL, String for `gsis_id`).** Saves a conversion,
  but JSON object keys are always strings, so the persisted crosswalk would hand back a different
  type than it was given, and comparisons across sources would depend on remembering which is
  which. One type removes that class of bug.
- **Prefix the canonical ID itself (`canonical_id: "nhl:8478402"`).** Unique across sports
  without a separate field, but the ID could no longer be passed straight to the NHL API, which
  was a reason for borrowing it in ADR 0004. A `sport` field plus `#key` gives both.
- **One class per sport (`HockeyPlayerRef`, `FootballPlayerRef`).** Type-level separation, but
  the crosswalk, matcher and caches would have to handle two classes that behave identically.
- **Leave the canonical source out of `source_ids`.** Less duplication, but every lookup by
  source would need a special case for the canonical one.
- **No format validation.** Accepts anything, but a swapped ID (an ESPN ID passed as the NHL ID)
  would be stored silently and matched wrongly forever. The formats are loose enough that real IDs
  can't fail them.

## Consequences

- Adapters convert IDs to strings at the boundary; consumers who call the NHL API with a canonical
  ID get a String, which the API accepts in its URLs.
- A player with no ID in the authoritative source can't have a `PlayerRef` (as ADR 0004 says,
  the matcher reports them as unmatched).
- Changing the fields or their meaning bumps `PlayerRef::SCHEMA_VERSION`, and the persisted
  crosswalk has to be rebuilt or migrated.
- `PlayerRef` lives in core (`lib/sports_ingest/identity/`), so every source can use it without
  loading another source.
