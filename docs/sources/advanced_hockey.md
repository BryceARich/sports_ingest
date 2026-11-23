# Evolving-Hockey and PuckPedia

- **Module:** `sports_ingest/advanced_hockey` (M6)
- **Last verified:** not yet; the M6 importers verify their column layouts and update this line.
- **Default raw-cache TTL:** none; these are local files, not HTTP.

**Licensed data.** Both subscriptions are licensed to the maintainer personally. Exports, and
anything derived from them, **never enter git** (ADR 0005, ADR 0014). Fixtures use the real column
layouts with invented values, under `spec/fixtures/advanced_hockey/`.

## Endpoints used

None. Input is files the user exports by hand and drops into a local folder outside the repo.

| Export | Importer | Issue |
|---|---|---|
| EH skater GAR table | skater GAR import | M6-01 |
| EH goalie GAR table | goalie GAR import | M6-02 |
| EH GAR projections | projections import | M6-03 |
| PuckPedia cap hits (CSV) | contract import | M6-04 |

Each importer adds its export's columns, file naming and an example row (invented values) here.

## Auth

Each site's own login, used only by the person exporting. The gem never signs in.

## Rate limits

Not applicable.

## Known quirks

- Add per-export quirks here as the M6 importers find them (encodings, helper rows, multi-team
  values such as `VAN/MIN`, older formats).

## PuckPedia cap hits (M6-04)

Verified 2026-11-22 against the 2026 export (773 player rows). Read with
`AdvancedHockey::PuckPedia.contracts(path)`; layouts and detection are in ADR 0047.

- **File:** a CSV saved from the maintainer's sheet, e.g. `GAR League Prep 2026 - 2026-CAPHIT.csv`.
  UTF-8 (accented names), CRLF line endings.
- **Columns read (`cap_hit_2026`):** `Player`, `Age`, `Pos`, `Status`, `Length`, `Cap Hit`,
  `Start Year`, `Expiry Year`, `Expiry Status`, `Signing Agent`, `Signing GM`. Every other column
  (an unnamed rank column, `Reordered Name`, stats, GAR) is ignored.
- **Example row (invented):**
  `1,"Testerson, Alpha",Alpha Testerson,24,C,YR 1 OF 5,5.00,9100000,2026-27,2030-31,UFA,Invented Agency,Pretend GM,...`
- **Quirks:** a helper row with a blank `Player` sits under the header and is skipped. `Player` is
  "Last, First". `Length` is a decimal ("5.00"). `Pos` is `C`/`L`/`R`/`D`/`G` (wingers as `L`/`R`).
  `Expiry Status` values seen: `UFA`, `RFA`, `RFA+ARB`, `UFA-Group6`. `Signing Agent` can be blank.
- **Older layout (2025, CapFriendly):** `Current Cap Hit`, `Contract Length`, `UFA Year`
  ("Yr 2 of 4"), `Expiry Yr`, `Clause`, `Signing Status`, an `averages` row under the header. Not
  parsed yet; it fails detection with a `SourceChangedError` listing the missing 2026 columns.

## Terms of use

Both are paid, personal subscriptions. Don't scrape or auto-download from either site
(M6-09 decides whether that ever changes), don't commit or share exports, and don't publish data
derived from them.
