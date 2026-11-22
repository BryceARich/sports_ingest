# 0002. No database in the library; persist as JSON files

- **Status:** Accepted
- **Date:** 2026-11-22
- **Issue:** #2

## Context

The library has to keep data between runs: HTTP responses (to respect rate limits and survive
outages), normalized models, and the player crosswalk. The data volume is small (thousands of
players, a few seasons, per-league fantasy data). The library runs on a Mac and on a Raspberry Pi,
and consumers may have their own storage choices.

## Decision

We will not use a database inside the library. Everything it persists is files on disk: JSON for
the processed cache, the crosswalk and snapshots, plus the raw HTTP cache. Cache and data
directories are configurable and default to locations outside the repo.

## Alternatives considered

- **SQLite.** Queryable and a single file, but `sqlite3` is a native extension (slow or awkward to
  build on the Pi) and it adds a schema and migrations to a library whose job is reading.
- **PostgreSQL or another server database.** Requires a running server on every machine that uses
  the gem. Far more than the data volume needs.
- **Marshal or YAML files.** Marshal is Ruby-version-specific and unsafe to load from untrusted
  files; YAML is slower and has its own loading pitfalls. JSON is readable by non-Ruby consumers too.

## Consequences

- Zero setup: no server, no migrations, nothing native to compile.
- Files are easy to inspect, diff, and package as snapshots (M7).
- No ad-hoc querying; consumers load collections into memory and filter in Ruby. That's fine at
  this data size.
- Writes must be atomic (write to a temp file, then rename) so a crash doesn't leave half a file.
- If file caches stop being enough, an optional database-backed store can come later
  (M8-02, Sequel), behind the same interface, without changing this default.
