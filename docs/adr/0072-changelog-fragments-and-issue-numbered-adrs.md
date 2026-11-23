# 0072. Keep changelog entries in fragments, name ADRs after their issue, and index ADRs at release

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #72

## Context

Issues now run in parallel, one session and one PR each (`/spawn-unblocked`). Every PR appended
to the same three places, so PRs that were fine on their own conflicted with each other:

- the top of the "Unreleased" list in `CHANGELOG.md`;
- the ADR number: each PR took "the next free number", and 0008 and then 0009 were each claimed
  twice;
- the last row of the index table in `docs/adr/README.md`.

Each conflict needed a manual rebase and renumbering, and one renumbering changed an unrelated
ADR reference by mistake. GitHub's merge queue would only keep `main` green while PRs merge one at
a time, not prevent the conflicts, and it isn't available on user-owned repos anyway. GitHub's
merge button also ignores `.gitattributes` merge drivers such as `merge=union`.

## Decision

1. **Changelog fragments.** A PR adds `changelog.d/<issue>.md` (or `<issue>-<slug>.md` when an
   issue needs several), holding Keep a Changelog `### Type` sections and `- entry` lines, instead
   of editing `CHANGELOG.md`. `rake changelog:compile[version]` folds every fragment, plus anything
   still listed under "Unreleased", into a `## [version] - date` section and deletes the fragments.
   `rake changelog:check` (in CI) fails if a fragment doesn't parse.
2. **ADRs named after their issue.** A new ADR is `NNNN-slug.md`, where `NNNN` is the issue
   number padded to four digits (#72 → `0072-…`). ADRs 0001–0010 keep their names. When an issue
   number matches an existing ADR (open issues #8–#10 against ADRs 0008–0010) or one issue writes
   several ADRs, the files share the number and the slug keeps them apart. An ADR is identified by
   its file name, so links and references point at the file, not just the number.
3. **ADR index updated at release.** `rake adr:index` rewrites the table in `docs/adr/README.md`
   from each ADR's title and Status lines. PRs don't touch the table; it's rewritten at release by
   `rake release:prepare[version]` together with the changelog. `rake adr:check` (in CI) fails when
   a row is wrong (title, status, link, order or a missing file) and lists the ADRs still waiting
   for a row.
4. CI also runs on `merge_group`, so it's ready if a merge queue is turned on later.

## Alternatives considered

- **Keep editing `CHANGELOG.md`, rebase on conflict.** Works, but every parallel batch costs a
  rebase per PR, and the conflicts are pure noise.
- **`merge=union` in `.gitattributes`.** Resolves local rebases, but GitHub's merge button ignores
  it, so PRs still show as conflicting.
- **Reserve ADR numbers up front** (for example in the issue). Still needs coordination, and a
  skipped number leaves gaps or needs renumbering.
- **A letter suffix or a prefix for issue-numbered ADRs** (`0008a-…`, `i0072-…`). Gives unique
  IDs, but adds a rule to remember; sharing a number with a different slug needs no special case.
- **Commit the regenerated index table in every PR, with CI failing on any missing row.** Two PRs
  adding ADRs insert rows at the same place (after the last existing row), so they conflict on
  GitHub. The maintainer chose to let the table lag until the next release instead.
- **No committed table, only a generated one.** Avoids conflicts entirely but loses the readable
  index in the repo.

## Consequences

- Two PRs that each add a changelog fragment and an ADR merge in either order without conflicts.
- "Unreleased" in `CHANGELOG.md` only changes at release, so the full list of pending changes is
  `rake changelog:preview`, not the file. The entries already there are folded in by the next
  compile.
- The ADR index can be missing the newest ADRs until the next release; `rake adr:check` says which.
- "ADR 0008" could mean two files once issue #8 writes one, so new references link to the file.
- The Definition of Done in the issue and PR templates asks for a changelog fragment, and
  `CLAUDE.md`, `CONTRIBUTING.md` and `/work-issue` describe the new flow.
- Allowing only squash merges, auto-deleting head branches and moving to an org for a merge queue
  are repo settings, left to the maintainer.
