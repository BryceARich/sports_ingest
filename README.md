# sports_ingest

A Ruby gem for **reading** sports data and turning it into clean, cached Ruby models that other
projects (fantasy tools, dashboards, a future API) consume.

> **Status:** early development (M1 Foundation). The gem skeleton exists; no source adapters yet.
> See [`docs/RESUME.md`](docs/RESUME.md) for current status and the next issues.

## Goals

- **One place to read sports data.** Consumers `require` the gem instead of re-implementing
  fetching, parsing, caching and player matching in every project.
- **Clean models.** Every source becomes immutable Ruby value objects with a schema version.
- **One player identity.** Each player gets a canonical ID, and every source maps to it through
  a crosswalk.
- **Cached and offline-friendly.** A raw HTTP cache (served stale when the network fails) and a
  processed cache of normalized models, both JSON on disk. No database.
- **Load only what you use.** `require "sports_ingest/nhl"` loads core plus NHL, nothing else.
- **Runs on a Raspberry Pi.** Core has no native-extension dependencies.
- **Respect licensed data.** Evolving-Hockey and PuckPedia exports are read from files you export
  yourself and never enter git.

## Sources

| Source | Module | Notes |
|---|---|---|
| Source | Module | Notes |
|---|---|---|
| [NHL](docs/sources/nhl.md) (`api-web.nhle.com`, `api.nhle.com/stats/rest`) | `sports_ingest/nhl` | public, no auth |
| [ESPN Fantasy](docs/sources/espn.md) | `sports_ingest/espn` | read-only; private leagues need `espn_s2` + `SWID` cookies |
| [nflverse releases](docs/sources/nflverse.md) | `sports_ingest/nflverse` | GitHub release files |
| [Evolving-Hockey + PuckPedia](docs/sources/advanced_hockey.md) | `sports_ingest/advanced_hockey` | licensed, manually exported files only |

They arrive in milestones M2 to M6. So far: the NHL adapter, the Evolving-Hockey skater GAR import,
the ESPN Fantasy client and nflverse release downloads. Each source's usage examples are in its
doc, linked above; [`docs/sources/README.md`](docs/sources/README.md) indexes the notes.

## Quick start

```ruby
require "sports_ingest"

SportsIngest::VERSION # => "0.1.0"
```

Each source loads on its own, with core but no other source:

```ruby
require "sports_ingest/nhl" # SportsIngest::NHL, nothing from ESPN, nflverse or CSV
```

Teams resolve from any source's code, in core:

```ruby
team = SportsIngest::Teams.fetch("T.B")    # the advanced-stats code; "TBL", "TB" work too
team.tri_code                              # => "TBL"
team.division                              # => "Atlantic"
SportsIngest::Teams.find("UTAH", source: :espn).name # => "Utah Mammoth"
```

## Development

Ruby is pinned in `.ruby-version` and installed with [mise](https://mise.jdx.dev).
Full setup for Mac and Raspberry Pi is in [`docs/SETUP.md`](docs/SETUP.md).

```bash
mise install          # Ruby from .ruby-version
bundle install
bundle exec rspec     # tests, fully offline
bundle exec rubocop   # lint (Standard Ruby)
bundle exec yard doc  # API docs into doc/
bundle exec rake yard:coverage  # doc coverage; CI fails below 90%
bin/console           # IRB with the gem loaded
```

Rules for contributing (branches, commits, PRs, the Definition of Done) are in
[`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CLAUDE.md`](CLAUDE.md). The architecture is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), decisions in [`docs/adr/`](docs/adr/README.md), and
per-source endpoints, limits and terms in [`docs/sources/`](docs/sources/README.md).

## License

The code is available under the [MIT License](LICENSE.txt). The license covers this code only:
data you read with it stays under each source's own terms, and Evolving-Hockey and PuckPedia
exports are licensed to you personally and never belong in this repo.
