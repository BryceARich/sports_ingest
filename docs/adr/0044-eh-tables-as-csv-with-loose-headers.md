# 0044. Import Evolving-Hockey tables from CSV, matching columns by name

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #44

## Context

Evolving-Hockey tables (skater GAR now; goalie GAR and GAR projections next, M6-02 and M6-03)
arrive as files the maintainer exports by hand ([ADR 0005](0005-licensed-data-never-committed.md)).
The usual input is EH's own CSV download (`EH_gar_sk_stats_regular_<date>.csv`), but a table may
also come from a spreadsheet tab saved as CSV (for example `GAR_25-26`), where column order, header
spelling (`EVO_GAR` against `EVO GAR`), extra columns, trailing blank rows and a byte-order mark can
differ. A season is spelled `26-27` in EH tables, while the gem names seasons by start year
([ADR 0006](0006-seasons-and-last-n-convention.md)).

EH offers the skater table **grouped by season** or **by team and season**, with the same columns.
Grouped by season, a traded player has one row with a team cell such as `N.J/WPG`. Grouped by team
and season, they have a row per team, but EH leaves out short stints there, so those rows don't
always add up to the season row; the parts are also rounded to one decimal before any sum.
Checked against both groupings of a 2026-27 export on 2026-11-23: summing the team rows matched the
season row for 691 of 699 players, was 0.1 off for 5, and missed a stint (a team and its games) for
3; one traded player had no team row at all. Consumers may want either view.

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
- Import **either grouping with the same importer and model**: one `SkaterGar` per row, as
  exported. A multi-team cell becomes `teams: ["N.J", "WPG"]`, in export order; splitting it into
  per-team rows would invent numbers. Team abbreviations stay EH's (`N.J`, `L.A`, `S.J`, `T.B`);
  mapping them to NHL codes belongs with the matcher (M6-06).
- Offer **`SkaterGar.combine(rows)`** to turn team-grouped rows into one row per player and season
  (teams joined, counting fields summed). It returns season-grouped rows unchanged, so callers
  don't need to know which grouping a file had. Its docs say when it can fall short, and to import
  the season grouping when totals matter.

The shared pieces (`CsvTable`, `TableRow`) are reused by the goalie and projection imports.

## Alternatives considered

- **Read `.xlsx` directly.** Saves one export step, but needs a zip and XML parser (`roo` or
  `rubyXL` and their dependencies), whose install on the Raspberry Pi isn't proven, for a format
  every spreadsheet can save as CSV anyway.
- **Match columns by position.** Simpler, but a reordered or extra column would silently shift
  every value into the wrong field.
- **Detect the grouping and tag each row with it.** A file only shows its grouping when someone
  was traded, so the tag would be unreliable early in a season; `combine` works on both anyway.
- **A separate model or importer per grouping.** The columns are identical, so this would double
  the code for no gain.
- **Keep `Team` as the raw string.** Pushes the `/` splitting to every consumer and the matcher
  (M6-06).
- **Fail on `NA` or blank numbers.** EH is built in R and exports `NA` for missing values; one
  missing component shouldn't drop a whole table.

## Consequences

- EH's CSV download imports as is; a spreadsheet tab has to be saved as CSV first.
- Per-team views come only from the team grouping; exact season totals only from the season
  grouping. Consumers that need both import both files.
- Header spellings EH might change (a renamed component) surface as `SourceChangedError` with
  the columns found, not as wrong numbers.
- Two-digit seasons are read as 20xx, which holds for every season EH publishes.
