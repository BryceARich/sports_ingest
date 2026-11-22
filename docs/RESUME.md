# Picking back up

Start here after time away. Update this file at the end of every milestone.

_Last updated: 2026-11-22 (during M0)._

## Current status

| Milestone | State |
|---|---|
| M0 Documentation & conventions | **in progress**: M0-01 (this file, `CLAUDE.md`) done; M0-02 and M0-03 open |
| M1 Foundation | not started, no gem code exists yet |
| M2 to M7 | not started |
| M8 Later | not scheduled |

There's no Ruby code yet, so there are no tests to run. "Green tests" becomes possible once
M1-01 (gem skeleton) lands. Until then, setup ends at step 4 below.

## Next 3 issues to take

1. **M0-02** ARCHITECTURE.md and ADRs (#2)
2. **M0-03** Issue/PR templates, CONTRIBUTING, CHANGELOG (#3)
3. **M1-01** Gem skeleton (#4)

All issues and their order are on GitHub: <https://github.com/BryceARich/sports_ingest/issues>.
The `[Mx-yy]` prefix in each title is the build order.

## 10-minute setup on a fresh machine

### Mac

```bash
xcode-select --install        # compilers; skip if already installed
brew install mise libyaml openssl@3 git
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && exec zsh
```

### Raspberry Pi (64-bit Ubuntu or Raspberry Pi OS)

```bash
sudo apt update
sudo apt install -y git build-essential libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && exec bash
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

Steps 1 to 4 need the gem skeleton (M1-01). Before that, cloning the repo is the whole setup.

Optional, only for ESPN private leagues (M4): copy your `espn_s2` and `SWID` cookies into
environment variables (names are defined in M1-04). Never put them in a committed file.

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

Rows that point at later milestones (fixtures M1-10, YARD threshold M1-12) only work once those land.

## Where things live

| Path | Contents |
|---|---|
| `CLAUDE.md` | Project rules: conventions, commands, licensed-data rule |
| `docs/RESUME.md` | This file |
| `docs/ARCHITECTURE.md` | Data-flow diagram, module map, how to add a source (M0-02) |
| `docs/adr/` | Architecture decision records (M0-02) |
| `docs/sources/<source>.md` | Per-source notes: endpoints, auth, limits, quirks, terms (M1-12) |
| `CHANGELOG.md` | Keep a Changelog, newest at top |
| `lib/sports_ingest/` | Gem code, one folder per source (M1) |
| `spec/` | RSpec specs and recorded fixtures (M1) |
| Data and caches | **Outside the repo** by default; exact path set in M1-04/M1-11 |
| EH / PuckPedia exports | A local folder you drop exports into, never inside the repo |

## Known gotchas

- **macOS system Ruby (2.6) is too old.** Make sure `which ruby` points into mise, not `/usr/bin/ruby`.
  If it doesn't, the `mise activate` line isn't in your shell profile.
- **The Pi is slow to build Ruby** and native gems. That's why core avoids native extensions:
  adding one means checking it installs on the Pi first.
- **Licensed data:** EH and PuckPedia files must never be committed, including derived caches and
  snapshots. Fixtures use invented values. See `CLAUDE.md`.
- **ESPN cookies expire.** If ESPN calls start failing with auth errors, copy fresh `espn_s2` and
  `SWID` values from a logged-in browser.
- **NHL APIs are undocumented** and change between seasons. Re-record fixtures and update
  `docs/sources/nhl.md` with the date you verified them.
- **Specs must stay offline.** If a spec needs the network, the fixture is missing; record it,
  don't allow the request.
