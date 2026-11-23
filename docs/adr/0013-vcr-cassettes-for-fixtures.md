# 0013. Record fixtures as VCR cassettes over WebMock

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #13

## Context

Specs must never reach the network, and CI runs fully offline. Adapters (M2 onward) need real
payloads from undocumented APIs that change between seasons, so fixtures have to be cheap to
re-record and the diff readable. ESPN private-league calls carry `espn_s2` and `SWID` cookies,
which must never land in a committed file. WebMock already blocks every request in specs (M1-05).

## Decision

We will use **VCR** hooked into WebMock:

- Cassettes live in `spec/fixtures/cassettes/<source>/<name>.yml`; a spec opts in with
  `vcr: {cassette_name: "<source>/<name>"}`. Requests match on method and URI, and a cassette with
  unused interactions fails.
- Record mode is `none` (replay only) unless `SPORTS_INGEST_RECORD` names a VCR mode.
  `rake fixtures:record[path]` sets it to `all` and runs the `vcr`-tagged specs. Recording is
  refused when `CI` is set.
- Bodies are stored decoded (`decode_compressed_response`), so cassettes are plain text that can be
  read in review and searched for secrets.
- Before a cassette is written, `Cookie`, `Authorization` and `Set-Cookie` headers are dropped,
  noisy headers (`Date`, CDN ids) are dropped to keep diffs small, and the configured ESPN cookie
  values, raw and URL-encoded, are replaced with `<ESPN_S2>` / `<ESPN_SWID>`.
- A spec scans every committed cassette for cookie headers and configured secret values.

## Alternatives considered

- **WebMock stubs with hand-saved JSON files.** No new dependency, but every fixture needs a
  hand-written stub and a manual `curl`, and re-recording a season's worth of endpoints is tedious.
- **Record through the gem's own raw cache (M1-06).** Reuses our code, but couples tests to the
  cache format and gives no request matching or unused-interaction checks.
- **VCR's `filter_sensitive_data`.** It restores the real value on playback, which we don't want
  (CI has no cookies) and it doesn't remove headers, so we scrub in a `before_record` hook instead.

## Consequences

- One more development gem (`vcr`); nothing changes at runtime.
- Re-recording is one command, but the person recording must read the diff: scrubbing covers known
  secrets, not anything a source might echo back.
- Recorded values change on each re-record (live stats), so specs should assert on shape, not on
  exact numbers, unless the cassette is for a finished season.
- Licensed sources (EH, PuckPedia) are files, not HTTP, so they keep invented-value fixtures in
  `spec/fixtures/advanced_hockey/` (ADR 0005); cassettes are never recorded for them.
