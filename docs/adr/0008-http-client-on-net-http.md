# 0008. Build the shared HTTP client on Net::HTTP

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #8

## Context

Every network call in the gem goes through one client (`CLAUDE.md`), which needs timeouts, retries
with exponential backoff on 429/5xx, per-host rate limits, a configurable user agent and gzip. The
issue leaves the library open: Faraday or Net::HTTP. Core must install cleanly on a Raspberry Pi
with no native extensions, and adapters must raise only the gem's errors (ADR 0012).

## Decision

We will build `SportsIngest::HTTP::Client` on Net::HTTP from the standard library, with no new
runtime dependency:

- **GET only.** Every source is read-only.
- **Retries** on 408, 429, every 5xx, timeouts and connection errors, 3 by default. Delays come from
  `HTTP::Backoff`: `base * 2**attempt` (0.5 s, 1 s, 2 s, ...) plus up to 25% random jitter, or the
  server's `Retry-After` (seconds or an HTTP date) when it sends one, always capped at 30 s.
- **Rate limits** per host in `HTTP::RateLimiter`: one request per host every 0.5 s by default,
  changeable per host (`RateLimiter.default.limit(host, seconds)`). Every client shares one limiter
  unless given its own, so sources that call the same host share its limit. Retries and redirects
  wait their turn too.
- **Gzip** by sending `Accept-Encoding: gzip` and inflating with Zlib ourselves, since setting that
  header turns off Net::HTTP's own decoding and doing it explicitly is testable.
- **Redirects** are followed (up to 5; nflverse's GitHub release downloads redirect to a CDN).
  Caller headers such as ESPN cookies are dropped when a redirect leaves the original host.
- **Errors** map per ADR 0012: 401/403 to `AuthError`, 404 to `NotFound`, other failures to
  `HTTPError` (the library error kept as `cause`), an undecodable gzip body to `ParseError`.
- **Timeouts, retry count, backoff and limiter** are constructor arguments, so each adapter picks
  what suits its source. The user agent comes from `SportsIngest.configuration` at request time.

Specs stub responses with WebMock, a development dependency that also blocks real network calls in
every spec. Fixture recording (VCR, [ADR 0013](0013-vcr-cassettes-for-fixtures.md)) builds on it.

## Alternatives considered

- **Faraday with `faraday-retry` and `faraday-gzip`.** Pure Ruby and well known, but three runtime
  gems (plus their dependencies) for features that take ~200 lines here, middleware ordering to get
  right, and no per-host rate limiting anyway. Swapping later stays cheap: adapters only see
  `Client#get` and `Response`.
- **A retry/rate-limit library on top of Net::HTTP.** Same dependency cost; none of them do the
  per-host spacing across threads that we need.
- **Exponential backoff without jitter.** Simpler to reason about, but parallel clients that fail
  together retry together. Tests pass `jitter: 0` to get exact delays.
- **Giving up when `Retry-After` exceeds the cap.** Politer to a server that asked for minutes, but
  an hourly-cached source is better served by one capped wait and a retry. Revisit if a source
  starts sending long values.
- **Rate limits in `SportsIngest.configure`.** Hosts belong to adapters, which know their limits;
  a configuration key can come later if users need to tune them.

## Consequences

- No new runtime dependency; core still installs without native extensions.
- WebMock brings `bigdecimal` (a native extension) into the development bundle. It isn't a runtime
  dependency, so the Pi rule for core holds, but `bundle install` on a Pi compiles it.
- The client doesn't cache yet; the raw cache (M1-06) hooks in around `Client#get`.
- One connection per request (no keep-alive). Fine at our request rates; revisit if a source needs
  many calls per run.
