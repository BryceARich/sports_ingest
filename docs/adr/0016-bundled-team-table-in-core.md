# 0016. Ship the team table as Ruby data in core, with per-source codes

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #16

## Context

Every source names teams its own way. The NHL uses tri-codes (`TBL`, `NJD`, `LAK`, `SJS`, `UTA`),
Evolving-Hockey dotted codes (`T.B`, `N.J`, `L.A`, `S.J`), ESPN short codes (`TB`, `NJ`, `LA`,
`SJ`, `UTAH`) and numeric `proTeamId`s. Models from every source need to point at the same team,
and the NHL, ESPN and advanced-hockey modules load separately
([ADR 0009](0009-one-zeitwerk-loader-per-source.md)), so none of them can own the mapping.

The NHL APIs have team IDs, tri-codes, names, conferences and divisions, spread over two hosts
(`/standings` and `stats/rest/en/team`), but no colors and no other sources' codes. The stats team
list also keeps old rows: `UTA` appears as both 59 (Utah Hockey Club) and 68 (Utah Mammoth).
Teams change rarely: a relocation or rename every few years.

## Decision

We will ship the table with the gem as Ruby data, `SportsIngest::Teams::Hockey::ROWS` (one hash per team), and
read it through `SportsIngest::Teams` in core, which every source can use.

- Each row becomes a `SportsIngest::Team` model: the NHL team ID (a String, as in
  [ADR 0026](0026-canonical-id-scheme.md)) and tri-code, full, place and common names,
  conference, division, primary and secondary colors (`#RRGGBB`), `source_ids` (ESPN's team ID,
  which is the fantasy API's `proTeamId`) and `codes` per source (`:evolving_hockey`,
  `:puckpedia`, `:espn`). The NHL's ID and tri-code are filled in as the `:nhl` entries.
- `Teams.find(code, source: nil)` matches loosely (case, spaces, punctuation and accents ignored,
  so `T.B`, `TB` and `tb` are one key) against any source's codes and the full name, or only one
  source's codes when `source:` is given. `Teams.fetch` raises `NotFound` instead of returning
  `nil`. `Teams.find_by_source_id(:espn, 20)` looks up by ID.
- Building the index raises if two teams share a normalized code, name or ID, so a bad edit fails
  loudly instead of resolving to whichever team comes first.
- Specs check the table against recorded NHL responses (standings for codes, names, conferences
  and divisions; the stats team list for IDs). Re-record them when a team moves or is renamed.

Only the 32 current teams are in the table. Historical teams (`ARI`, `PHX`, `ATL`, ...) aren't,
so older seasons' codes don't resolve yet.

## Alternatives considered

- **Fetch the table from the NHL at runtime.** Always current, but two requests for data that
  changes every few years, no colors or other sources' codes, a network dependency for a lookup
  every adapter needs, and the duplicate `UTA` rows to filter out. The recorded-response specs
  give most of the freshness check without the cost.
- **Put the table in `SportsIngest::NHL`.** It's NHL data, but ESPN and advanced-hockey code
  would then have to load the NHL module, which ADR 0009 forbids.
- **A JSON file instead of a Ruby constant.** Easier for other languages to read, but
  `script/licensed-data-guard` scans data files (`.json` among them) for the words
  "Evolving-Hockey" and "PuckPedia", which the table's source keys contain. Ruby code is exempt by
  design, so a constant keeps the guard strict without an allow-list entry for the gem's own code.
- **Strict, exact code matching.** Simpler, but every source would need each spelling listed
  (`T.B`, `TB`, `t.b`). Normalizing collapses those, and the collision check keeps it safe.
- **Include historical teams now.** Useful for old EH seasons, but it needs a validity range per
  code (`ARI` until 2024) and isn't part of this issue's 32-team scope.

## Consequences

- Any source can resolve a team code with `SportsIngest::Teams.fetch(code)`, without loading
  another source.
- When a team relocates or is renamed, someone edits that team's row in `lib/sports_ingest/teams/hockey.rb` and re-records the two NHL
  cassettes; the specs fail until both agree.
- PuckPedia's codes are recorded as the NHL tri-codes. The current PuckPedia export has no team
  column, so this is unverified; the PuckPedia importer should confirm it.
- Colors are for display, not an official source; they come from the teams' published brand
  colors.
- Historical team codes need a follow-up if old seasons are imported.
