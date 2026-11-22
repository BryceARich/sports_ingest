# CLAUDE.md

**Read [`docs/RESUME.md`](docs/RESUME.md) first.** It has the current status, setup steps,
the next issues to take, and known gotchas. This file covers the rules that don't change much.

## What this project is

`sports_ingest` is a Ruby gem for **reading** sports data and turning it into clean,
cached Ruby models that other projects (fantasy tools, dashboards, a future API) consume.

Sources, in build order:

| Source | Module | Notes |
|---|---|---|
| NHL (`api-web.nhle.com`, `api.nhle.com/stats/rest`) | `sports_ingest/nhl` | public, no auth |
| ESPN Fantasy (`lm-api-reads.fantasy.espn.com`) | `sports_ingest/espn` | read-only; private leagues need `espn_s2` + `SWID` cookies |
| nflverse releases | `sports_ingest/nflverse` | GitHub release files |
| Evolving-Hockey + PuckPedia | `sports_ingest/advanced_hockey` | **licensed**, manually exported files only |

Data flows **sources → adapters → models → caches → consumers**. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the diagram, module map, and how to add a source.

Design rules already decided (each has an ADR in [`docs/adr/`](docs/adr/README.md)):

- Ruby library, **no database** in the library. Persistence is caches on disk as JSON.
- Two cache tiers: a **raw** HTTP cache (TTL per source, served stale when the network errors)
  and a **processed** cache (normalized and matched models plus metadata: source, `fetched_at`,
  schema version).
- Players get a **canonical ID**; every source maps to it through the crosswalk (M3).
- Each source loads separately: `require "sports_ingest/nhl"` must not load ESPN, CSV, etc.
  Core has **no native-extension dependencies** (it has to install cleanly on a Raspberry Pi).
- Time ranges use one convention everywhere: `seasons: [2024, 2025]` or `last: N`.

## Commands

The gem skeleton arrives in M1-01. Until then these commands don't work yet; when they
change, update this list and `docs/RESUME.md` together.

```bash
mise install                 # install the Ruby version pinned in .ruby-version
bundle install               # install gems
bundle exec rspec            # tests (offline, from fixtures)
bundle exec rubocop          # lint (standard config)
bundle exec yard doc         # build API docs into doc/
bundle exec yard stats --list-undoc   # doc coverage; CI fails below 90%
bundle exec rake fixtures:record      # re-record fixtures against live sources (M1-10)
```

## Code conventions

- Ruby, Zeitwerk autoloading, one constant per file, file paths match constant names.
- Style is RuboCop with the `standard` config. Don't disable cops inline without a comment saying why.
- Every public method gets a YARD comment: what it does, `@param`, `@return`, `@raise`, and an `@example`.
- Raise errors from the gem's own hierarchy (M1-09), never bare `RuntimeError` or library errors.
- HTTP only goes through the shared client (M1-05). Adapters never call `Net::HTTP` directly.
- Specs never hit the network. Use the VCR/WebMock fixtures; CI runs fully offline.
- Configuration goes through `SportsIngest.configure` or env vars. **Secrets** (`espn_s2`, `SWID`)
  are redacted in `inspect` and logs, scrubbed from cassettes, and never committed.
- Any decision with real alternatives gets an ADR in `docs/adr/`.
- Every change adds a line under "Unreleased" in `CHANGELOG.md` (Keep a Changelog format).
- Branch per issue, named after its build order (for example `m1-04-configuration`). Reference the
  issue in the PR, and tick its Definition of Done checklist.

## The licensed-data rule

Evolving-Hockey and PuckPedia data is licensed to the user personally. **It never enters git.**

- Never commit real EH or PuckPedia exports, or anything derived from them (cached JSON, snapshots).
- Data and cache directories default to locations **outside the repo** (or gitignored paths).
- Test fixtures for these sources use the **real column layouts with invented values**.
- Don't add code that scrapes or auto-downloads from EH or PuckPedia. Input is manually exported
  files, until an ADR (M6-09) says otherwise.
- If you see a file that looks like a real export staged for commit, stop and say so.
  The pre-commit hook and CI check from M1-11 enforce this, but don't rely on them.

## Working on an issue

1. Read `docs/RESUME.md` and the issue, including its "Blocked by" list.
2. Check the issue's Definition of Done before calling it finished.
3. At the end of each milestone, update `docs/RESUME.md` (status, next 3 issues, gotchas).
