# Contributing

`sports_ingest` is a small, single-maintainer project. Most changes are made by the maintainer
or by Claude Code working on their behalf. This file is the short version of how work flows;
the full rules are in [`CLAUDE.md`](CLAUDE.md), and setup is in [`docs/RESUME.md`](docs/RESUME.md).

## Issues

- Planned work lives in GitHub issues titled `[Mx-yy] Title`, where `Mx-yy` is the build order
  (milestone `x`, item `yy`). Take issues in that order unless their "Blocked by" list says otherwise.
- New issues start from a template (**Task**, **Bug**, or **Consumer request**). Each one has
  Context, Acceptance criteria, Blocked by, and the Definition of Done checklist.
- Progress is tracked on the "Sports Ingestion" project board: **Todo → In Progress →
  Awaiting Human Review → Done**. Closing the issue moves it to Done.

## Branches

- `main` is protected: changes only arrive through pull requests with a code-owner approval.
  Never push to `main` directly.
- One branch per issue, named after its build order and a short slug, for example
  `m1-04-configuration`. Branch from an up-to-date `main`.

## Commits

- Write the subject in the imperative, under about 72 characters, and add the build order in
  parentheses when the commit belongs to an issue: `Add the shared HTTP client (M1-05)`.
- Use the body, if needed, to explain *why*, not *what*.
- Keep commits focused. Don't mix formatting-only changes with behavior changes.
- Never commit secrets (`espn_s2`, `SWID`) or Evolving-Hockey / PuckPedia data, including caches
  or snapshots derived from them. See "The licensed-data rule" in [`CLAUDE.md`](CLAUDE.md).

## Pull requests

- The PR template pre-fills the Definition of Done. Tick each item, or say why it doesn't apply
  (for example, a docs-only change has no tests or YARD comments).
- Reference the issue with `Closes #N` so merging closes it.
- Every change adds a line under "Unreleased" in [`CHANGELOG.md`](CHANGELOG.md), following
  [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) (Added, Changed, Deprecated, Removed,
  Fixed, Security).
- A decision with real alternatives gets an ADR; see [`docs/adr/README.md`](docs/adr/README.md).
- Once the gem skeleton exists (M1-01), `bundle exec rspec` and `bundle exec rubocop` must pass,
  and specs must run offline.

## How Claude Code is used here

Claude Code does a lot of the implementation, under the same review rules as anyone else:

- **Instructions.** Claude reads [`CLAUDE.md`](CLAUDE.md) (project rules) and
  [`docs/RESUME.md`](docs/RESUME.md) (current status and next issues) at the start of each session.
  Keep both current: they're how a fresh session picks the work back up.
- **Separate identity.** Claude can commit, push and open PRs as your own machine account, so you
  can review and approve its PRs. Set it per clone with `git config --local claude.botUser`; the
  full setup is in [`CLAUDE.md`](CLAUDE.md). Without one, Claude uses your own account.
- **Workflow.** For an issue, Claude creates the branch, moves the issue to In Progress, makes the
  change, opens a PR from the template, and moves the issue to Awaiting Human Review.
  It doesn't merge its own PRs; the maintainer reviews and merges. `/work-issue <N>` runs this
  for one issue. After a merge, `/spawn-unblocked` starts a separate session for each issue
  that the merge unblocked.
- **Attribution.** Commits Claude writes end with a `Co-Authored-By:` trailer, and its PR
  descriptions say they were generated with Claude Code.
- **Limits.** Claude follows the licensed-data rule like everyone else, and stops and flags it if
  something that looks like a real export is about to be committed.
