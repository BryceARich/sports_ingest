# Architecture decision records

Each file records one decision that had real alternatives: the context, what we chose, what we
didn't, and what follows. See [`../ARCHITECTURE.md`](../ARCHITECTURE.md) for how the pieces fit.

## Writing one

1. Copy [`0000-template.md`](0000-template.md) to `NNNN-short-title.md`, where `NNNN` is the
   issue number padded to four digits (`0072-…` for #72), not the next free number. ADRs
   0001–0010 predate this and keep their names. If the number is already taken (by one of those,
   or another ADR from the same issue), keep it: the slug keeps the files apart, so link to the
   file. See [ADR 0072](0072-changelog-fragments-and-issue-numbered-adrs.md).
2. Fill it in, keeping the first line as `# NNNN. Title`. Start with status **Proposed**; change
   it to **Accepted** when the PR merges.
3. Don't edit the index below. `rake adr:index` rewrites it from the files at release, so parallel
   PRs don't conflict on it. `rake adr:check` (run in CI) fails if a row is wrong and lists ADRs
   still waiting for a row.
4. Never rewrite an accepted ADR's decision. To change course, write a new ADR and mark the old one
   **Superseded by [NNNN](NNNN-title.md)**.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-ruby-library.md) | Build `sports_ingest` as a Ruby library (gem) | Accepted |
| [0002](0002-no-database-in-library.md) | No database in the library; persist as JSON files | Accepted |
| [0003](0003-two-cache-tiers.md) | Two cache tiers: raw HTTP and processed models | Accepted |
| [0004](0004-canonical-player-ids.md) | Canonical player IDs with a per-source crosswalk | Accepted |
| [0005](0005-licensed-data-never-committed.md) | Licensed data is never committed | Accepted |
| [0006](0006-seasons-and-last-n-convention.md) | One time-range convention: `seasons:` or `last: N` | Accepted |
| [0007](0007-ruby-toolchain.md) | Pin Ruby with mise, autoload with Zeitwerk, lint with Standard | Proposed |
| [0008](0008-ci-matrix-and-mise-setting.md) | CI on macOS Intel and Ubuntu ARM64; mise reads `.ruby-version` via a setting | Proposed |
| [0009](0009-one-zeitwerk-loader-per-source.md) | Give each source its own Zeitwerk loader | Proposed |
| [0010](0010-configuration-and-secrets.md) | Configure through env vars and a block; wrap secrets in a redacting type | Proposed |
