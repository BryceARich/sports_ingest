# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- `/spawn-unblocked` now starts Claude desktop app sessions, each in its own worktree with Remote
  Control on, instead of wrapping `script/claude/spawn-unblocked`. The script stays for headless
  runs from a terminal and now says it needs the `claude` CLI logged in.

### Added

- GitHub Actions CI (`.github/workflows/ci.yml`): specs and RuboCop on macOS (Intel) and Ubuntu
  (ARM64), Ruby from `.ruby-version` through `ruby/setup-ruby`. `bin/setup` and the Mac and Pi
  setup in `docs/RESUME.md` now turn on mise's `idiomatic_version_file_enable_tools` for Ruby so
  `mise install` reads `.ruby-version`, replacing the temporary gotcha. ADR 0008 records both (M1-02).
- Modular loading: `require "sports_ingest/nhl"`, `/espn`, `/nflverse` and `/advanced_hockey`
  each load core plus that one source through its own Zeitwerk loader
  (`SportsIngest::SourceLoader`), and core's loader ignores them. A spec proves each entry point
  loads no other source and no `CSV`, and that core has no native extensions. ADR 0009 (M1-03).
- `CLAUDE.md` and the issue and PR templates now ask for a YARD `@example` only when usage isn't
  obvious, and for short comments, with usage in the README and reasons in ADRs (M1-03).
- Gem skeleton: `sports_ingest.gemspec`, Bundler, Ruby 4.0.10 pinned in `.ruby-version` and installed
  with mise, Zeitwerk autoloading, RSpec, RuboCop with the Standard config, YARD options,
  `bin/console`, a README with the project's goals, and ADR 0007 on the toolchain. The
  `script/claude/` helpers now pass RuboCop too, and the gem is MIT-licensed. `docs/RESUME.md`
  notes that mise needs a one-time setting to read `.ruby-version` until #5 fixes setup (M1-01).
- `.claude/commands/work-issue.md` and `.claude/commands/spawn-unblocked.md`: `/work-issue` takes
  one issue from Todo to a PR awaiting review, and `/spawn-unblocked` starts a fresh headless
  Claude session in its own worktree for each issue whose blockers have merged. The GitHub
  queries live in `script/claude/` (`ready-issues`, `spawn-unblocked`, `set-status`) so they can
  run without Claude. Because the repo is public, they only act on issues and comments from people
  with a role on the repo. The AI account is set per clone (`git config claude.botUser`, shown by
  `script/claude/identity`), so no account names are hardcoded.
- Issue templates (Task, Bug, Consumer request) with Context, Acceptance criteria, Blocked by and
  the Definition of Done; a PR template with the DoD checklist; and `CONTRIBUTING.md` covering
  branching, commit style and how Claude Code is used here (M0-03).
- `.github/CODEOWNERS` naming the maintainer as reviewer for every path, used by the
  "Protect main" ruleset that requires a code-owner approval on PRs to `main`.
- `CLAUDE.md` section on Claude's GitHub identity: commits, pushes and PRs go through the
  `BryceAIRich` machine account so the maintainer can approve them.
- `docs/ARCHITECTURE.md`: data-flow diagram (Mermaid), module map and how to add a new source (M0-02).
- `docs/adr/` with an ADR template and the first six ADRs: Ruby library, no database in the library,
  two cache tiers, canonical player IDs, licensed data never committed, and the `seasons:` / `last: N`
  convention (M0-02).
- `CLAUDE.md` with project purpose, commands, code conventions and the licensed-data rule (M0-01).
- `docs/RESUME.md`, the "picking back up" guide: setup for Mac and Pi, how to run things,
  where things live, current status, next issues and known gotchas (M0-01).
