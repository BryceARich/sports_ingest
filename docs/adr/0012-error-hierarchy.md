# 0012. Raise one flat hierarchy of gem errors

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #12

## Context

Consumers need to tell "the network is down" from "my cookies expired" from "the NHL changed its
JSON" without knowing which HTTP or CSV library the gem uses. Adapters must raise only the gem's own
errors (`CLAUDE.md`), so the classes have to exist before the first adapter (M2).

## Decision

We will raise `SportsIngest::Error < StandardError` and five direct subclasses, one per file:

| Class | When |
|---|---|
| `HTTPError` | a failed request not covered below: 5xx, other 4xx, timeouts, connection errors. Carries `status` (nil without a response) and `url`. |
| `AuthError` | HTTP 401/403, or missing credentials (ESPN `espn_s2` / `SWID`) |
| `NotFound` | HTTP 404, or a missing import file |
| `ParseError` | a payload or file that can't be parsed at all (bad JSON or CSV) |
| `SourceChangedError` | a payload that parses but has an unexpected shape; raised instead of returning partial data |

Every error takes an optional `source:` (`:nhl`, `:espn`, ...). When wrapping a library error,
raise inside the `rescue` so Ruby keeps the original as `cause`. Errors from other milestones
(`ConfigurationError`, M1-04) also subclass `Error` directly.

## Alternatives considered

- **`AuthError` and `NotFound` under `HTTPError`.** `rescue HTTPError` would then catch every HTTP
  status, but both also cover non-HTTP cases (missing cookies, a missing import file), where
  `status` and `url` mean nothing.
- **Namespaced classes (`Error::HTTP`, `Error::Auth`).** Shorter to type, but the issue and docs
  already use the flat names, and flat names read better in `rescue` lines.
- **One `errors.rb` with every class.** Breaks the one-constant-per-file rule Zeitwerk relies on.

## Consequences

- `rescue SportsIngest::Error` catches everything the gem raises; nothing leaks from Net::HTTP,
  JSON or CSV.
- The shared HTTP client (M1-05) maps statuses: 401/403 to `AuthError`, 404 to `NotFound`, other
  failures to `HTTPError`. Adapters raise `ParseError` and `SourceChangedError`.
- A caller who wants every HTTP failure has to rescue three classes. Accepted for the cleaner
  non-HTTP cases.
- Core's loader inflects `http_error` to `HTTPError`.
