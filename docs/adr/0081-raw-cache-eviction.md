# 0081. Evict raw cache entries at 10 × TTL, on read and in an hourly sweep

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #81

## Context

The raw cache ([ADR 0009](0009-raw-cache-stores-and-stale-on-error.md)) kept every entry forever
as the stale fallback, so the disk cache only grew. ESPN makes it worse: the key includes the
request headers, cookies included, so each new `espn_s2` / `SWID` login writes new entries and the
ones under old cookies (private-league data) are never read or deleted. We needed an age past which
an entry is gone, and a way to delete entries no request will ask for again.

## Decision

- **Eviction age per source**, measured from the entry's `fetched_at`. An entry at or past it is
  deleted when read and treated as missing: never served fresh **or** stale.
- **Settings**, layered like TTLs (`Configuration#evict_after_for(source)`):
  1. a per-source age, `config.evict_after = {espn: 3600}` / `SPORTS_INGEST_EVICT_AFTER_<SOURCE>`;
  2. else a default for all sources, `config.default_evict_after` / `SPORTS_INGEST_EVICT_AFTER`;
  3. else **10 × the source's TTL** (`Configuration::EVICT_AFTER_TTLS`): NHL 10 h, ESPN 2.5 h,
     nflverse 10 days. A `Cache::Raw` given its own `ttl:` multiplies that one; `evict_after:`
     overrides the age for one cache.
- **A TTL of 0 uses `default_ttl`** for the multiple (10 h by default). TTL 0 means "always try
  the network", not "no fallback": a source that always refetches still wants an old copy when the
  network is down.
- **An eviction age of 0 means never evict**, the behavior before this ADR, matching "0 turns it
  off" for the TTL's freshness window.
- **Sweep:** `Cache::Raw#prune` deletes every entry in the store past its source's age (the source
  is the first segment of the key), whatever cache wrote it, plus entries too damaged to read. It
  judges by `fetched_at` alone, so entries with another `schema_version` still age out. `#get`
  runs it after a write, at most once an hour per store per process (`Raw::SWEEP_INTERVAL`);
  callers can run it any time. Stores gain `#keys` to list entries.
- **ESPN keys stay per cookie.** Old-cookie entries are left for the sweep, which removes them
  within the eviction age (2.5 h by default) of their fetch.

## Alternatives considered

- **Sweep at startup.** A library has no startup; the first cache use is the nearest thing, and
  a long-running process (a dashboard, the future API) would never sweep again.
- **Sweep every N writes.** Bounds work per write, but a quiet process could go days between
  sweeps, and N has no natural value. Once an hour is cheap (one directory listing and a JSON read
  per entry) and bounds how long dead entries linger.
- **Sweep only on demand, or from a rake task or cron job.** Nobody would run it, and the old
  ESPN entries the issue is about would stay on disk.
- **Judge age by file mtime.** Skips reading each file, but mtime changes when files are copied or
  restored, and memory stores have none. `fetched_at` is what freshness already uses.
- **A fixed default age (say 7 days).** Ignores that sources change at very different rates; a
  multiple of the TTL scales with how fresh each source needs to be.
- **TTL 0 means no stale fallback (evict at once).** Simple, but conflates "don't trust the cache
  when online" with "don't keep anything", and would make TTL 0 silently drop the offline copy.
- **Key ESPN requests by league and `SWID`, not `espn_s2`.** A new login would reuse the cache, but
  the raw cache would need ESPN's cookie format, and an `espn_s2` from one account with another's
  `SWID` could read that account's cached private league. The ESPN adapter (M4) can revisit this
  with an explicit cache key if refetching after a login proves costly.

## Consequences

- With no settings, a response is served stale for at most 10 × TTL after it was fetched; past
  that, a network failure raises `HTTPError` as if nothing were cached. Sources that want a longer
  offline window set `SPORTS_INGEST_EVICT_AFTER_<SOURCE>` (or 0 for forever).
- The disk cache is bounded by what was fetched within each source's eviction age, plus up to an
  hour between sweeps.
- Entries fetched under old ESPN cookies are deleted by the next sweep after their age passes.
- A `get` that triggers a sweep pays for listing and reading the whole raw store once an hour.
- Stray `*.tmp` files from a crash mid-write aren't entries, so the sweep leaves them.
