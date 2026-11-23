# 0010. Store processed collections per model class and check the round trip on write

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #10

## Context

[ADR 0003](0003-two-cache-tiers.md) set up a processed cache tier: normalized and matched model
collections saved as JSON with `source`, `fetched_at` and `schema_version`, which consumers read
instead of re-importing. Models are `Data` classes from `SportsIngest::Model.define`
([ADR 0011](0011-models-on-ruby-data.md)): they serialize with `to_h` and rebuild with `from_h`,
and each class has a `SCHEMA_VERSION`. The raw tier already has stores for memory, disk and off
([ADR 0009](0009-raw-cache-stores-and-stale-on-error.md)). The acceptance criterion is that any
model collection round-trips through the processed cache unchanged. JSON has no symbols, times or
dates, so a model only round-trips if its `initialize` coerces those back.

## Decision

We will add `SportsIngest::Cache::Processed`, on the same stores as the raw tier.

- **Entries.** One entry per caller-chosen key (`"nhl/skaters/2025"`, in `DiskStore::KEY_FORMAT`),
  holding an Array of instances of one model class plus: `format_version` (the entry layout),
  `source`, `model` (the class name), `schema_version` (the class's `SCHEMA_VERSION`),
  `fetched_at` (when the data came from the source, passed in by the caller, default now) and
  `written_at`. Disk entries live under `<cache_dir>/processed`.
- **Reading.** `read(key, model:, max_age: nil)` takes the model class from the caller. It returns
  an `Entry` (models plus metadata), or `nil` when there's no entry, the stored class name or
  schema version differs, `fetched_at` is older than `max_age`, or the entry is damaged. A miss
  means "rebuild and write again", as in the raw tier.
- **Writing.** `write(key, models, source:, fetched_at:, model:)` serializes, parses the JSON back,
  rebuilds the models and compares them with `==` before storing. A collection that wouldn't read
  back unchanged raises `ArgumentError` naming the item, and nothing is stored.
- **Mode.** A separate setting, `Configuration#processed_cache` / `SPORTS_INGEST_PROCESSED_CACHE`
  (`disk`, `memory`, `off`; default `disk`). Store selection moves to `Cache.store_for(mode, tier:)`,
  with one process-wide memory store per tier.

## Alternatives considered

- **Store the class name and constantize it on read**, so `read(key)` needs no `model:`. Shorter
  to call, but it turns a file on disk into "instantiate whatever class this names", and a
  renamed class would fail at read time rather than miss. The caller always knows what it wants.
- **Raise on a schema-version mismatch** instead of missing. Makes stale entries visible, but
  every consumer would need a rescue for what is the normal case after an upgrade. A cache should
  rebuild quietly; `fetched_at` and `written_at` are there for anyone who wants to inspect.
- **No round-trip check on write**, trusting models to coerce their fields. Cheaper, but a model
  that forgets to coerce a symbol would write entries that read back different, silently, on every
  later run. The check costs one extra parse per write, and writes are rare next to reads.
- **One setting for both tiers.** Simpler, but turning the processed tier off (to force rebuilds
  while working on an adapter) while keeping the raw tier (to avoid the network) is exactly the
  combination that's useful during development.
- **A `fetch(key) { build }` helper.** Handy, but what the block should return when its data's
  `fetched_at` comes from the raw tier isn't clear until the first adapters use it. It can be
  added on top of `read` and `write` later.

## Consequences

- Any model collection whose `initialize` coerces its non-JSON fields round-trips unchanged; one
  that doesn't is caught on its first write, in specs.
- Bumping a model's `SCHEMA_VERSION` invalidates its processed entries with no other step.
- Keys are the caller's job. Adapters should start them with the source name so sources don't
  collide.
- Processed data built from licensed sources lands under `cache_dir`, outside the repo by default,
  and falls under [ADR 0005](0005-licensed-data-never-committed.md).
