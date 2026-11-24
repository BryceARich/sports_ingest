# Picking back up

Start here after time away. Update this file at the end of every milestone. Setup, commands and
the file map are in [`SETUP.md`](SETUP.md).

_Last updated: 2026-11-23 (during M2)._

## Current status

| Milestone | State |
|---|---|
| M0 Documentation & conventions | **done** |
| M1 Foundation | **done**: skeleton, CI, loading, config, HTTP client, caches, errors, fixtures, licensed-data guard |
| M2 NHL adapter | **in progress** (7 of 11): teams, schedule, scoreboard, live game state, standings, rosters, player details |
| M3 Player identity | started (2 of 6): canonical IDs, name match keys |
| M4 ESPN Fantasy | started (1 of 8): client and cookies |
| M5 nflverse, M6 Advanced hockey | started (1 each) |
| M7, M8 Later | not started |

## Next issues to take

`script/claude/ready-issues` lists every issue whose blockers have merged, in build order. At
the time of writing: **M2-05** play-by-play (#20), **M2-10** polling helper (#25), **M2-11**
shared field checks on `Model` (#98).

All issues and their order are on GitHub: <https://github.com/BryceARich/sports_ingest/issues>.
The `[Mx-yy]` prefix in each title is the build order.

## Known gotchas

- **Claude sessions: run Ruby through `script/claude/run`.** The desktop app's shell doesn't
  activate mise, so `ruby` is macOS's 2.6. `script/claude/run bundle exec rspec` (or any command)
  uses the `.ruby-version` Ruby and a UTF-8 locale. Specs, rake and `script/claude/*` read files as
  UTF-8 whatever the locale.
- **CI runs on macOS (Intel) and Ubuntu (ARM64)** (`.github/workflows/ci.yml`) and reads
  `.ruby-version`, so bumping Ruby there bumps CI too. A new Ruby can take a few days to appear in
  `ruby/setup-ruby`; bump `.ruby-version` only once CI is green with it.
- **Licensed data:** EH and PuckPedia files must never be committed, including derived caches and
  snapshots. Fixtures use invented values, in `spec/fixtures/advanced_hockey/`, the one folder the
  guard allows. The pre-commit hook needs `bin/setup` once per clone; CI checks every PR. See `CLAUDE.md`.
- **ESPN cookies expire.** If ESPN calls start failing with auth errors, copy fresh `espn_s2` and
  `SWID` values from a logged-in browser.
- **NHL APIs are undocumented** and change between seasons. Re-record fixtures and update
  `docs/sources/nhl.md` with the date you verified them. Each adapter issue adds the endpoints it
  uses to its source note (`docs/sources/README.md`).
- **Parallel PRs:** don't edit `CHANGELOG.md` or the ADR index table, and don't take "the next
  free" ADR number. Add `changelog.d/<issue>.md` and name ADRs after the issue (ADR 0072).
  "Unreleased" in `CHANGELOG.md` looks stale between releases; `rake changelog:preview` shows
  what's pending.
- **Specs must stay offline.** If a spec needs the network, the fixture is missing; record it,
  don't allow the request. Cassettes replay only (record mode `none`) unless
  `SPORTS_INGEST_RECORD` is set, and never in CI. Read the cassette diff before committing: cookies
  and the configured ESPN values are scrubbed, but a source could echo something else (ADR 0013).
- **`certificate verify failed` when recording.** A mise Ruby built against Homebrew's `openssl@4`
  looks for a CA bundle that doesn't exist. Run with `SSL_CERT_FILE=/etc/ssl/cert.pem` (macOS).
