# 0005. Licensed data is never committed

- **Status:** Accepted
- **Date:** 2026-11-22
- **Issue:** #2 (enforced by M1-11, #14)

## Context

Evolving-Hockey and PuckPedia data is licensed to the user personally. Their terms don't allow
redistribution, and this repository is public on GitHub. Leaks are easy: a real export dropped in
the repo for testing, a processed cache or snapshot that contains derived values, a VCR cassette.
Once pushed, data stays in git history and forks even after deletion.

## Decision

We will never commit licensed data or anything derived from it.

- Real EH and PuckPedia exports, and caches, crosswalk entries or snapshots derived from them,
  stay out of git.
- Data and cache directories default to locations outside the repo (or gitignored paths).
- Test fixtures for these sources use the real column layouts with **invented values**.
- Input is manually exported files. No scraping or auto-downloading from EH or PuckPedia until a
  later ADR (M6-09) decides otherwise.
- A pre-commit hook and a CI check (M1-11) block likely exports; reviewers and Claude still check,
  because the guard can't catch everything.

## Alternatives considered

- **A private repo or private submodule for licensed data.** Keeps it out of the public repo but
  still copies it to GitHub's servers and to every clone, which the license doesn't cover.
- **Commit encrypted exports.** The data still gets redistributed; keys leak; and it complicates CI.
- **Rely on `.gitignore` alone.** Easy to bypass with `git add -f` or a file in an unexpected path.

## Consequences

- Specs for licensed sources can never use real values, so fixtures must be hand-made and kept in
  sync with the real column layout.
- New contributors (and fresh machines) can't run the licensed-source pipeline end to end without
  their own exports; that's intended.
- Snapshots that include licensed data are personal files, never release artifacts.
- The rule is repeated in `CLAUDE.md` so it applies to every change, not only M6 work.
