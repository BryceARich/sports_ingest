# Architecture decision records

Each file records one decision that had real alternatives: the context, what we chose, what we
didn't, and what follows. See [`../ARCHITECTURE.md`](../ARCHITECTURE.md) for how the pieces fit.

## Writing one

1. Copy [`0000-template.md`](0000-template.md) to `NNNN-short-title.md`, using the next free number.
2. Fill it in. Start with status **Proposed**; change it to **Accepted** when the PR merges.
3. Add a row to the index below.
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
