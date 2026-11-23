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

## Terms of use

Both are paid, personal subscriptions. Don't scrape or auto-download from either site
(M6-09 decides whether that ever changes), don't commit or share exports, and don't publish data
derived from them.
