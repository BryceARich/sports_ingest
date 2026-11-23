# 0009. Cache raw responses by wrapping the client, in a pluggable store, stale on network failure

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #9

## Context

[ADR 0003](0003-two-cache-tiers.md) set up a raw HTTP cache tier: memory, disk or off, keyed by
request, a TTL per source, and a stale copy served "when the network errors". The shared HTTP
client (M1-05, [ADR 0008](0008-http-client-on-net-http.md)) does no caching. Several details had
real alternatives: where the cache hooks in, what the key holds (ESPN requests carry secret
cookies), which failures count as "the network errors", how callers learn a response is stale, and
how entries are stored on disk.

## Decision

- **A wrapper, not a client option.** `SportsIngest::Cache::Raw.new(client:)` has the same `#get`
  as `HTTP::Client` and wraps it. The client stays about the wire; adapters choose to cache by
  wrapping.
- **Stores hold JSON-ready Hashes** behind one small interface (`read`, `write`, `delete`,
  `clear`): `MemoryStore` (one per process, shared), `DiskStore` (one JSON file per entry under
  `<cache_dir>/raw/<source>/`) and `NullStore` (off). The processed tier (M1-07) can reuse them.
  The mode is a setting, `Configuration#raw_cache` / `SPORTS_INGEST_RAW_CACHE`, default `:disk`.
- **Key:** SHA-256 of the source, URL, params and request headers (lowercased names, sorted).
  `Secret` values are revealed only into the digest, so different ESPN cookies never share an
  entry and no cookie is written anywhere. Response `Set-Cookie` headers are dropped before storing.
- **Fresh** means younger than the source's TTL (`Configuration#ttl_for`); a TTL of 0 always
  refetches. Entries are kept past their TTL, as the stale fallback.
- **Stale on error:** when the client raises `HTTPError` with no status (timeout, connection
  error) or with 408, 429 or 5xx after its retries, the stored entry is returned however old.
  `AuthError`, `NotFound` and `ParseError` are raised even with an entry stored: they mean the
  request itself is wrong (expired cookies, a moved endpoint), and hiding that behind old data
  would delay the fix.
- **Callers can tell:** `HTTP::Response` gains `fetched_at` (when it came off the network) and
  `stale` / `stale?`.
- **Disk safety:** files are written to a temp file and renamed into place, created `0600` in
  `0700` directories. A file that doesn't parse, or has another `schema_version`, reads as a miss.
  Bodies that aren't valid UTF-8 are stored Base64-encoded with their encoding name.

## Alternatives considered

- **Caching inside `HTTP::Client#get`.** One less object for adapters, but it mixes retry and
  wire concerns with storage, and every client spec would have to think about a cache.
- **Off-the-shelf middleware (Faraday HTTP cache, `ActiveSupport::Cache`).** Pulls in a stack the
  gem doesn't use (ADR 0008 chose plain Net::HTTP) and drives TTLs from `Cache-Control`, which these
  APIs don't set reliably (ADR 0003).
- **Serving stale on every error, 4xx included.** Keeps dashboards up through anything, but an
  expired ESPN cookie would silently return days-old data instead of an `AuthError`.
- **Key on URL only.** Simpler, but two ESPN leagues or accounts fetched with different cookies
  would read each other's cached responses.
- **Marshal or one SQLite file on disk.** Marshal isn't safe to load from a shared directory and
  breaks across Ruby versions; SQLite is a native extension (the Pi rule in `CLAUDE.md`) and the
  library keeps no database ([ADR 0002](0002-no-database-in-library.md)).
- **Signal staleness with a warning or a callback.** Easy to miss; a field on the response travels
  with the data, as ADR 0003 asks for `fetched_at`.

## Consequences

- Adapters wrap their client: `Cache::Raw.new(client: HTTP::Client.new(source: :nhl))`. Code that
  uses the client bare is uncached.
- The disk cache grows without bound; nothing evicts old entries yet. `DiskStore#clear` (or
  deleting `<cache_dir>/raw`) resets it. Eviction can come later if a Pi's disk fills.
- Private-league ESPN responses sit on disk, readable by the owner only. Cookies themselves never do.
- A stale response looks like a normal one unless the caller checks `stale?` or `fetched_at`.
- Changing the stored layout means bumping `Cache::Raw::SCHEMA_VERSION`; old entries become misses.
