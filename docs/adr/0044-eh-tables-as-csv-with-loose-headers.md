# 0044. Import Evolving-Hockey tables from CSV, matching columns by name

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #44

## Context

Evolving-Hockey tables (skater GAR now; goalie GAR and GAR projections next, M6-02 and M6-03)
arrive as files the maintainer exports by hand ([ADR 0005](0005-licensed-data-never-committed.md)).
They are often kept as tabs of a spreadsheet (for example `GAR_25-26`), so a file may be EH's own
CSV or a spreadsheet tab saved as CSV. Column order, header spelling (`EVO_GAR` against
`EVO GAR`), extra columns, trailing blank rows and a byte-order mark can all differ between the
two. A season is spelled `25-26` in EH tables, while the gem names seasons by start year
([ADR 0006](0006-seasons-and-last-n-convention.md)). Players traded mid-season have a combined row
with a team cell such as `VAN/MIN`.

## Decision

We will:

- Read **CSV only**, with Ruby's `csv` gem (pure Ruby; a bundled gem since Ruby 3.4, so a gemspec
  dependency). It is required only by `lib/sports_ingest/advanced_hockey/`, through Zeitwerk, so
  no other source and not even `require "sports_ingest/advanced_hockey"` loads it until an import
  runs.
- Match columns **by normalized name** (lowercase, runs of other characters become `_`), ignore
  extra columns, skip all-blank rows and drop a byte-order mark. A missing column, or a cell that
  doesn't fit its column, raises `SourceChangedError` naming the line and column; malformed CSV
  raises `ParseError`. Blank, `NA` and `-` cells in numeric columns read as `nil`.
- Read seasons into their **start year** (`25-26`, `2025-26`, `2025-2026`, `20252026` → `2025`).
- Keep multi-team cells as **one row with `teams: ["VAN", "MIN"]`**, in export order, because EH
  reports one combined row per player-season and splitting it would invent per-team numbers.

The shared pieces (`CsvTable`, `TableRow`) are reused by the goalie and projection imports.

## Alternatives considered

- **Read `.xlsx` directly.** Saves one export step, but needs a zip and XML parser (`roo` or
  `rubyXL` and their dependencies), whose install on the Raspberry Pi isn't proven, for a format
  every spreadsheet can save as CSV anyway.
- **Match columns by position.** Simpler, but a reordered or extra column would silently shift
  every value into the wrong field.
- **Keep `Team` as the raw string.** Pushes the `/` splitting to every consumer and the matcher
  (M6-06).
- **Fail on `NA` or blank numbers.** EH is built in R and exports `NA` for missing values; one
  missing component shouldn't drop a whole table.

## Consequences

- The maintainer saves the tab as CSV before importing; the README says so.
- Header spellings EH might change (a renamed component) surface as `SourceChangedError` with
  the columns found, not as wrong numbers.
- Two-digit seasons are read as 20xx, which holds for every season EH publishes.
