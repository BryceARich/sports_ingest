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
| EH skater GAR table | `SkaterGarImport` | M6-01 |
| EH goalie GAR table | goalie GAR import | M6-02 |
| EH GAR projections | projections import | M6-03 |
| PuckPedia cap hits (CSV) | contract import | M6-04 |

Each importer adds its export's columns, file naming and an example row (invented values) here.

### EH skater GAR

Save EH's skater GAR table, or a spreadsheet tab holding it (such as `GAR_25-26`), as CSV. Any file
name works. Columns are matched by name (ADR 0044), so their order and any extra columns don't
matter. The required columns, from the issue (not yet checked against a real export):

```csv
Player,Season,Team,Position,GP,TOI_All,EVO_GAR,EVD_GAR,PPO_GAR,SHD_GAR,Take_GAR,Draw_GAR,Off_GAR,Def_GAR,Pens_GAR,GAR,WAR,SPAR
Avery Testwood,25-26,VAN/MIN,C,82,1612.4,9.8,1.2,3.1,0.4,-0.6,1.1,12.9,1.6,0.5,15.0,2.7,5.3
```

## Auth

Each site's own login, used only by the person exporting. The gem never signs in.

## Rate limits

Not applicable.

## Known quirks

- Add per-export quirks here as the M6 importers find them (encodings, helper rows, older formats).
- **Traded players** get one combined row with a team cell such as `VAN/MIN`; it reads as
  `teams: ["VAN", "MIN"]` (ADR 0044).
- **Seasons** are spelled `25-26`; they read as the start year, `2025` (ADR 0006).
- **Missing values** are `NA` (EH is built in R); they read as `nil`, as do blanks and `-`.
- **Spreadsheet exports** may add a byte-order mark and trailing all-blank rows; both are ignored.

## Terms of use

Both are paid, personal subscriptions. Don't scrape or auto-download from either site
(M6-09 decides whether that ever changes), don't commit or share exports, and don't publish data
derived from them.
