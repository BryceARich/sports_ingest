# 0015. Gate YARD coverage at 90% in CI and keep a dated note per source

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #15

## Context

`CLAUDE.md` asks for a YARD comment on every public method, but nothing checked it. Several
sessions now write code in parallel, so a missing comment would only be caught in review. The
data sources are mostly undocumented APIs (NHL, ESPN) that change between seasons; when one
breaks, we need to know what we relied on and when it last worked.

## Decision

- **Coverage gate.** `rake yard:coverage` runs `yard stats --list-undoc`, prints it, and fails when
  the "% documented" figure is below 90%. CI runs it in the test job on both platforms. The task
  takes an optional threshold (`rake 'yard:coverage[95]'`). The parsing lives in
  `rakelib/lib/doc_coverage.rb` with a spec, next to the other repo tooling (ADR 0072).
- **Source notes.** `docs/sources/<source>.md`, one per source, all with the same headings:
  endpoints used, auth, rate limits, known quirks, terms of use, and a **Last verified** line that
  says when and what was checked. `docs/sources/README.md` holds the index and the template, and
  `.yardopts` includes the notes (not their index) in the generated docs. Each adapter issue adds to its note.

## Alternatives considered

- **A coverage gem** (`inch`, `yard-junk`). More checks (tag quality, broken links), but another
  dependency to keep installing on the Pi, and their scores don't match `yard stats`, which is what
  `CLAUDE.md` tells people to run. Revisit if 90% stops catching real gaps.
- **Count undocumented objects through the YARD registry API.** No output parsing, but a second
  definition of "documented" that could drift from `yard stats`. The summary line has been stable
  for years, and the spec pins the format.
- **A higher threshold (100%).** Coverage is at 100% today, but a hard 100% would block a PR over one
  private helper YARD counts as public. 90% is what the issue asks for; raise it later if it holds.
- **Source notes in the YARD docs of each module.** Keeps them next to the code, but adapters
  don't exist yet, and endpoint quirks and terms aren't API documentation.

## Consequences

- CI fails a PR that drops coverage below 90%; `rake yard:coverage` lists what to document.
- A changed `yard stats` summary format would break the gate loudly (the task aborts), not let it
  pass silently.
- Every adapter PR now has a docs step: update its source note and its "Last verified" date.
