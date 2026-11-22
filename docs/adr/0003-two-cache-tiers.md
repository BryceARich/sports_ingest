# 0003. Two cache tiers: raw HTTP and processed models

- **Status:** Accepted
- **Date:** 2026-11-22
- **Issue:** #2

## Context

Sources are slow, rate-limited, or occasionally down (NHL endpoints are undocumented and change
between seasons). Parsing and especially player matching are expensive enough that consumers
shouldn't redo them on every run. Licensed EH and PuckPedia data never travels over HTTP at all:
it comes from manually exported files. Different data goes stale at different rates (live scores
in seconds, season totals in a day, draft history never).

## Decision

We will have two cache tiers.

1. **Raw cache** (M1-06): HTTP responses keyed by request. Backends are memory, disk or off. Each
   source has its own TTL. When the network errors, a stale cached response is served instead of
   failing.
2. **Processed cache** (M1-07): normalized and matched model collections saved as JSON, with
   metadata: `source`, `fetched_at`, and `schema_version`. Consumers read this tier instead of
   re-importing.

## Alternatives considered

- **Raw cache only.** Simple, but every consumer re-parses and re-matches on every run, and
  file-based licensed sources get no caching at all.
- **Processed cache only.** Avoids repeated work, but any change to a model or parser would force
  re-fetching everything from the network, and there'd be no stale-on-error fallback per request.
- **An HTTP caching proxy or an off-the-shelf HTTP cache middleware alone.** Covers tier 1 only, and
  `Cache-Control` headers from these APIs are not reliable enough to drive TTLs.

## Consequences

- A parser or model change can be re-run against the raw cache without hitting the network.
- `schema_version` lets readers detect and reject (or rebuild) processed data written by an
  older model shape.
- Two tiers mean two invalidation stories; TTLs are per source in configuration (M1-04), and the
  processed tier is rebuilt from the raw tier or the source when its schema version changes.
- Stale-on-error means callers can get old data silently; `fetched_at` must be exposed so they can
  tell.
- Both tiers live outside the repo by default. Processed data derived from licensed sources falls
  under [ADR 0005](0005-licensed-data-never-committed.md).
