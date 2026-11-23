# 0014. Guard against licensed data with a pre-commit hook and a CI check

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #14

## Context

ADR 0005 says Evolving-Hockey and PuckPedia data never enters git, and asks for a pre-commit hook
and a CI check that block likely exports. The guard has to run before the gem's bundle is
installed (git hooks may run outside mise, on macOS system Ruby 2.6), must not flag the code and
docs that name these sources, and must still let hand-made fixtures with invented values in.

## Decision

`script/licensed-data-guard` (stdlib Ruby, logic in `script/lib/licensed_data_guard.rb`) checks
**data-like files only** (`.csv`, `.tsv`, `.json`, `.xlsx`, `.parquet`, archives and similar). A file
is refused when its name looks like an export (`EH_...`, "Evolving-Hockey", "PuckPedia") or its
first 256 KB contains an `EH_ID` column or names either source. Files under
`spec/fixtures/advanced_hockey/` are allowed; that is where invented-value fixtures go, and
reviewers check them by hand.

It runs in three places:

- **Pre-commit hook** `.githooks/pre-commit` (`--staged`, reading the staged blobs).
  `bin/setup` turns it on with `git config core.hooksPath .githooks`.
- **CI job** "Licensed-data guard": `--all` over tracked files, and on pull requests `--range` over
  every commit in the PR, so a file added and then deleted is still caught before it reaches `main`.
- **By hand:** `script/licensed-data-guard <paths>`.

`/data/` and `/exports/` are gitignored as a second line of defence; caches default outside the
repo (M1-04).

## Alternatives considered

- **A hook manager (Lefthook, Overcommit, pre-commit).** More features, but another dependency to
  install on every machine and the Pi, for one hook. `core.hooksPath` needs nothing.
- **Block every CSV/JSON outside `spec/fixtures/`.** Catches renamed exports with unknown headers,
  but would also block legitimate NHL and nflverse fixtures and future data files.
- **Check file size or row count.** Large files aren't necessarily licensed; small exports are.
- **Gem code under `lib/`.** The guard is repo tooling, not something consumers of the gem need.

## Consequences

- The patterns are heuristics. An export renamed to something neutral, with its `EH_ID` column
  dropped, gets through; reviewers and Claude still check (ADR 0005). When the real export layouts
  are confirmed in M6, add their distinctive headers to `CONTENT_PATTERNS`.
- A hook can be skipped with `git commit --no-verify` or by never running `bin/setup`; CI is the
  backstop, and the `--range` check fails the PR, though the commits are already on GitHub by then.
- Every contributor's clone needs `bin/setup` (or the `git config` line) once for the hook.
