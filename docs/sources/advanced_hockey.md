# Evolving-Hockey and PuckPedia

- **Module:** `sports_ingest/advanced_hockey` (M6)
- **Last verified:** 2026-11-23, skater GAR (both groupings, 2026-27 regular season). Goalie GAR,
  projections and PuckPedia: not yet; their importers update this line.
- **Default raw-cache TTL:** none; these are local files, not HTTP.

**Licensed data.** Both subscriptions are licensed to the maintainer personally. Exports, and
anything derived from them, **never enter git** (ADR 0005, ADR 0014). Fixtures use the real column
layouts with invented values, under `spec/fixtures/advanced_hockey/`.

## Usage

### Evolving-Hockey skater GAR

Download EH's skater GAR table as CSV (`EH_gar_sk_stats_regular_<date>.csv`) into a folder
**outside the repo**. EH groups it by season or by team and season; both import the same way:

```ruby
require "sports_ingest/advanced_hockey"
include SportsIngest::AdvancedHockey

rows = SkaterGarImport.read("~/hockey/EH_gar_sk_stats_regular_2026-11-23.csv")
rows.first.season # => 2026 (the 26-27 season, named by its start year)
rows.first.teams  # => ["N.J", "WPG"] for a traded player, grouped by season
rows.first.war    # => 0.9

SkaterGar.combine(rows) # one row per player and season, whichever grouping you exported
```

To see which players didn't match a canonical ID, pass a matcher built from known players (usually
NHL rosters). `report` prints the rows that need a look and returns the full report (ADR 0030):

```ruby
matcher = SportsIngest::Identity::Matcher.new(SportsIngest::NHL::Rosters.new.fetch("VAN"))
report = SkaterGarImport.report("~/hockey/EH_gar_sk_stats_regular_2026-11-23.csv", matcher: matcher)
File.write("unmatched.csv", report.to_csv) # the same rows as CSV
```

Grouped by team, a traded player has a row per team, but EH drops short stints from that view, so
use the season grouping for exact totals. Columns are matched by name (`EVO_GAR` or `EVO GAR`), so
a spreadsheet tab saved as CSV works too; a missing column raises
`SportsIngest::SourceChangedError` listing the columns it found.

## Endpoints used

None. Input is files the user exports by hand and drops into a local folder outside the repo.

| Export | Importer | Issue |
|---|---|---|
| EH skater GAR table | `SkaterGarImport` | M6-01 |
| EH goalie GAR table | goalie GAR import | M6-02 |
| EH GAR projections | `ProjectionGarImport` | M6-03 |
| PuckPedia cap hits (CSV) | contract import | M6-04 |

Each importer adds its export's columns, file naming and an example row (invented values) here.

### EH skater GAR

EH's download is named `EH_gar_sk_stats_regular_<date>.csv`: UTF-8 with accented names, no
byte-order mark, text quoted and numbers bare, one header row. EH offers it **grouped by season**
or **by team and season**, with identical columns; `SkaterGarImport` reads both. A spreadsheet
tab saved as CSV works too, since columns are matched by name (ADR 0044). Invented example, grouped
by season:

```csv
"Player","Season","Team","Position","GP","TOI_All","EVO_GAR","EVD_GAR","PPO_GAR","SHD_GAR","Take_GAR","Draw_GAR","Off_GAR","Def_GAR","Pens_GAR","GAR","WAR","SPAR"
"Avery Testwood","26-27","N.J/WPG","C",22,355.7,3.5,-0.7,1.4,0.1,0.1,0.2,4.9,-0.6,0.3,4.6,0.9,1.5
```

Grouped by team and season, the same player has a row for `N.J` and one for `WPG`.

## Auth

Each site's own login, used only by the person exporting. The gem never signs in.

## Rate limits

Not applicable.

## Known quirks

- Add per-export quirks here as the M6 importers find them (encodings, helper rows, older formats).
- **Traded players**, grouped by season, get one row with a team cell such as `N.J/WPG`; it reads
  as `teams: ["N.J", "WPG"]`. Grouped by team, they get a row per team instead.
- **The team grouping drops short stints** (a few games or minutes with one team), and sometimes
  a traded player entirely. Each row is also rounded to one decimal, so team rows summed with
  `SkaterGar.combine` can be 0.1 off the season row. Use the season grouping for totals.
- **Team abbreviations are EH's**, with dots where the NHL uses three letters: `N.J`, `L.A`, `S.J`,
  `T.B`. The matcher (M6-06) maps them.
- **Same-named players** are told apart in the name itself: `Elias Pettersson` (C) and
  `Elias Pettersson (D)`. Strip the suffix before name matching, and keep it as a hint.
- **Seasons** are spelled `26-27`; they read as the start year, `2026` (ADR 0006).
- **Missing values**: none in the 2026-11-23 exports. `NA` (EH is built in R), blanks and `-`
  read as `nil`.
- **Spreadsheet tabs** saved as CSV may add a byte-order mark and trailing all-blank rows; both
  are ignored.
- **GAR projections** (`ProjectionGarImport`): the tab's signs are part of its header names. `GAR-`
  and `GAR+` are the low and high ends of GAR; `GAR/60-` and `GAR/60+` do the same for GAR/60;
  `GAR Unc` is the uncertainty. Those headers are aliased, because normalizing them by name would
  collapse the signs into duplicate columns.

## Terms of use

Both are paid, personal subscriptions. Don't scrape or auto-download from either site
(M6-09 decides whether that ever changes), don't commit or share exports, and don't publish data
derived from them.
