# 0010. Configure through env vars and a block; wrap secrets in a redacting type

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #7

## Context

The gem needs a few settings before any source can run: where caches live, the HTTP user agent,
a raw-cache TTL per source, and the ESPN `espn_s2` / `SWID` cookies for private leagues. It runs
both inside other Ruby programs (which want to set things in code) and from a shell on a Mac or a
Raspberry Pi (where env vars are easiest). The cookies are credentials: `CLAUDE.md` says they must
never appear in `inspect`, logs or committed files. Caches must live outside the repo by default
([ADR 0005](0005-licensed-data-never-committed.md)).

## Decision

- One `SportsIngest::Configuration` object, reached with `SportsIngest.configuration` and changed
  with `SportsIngest.configure { |c| ... }`. Values are layered: built-in defaults, then
  `SPORTS_INGEST_*` env vars (read once, when the configuration is built), then the block.
- Env var names: `SPORTS_INGEST_CACHE_DIR`, `SPORTS_INGEST_USER_AGENT`, `SPORTS_INGEST_TTL`
  (default TTL), `SPORTS_INGEST_TTL_<SOURCE>` (for example `SPORTS_INGEST_TTL_NHL`),
  `SPORTS_INGEST_ESPN_S2` and `SPORTS_INGEST_ESPN_SWID`. Empty values count as unset.
- The cache directory defaults to `$XDG_CACHE_HOME/sports_ingest`, else `~/.cache/sports_ingest`:
  a per-user location outside any repository.
- TTLs are whole seconds (0 means always refetch). Unknown sources fall back to `default_ttl`, so
  a new source works before it gets its own default.
- Secrets are stored as `SportsIngest::Secret`. Its `to_s`, `inspect`, `pretty_print` and
  `to_json` all print `[REDACTED]`; only `#reveal` returns the value. `Configuration#inspect` and
  `#to_h` are built from those, so logging the configuration or a secret is safe by default.
- Invalid values raise `SportsIngest::ConfigurationError` (under `SportsIngest::Error`, which M1-09
  extends).

## Alternatives considered

- **Store the cookies as plain Strings and only redact `Configuration#inspect`.** Simpler to use,
  but `logger.info("cookie=#{config.espn_s2}")` or an exception message would leak the value.
  The wrapper makes the safe path the default and the leaking path an explicit `.reveal`.
- **ESPN's usual names (`ESPN_S2`, `SWID`) as env vars.** Shorter and matches other tools, but
  `SWID` is very generic and an unprefixed name could pick up a variable meant for something else.
  One `SPORTS_INGEST_` prefix keeps every setting easy to find with `env | grep`.
- **A YAML or `.env` config file.** Adds a parser and a file that could get committed with secrets
  in it. Env vars and code cover both ways the gem runs; a file can come later if a consumer needs it.
- **Re-read env vars on every access.** Lets env changes apply live, but makes a block override
  ambiguous. Reading once and calling `SportsIngest.reset_configuration!` to reload is predictable.

## Consequences

- The HTTP client (M1-05) and ESPN client (M4-01) must call `.reveal` at the point they build the
  `Cookie` header, and nowhere else. Cassette scrubbing (M1-10) still has to filter the revealed
  values out of recorded requests.
- Each new source adds a default to `Configuration::DEFAULT_TTLS`; its env var works automatically.
- `Secret` only protects values that stay wrapped. Code that calls `.reveal` and keeps the String
  around loses the protection.
