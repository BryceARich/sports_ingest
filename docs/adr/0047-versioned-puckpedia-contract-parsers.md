# 0047. Read PuckPedia exports with one parser per layout, picked by header

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #47

## Context

Contracts come from cap-hit CSVs the maintainer exports by hand (ADR 0005). The layout changes
between years: the 2025 file (CapFriendly's old format) has `Current Cap Hit`, `Contract Length`,
`UFA Year` ("Yr 2 of 4"), `Expiry Yr`, `Clause`; the 2026 PuckPedia file has `Cap Hit`, `Length`,
`Status` ("YR 1 OF 5"), `Expiry Year`, `Signing Agent`, `Signing GM`. We want the current file now
and older ones later for history. The files are sheets the maintainer also adds stat columns to,
so they carry many columns the importer doesn't own.

Ruby 4.0 ships `csv` as a bundled gem, not a default gem, so `require "csv"` fails under Bundler
unless the gemspec lists it.

## Decision

We will give each export layout its own parser module under `AdvancedHockey::PuckPedia`
(`CapHit2026` first), registered newest first in `PuckPedia::FORMATS`. `PuckPedia.contracts(path)`
reads the header row and uses the first parser whose required columns are all present; callers
can force one with `format: :cap_hit_2026`. A parser reads only its columns and ignores the rest.
Every parser builds the same `Contract` model, so consumers never see the layout.

Parsers check values strictly and raise `SourceChangedError` with the file and line (a status that
isn't "YR n OF m", a length that disagrees with the seasons) rather than returning partial data.

We add `csv` (`~> 3.3`, pure Ruby) as a runtime dependency. It is required only by the
autoloaded importer file, so `require "sports_ingest/advanced_hockey"` still loads no CSV.

## Alternatives considered

- **One parser with a column-alias table.** Less code while layouts only rename columns, but the
  2025 and 2026 files also differ in meaning (status text, clause and team columns, a summary row),
  which turns the alias table into conditionals.
- **Choose the parser by file name or a required `format:`.** Simple, but file names are whatever
  the sheet export produces, and making the caller name the layout pushes the problem onto every
  consumer. Detection by header still allows `format:` as an override.
- **Parse CSV by hand to avoid the dependency.** Quoted names ("Last, First") and multi-line
  cells make that a real parser to maintain; `csv` is pure Ruby and installs on a Pi.

## Consequences

- Adding the 2025 layout is a new `PuckPedia::CapHit2025` module plus a `FORMATS` entry; nothing
  else changes.
- Detection order matters if two layouts ever share all required columns; keep `FORMATS` newest
  first and make each parser's columns specific.
- Strict checks mean a sheet edit (a stray value in `Status`) stops the import with a line number
  instead of silently dropping a player.
- EH importers (M6-01 to M6-03) can use the same `csv` dependency.
