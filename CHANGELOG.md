# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `.claude/commands/work-issue.md` and `.claude/commands/spawn-unblocked.md`: `/work-issue` takes
  one issue from Todo to a PR awaiting review, and `/spawn-unblocked` starts a fresh headless
  Claude session in its own worktree for each issue whose blockers have merged. The GitHub
  queries live in `script/claude/` (`ready-issues`, `spawn-unblocked`, `set-status`) so they can
  run without Claude.
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
