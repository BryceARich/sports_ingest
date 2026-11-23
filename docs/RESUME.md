# Picking back up

Start here after time away. Update this file at the end of every milestone.

_Last updated: 2026-11-22 (M1-01 gem skeleton)._

## Current status

| Milestone | State |
|---|---|
| M0 Documentation & conventions | **done**: `CLAUDE.md`, this file, `ARCHITECTURE.md`, ADRs, issue/PR templates, `CONTRIBUTING.md` |
| M1 Foundation | **in progress**: gem skeleton (M1-01) done |
| M2 to M7 | not started |
| M8 Later | not scheduled |

The gem skeleton exists, so setup ends with green tests and a clean lint (steps 1 to 4 below).
There's no source code yet.

## Next 3 issues to take

1. **M1-02** CI matrix (#5)
2. **M1-03** Modular loading (#6)
3. **M1-04** Configuration and secrets (#7)

All issues and their order are on GitHub: <https://github.com/BryceARich/sports_ingest/issues>.
The `[Mx-yy]` prefix in each title is the build order.

## 10-minute setup on a fresh machine

### Mac

```bash
xcode-select --install        # compilers; skip if already installed
brew install mise libyaml openssl@3 git
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && exec zsh
mise settings add idiomatic_version_file_enable_tools ruby   # let mise read .ruby-version
```

`libyaml` has to be installed before `mise install`, or Ruby's psych extension fails to build.

### Raspberry Pi (64-bit Ubuntu or Raspberry Pi OS)

```bash
sudo apt update
sudo apt install -y git build-essential libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && exec bash
mise settings add idiomatic_version_file_enable_tools ruby   # let mise read .ruby-version
```

### Both

```bash
git clone https://github.com/BryceARich/sports_ingest.git
cd sports_ingest
mise install                  # 1. Ruby from .ruby-version (compiling takes ~15+ min on a Pi)
bundle install                # 2. gems
bundle exec rspec             # 3. tests: should be green, fully offline
bundle exec rubocop           # 4. lint: should be clean
```

`bin/setup` runs steps 1 and 2 for you, and adds the mise setting above if it's missing.
`mise current ruby` should print the version in `.ruby-version`.

Optional, only for ESPN private leagues (M4): copy your `espn_s2` and `SWID` cookies into
`SPORTS_INGEST_ESPN_S2` and `SPORTS_INGEST_ESPN_SWID` (for example in your shell profile, or an
untracked `.env`). Never put them in a committed file. Other settings (`SPORTS_INGEST_CACHE_DIR`,
`SPORTS_INGEST_TTL_<SOURCE>`, ...) are listed in `SportsIngest::Configuration` and ADR 0010.

## How to run everything

| What | Command |
|---|---|
| Tests | `bundle exec rspec` |
| One spec file | `bundle exec rspec spec/path/to_spec.rb` |
| Lint / autofix | `bundle exec rubocop` / `bundle exec rubocop -a` |
| API docs | `bundle exec yard doc`, then open `doc/index.html` |
| Doc coverage | `bundle exec yard stats --list-undoc` |
| Re-record fixtures (hits live APIs) | `bundle exec rake fixtures:record` |
| Console | `bin/console` |
| Check changelog fragments and ADR index | `bundle exec rake changelog:check adr:check` |
| Prepare a release (changelog + ADR index) | `bundle exec rake release:prepare[x.y.z]` |

Rows that point at later milestones (fixtures M1-10, YARD threshold M1-12) only work once those land.

## Where things live

| Path | Contents |
|---|---|
| `CLAUDE.md` | Project rules: conventions, commands, licensed-data rule |
| `CONTRIBUTING.md` | Issues, branches, commit style, PRs, how Claude Code is used |
| `.github/` | Issue and PR templates, `CODEOWNERS`, the CI workflow (`workflows/ci.yml`) |
| `docs/RESUME.md` | This file |
| `docs/ARCHITECTURE.md` | Data-flow diagram, module map, how to add a source |
| `docs/adr/` | Architecture decision records; index and template in `docs/adr/README.md` |
| `docs/sources/<source>.md` | Per-source notes: endpoints, auth, limits, quirks, terms (M1-12) |
| `CHANGELOG.md` | Keep a Changelog, newest at top; only changes at release |
| `changelog.d/` | One changelog fragment per PR (`<issue>.md`), compiled into `CHANGELOG.md` at release |
| `rakelib/` | Repo rake tasks (changelog, ADR index); not part of the gem |
| `lib/sports_ingest/` | Gem code, one folder per source (M1) |
| `spec/` | RSpec specs and recorded fixtures (M1) |
| Caches | `$XDG_CACHE_HOME/sports_ingest` or `~/.cache/sports_ingest`; override with `SPORTS_INGEST_CACHE_DIR` (M1-04) |
| Data | **Outside the repo** by default; exact path set in M1-11 |
| EH / PuckPedia exports | A local folder you drop exports into, never inside the repo |

## Known gotchas

- **macOS system Ruby (2.6) is too old.** Make sure `which ruby` points into mise, not `/usr/bin/ruby`.
  If it doesn't, the `mise activate` line isn't in your shell profile.
- **mise ignores `.ruby-version` by default** (mise 2026.x): if `mise install` installs nothing or
  `mise current ruby` warns "does not have a version set", the
  `mise settings add idiomatic_version_file_enable_tools ruby` step from setup is missing. Running
  `bin/setup` adds it. See ADR 0008.
- **CI runs on macOS (Intel) and Ubuntu (ARM64)** (`.github/workflows/ci.yml`) and reads
  `.ruby-version`, so bumping Ruby there bumps CI too. A new Ruby can take a few days to appear in
  `ruby/setup-ruby`; bump `.ruby-version` only once CI is green with it.
- **The Pi is slow to build Ruby** and native gems. That's why core avoids native extensions:
  adding one means checking it installs on the Pi first.
- **Licensed data:** EH and PuckPedia files must never be committed, including derived caches and
  snapshots. Fixtures use invented values. See `CLAUDE.md`.
- **ESPN cookies expire.** If ESPN calls start failing with auth errors, copy fresh `espn_s2` and
  `SWID` values from a logged-in browser.
- **NHL APIs are undocumented** and change between seasons. Re-record fixtures and update
  `docs/sources/nhl.md` with the date you verified them.
- **Parallel PRs:** don't edit `CHANGELOG.md` or the ADR index table, and don't take "the next
  free" ADR number. Add `changelog.d/<issue>.md` and name ADRs after the issue (ADR 0072).
  "Unreleased" in `CHANGELOG.md` looks stale between releases; `rake changelog:preview` shows
  what's pending.
- **Specs must stay offline.** If a spec needs the network, the fixture is missing; record it,
  don't allow the request.
