# 0032. Read ESPN through one client per game, cookies from configuration on every request

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #32

## Context

Every ESPN adapter in M4 (leagues, rosters, player pool, history) talks to the same host with the
same URL scheme, the same `view=` parameters, the same `X-Fantasy-Filter` header and the same
`espn_s2` / `SWID` cookies. We needed one place that builds those requests, decides when cookies are
sent, and turns ESPN's refusals into errors a user can act on.

## Decision

- **`SportsIngest::ESPN::Client.new(game: :hockey | :football)`**, one per game (`fhl` / `ffl`).
  `season(year)`, `league(id, season:, views:, filter:)` and the general `get` / `get_json(path, ...)`
  cover every path in `docs/sources/espn.md`; adapters build on them.
- **Views are repeated `view=` parameters** in the URL (`?view=mTeam&view=mRoster`), because the
  shared client's `params:` is a Hash and can't repeat a key.
- **The filter is a small immutable `ESPN::Filter`**: `Filter.players(limit:, status:, ...)` for the
  common player-pool keys, `Filter.new(hash)` / `#merge` for anything else, spelled as ESPN does.
  A plain Hash is accepted wherever a filter is.
- **Cookies come from `Configuration#espn_s2` / `#espn_swid`** (ADR 0010), read at request time,
  and are sent on every request when **both** are set, as a `Secret` `Cookie` header. With only one
  set, none is sent.
- **No cookies is not an error up front.** Public leagues and the game/player endpoints need none;
  the request is made and a 401/403 raises `AuthError` whose message says which cookies are missing
  and the env vars to set, or, when they were sent, that they were rejected and may have expired.
- **Requests go through `Cache::Raw`** with the `:espn` TTL by default; `http:` swaps in any `#get`.
- **Bad arguments** (unknown game, non-positive IDs) raise `ArgumentError`, like the models do.

## Alternatives considered

- **Raise `AuthError` before the request when cookies are missing.** Breaks public leagues and the
  public endpoints, which need no cookies.
- **Send cookies only to league endpoints.** Saves nothing (same host) and every new adapter would
  have to remember to opt in.
- **Per-client cookie arguments.** A second way to pass secrets, outside the redaction and env-var
  handling `Configuration` already has; a separate `Configuration` instance does the same job.
- **Filter as a raw Hash only.** Works, but each adapter would re-spell `filterStatus` /
  `sortPercOwned`; the builder keeps that in one place and still accepts a Hash.

## Consequences

- Adapters (M4-02 on) never build URLs, headers or cookies themselves.
- Cookies are part of the raw-cache key (as digests), so new cookies mean new entries; ADR 0081's
  eviction cleans up the old ones.
- The 401 body ESPN sends for a private league wasn't checked against a real league (none on hand
  on 2026-11-23); the client relies only on the status, so the body shape doesn't matter.
