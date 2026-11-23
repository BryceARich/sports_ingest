# 0040. Keep nflverse release files on disk, refreshed by timestamp.json

- **Status:** Accepted
- **Date:** 2026-11-23
- **Issue:** #40

## Context

nflverse publishes its data as files attached to GitHub releases of `nflverse/nflverse-data`, one
release tag per data set (`docs/sources/nflverse.md`). Season files are several megabytes and some
are binary (parquet, `.csv.gz`). Each tag also carries a tiny `timestamp.json` whose
`last_updated` changes when the tag's files are rebuilt. The acceptance criterion for M5-01 is that
a file is downloaded once and reused until upstream changes.

The raw cache (`Cache::Raw`, ADR 0009) keeps each response as one JSON file, with binary bodies
Base64-encoded, and evicts entries at 10 x TTL. That suits API responses, not large files.

## Decision

We will download release assets with the shared HTTP client (not through `Cache::Raw`) to plain
files at `<cache_dir>/releases/nflverse/<tag>/<file>`, each with a `<file>.meta.json` beside it
recording the URL, the `last_updated` value the copy matches, and `fetched_at`. Files and records
are written atomically (temporary file, then rename) and readable by the owner only.

Freshness comes from the tag's `timestamp.json`, fetched **through** `Cache::Raw`: it's checked at
most once per nflverse TTL (a day by default), and served stale when the network fails. The asset is
downloaded again only when `last_updated` differs from the recorded value, compared as a string. If
the timestamp check or the download fails because of the network, an existing copy is returned with
`stale: true`; 404s, auth errors and malformed timestamps are raised.

## Alternatives considered

- **Assets through `Cache::Raw`.** No new storage, but large files as Base64 JSON cost a third more
  disk and a full parse to read, and freshness would be a fixed TTL rather than "upstream changed".
- **HTTP validators (`ETag` / `If-None-Match`).** Asset downloads redirect to a signed
  `release-assets.githubusercontent.com` URL that expires, so a conditional request
  would need the shared client to expose redirects and validators. `timestamp.json` is nflverse's own
  documented signal and is one tiny request per tag.
- **The GitHub releases API (asset `updated_at`).** Exact per file, but 60 unauthenticated requests
  an hour per IP; too tight for a Raspberry Pi refreshing several tags.
- **Check `timestamp.json` on every call.** Always current, but a request per file read; the
  nflverse TTL bounds that, and a caller who wants every call checked sets it to 0.

## Consequences

- A change upstream is noticed within one nflverse TTL, not immediately. Set
  `SPORTS_INGEST_TTL_NFLVERSE` lower (or 0) to check sooner.
- One tag timestamp covers all of its files, so an update to any file in a tag re-downloads every
  file of that tag we hold, on their next read. Acceptable: tags change at most daily.
- Downloads are read fully into memory before being written. Fine for the season CSVs M5 reads; streaming to disk would need a streaming method on the HTTP client.
- Release files aren't evicted. They're replaced in place, and there's one copy per file we use;
  deleting `<cache_dir>/releases` is safe at any time.
- Later nflverse adapters (M5-02, M5-03) read the returned `path` and parse it themselves.
