# 0030. Report unmatched and low-confidence records after an import, as console text and CSV

- **Status:** Proposed
- **Date:** 2026-11-24
- **Issue:** #30

## Context

The tiered matcher ([ADR 0028](0028-tiered-player-matcher.md)) leaves some source records
unmatched (`:no_match`), ambiguous (`:ambiguous`) or matched only on a unique name (`:low`).
Nothing shows those to a person yet, so a wrong or missing player would stay hidden until stats
looked off. An import needs a list of what it couldn't resolve, with the players each record
could be, so the maintainer can fix the overrides (M3-04) or the source data.

## Decision

`SportsIngest::Identity::UnmatchedReport.build(matcher, records)` matches each record (a hash of
`Matcher#match` arguments plus `source:`) and keeps every result. Its `review` is the rows whose
confidence is `:low` or `:none`, including ambiguous and unmatched rows. The report has two
outputs:

- `#to_text`: a summary line, then one line per reviewed row with the match or the candidates.
  Printed to the console.
- `#to_csv`: the reviewed rows with a header (`source,name,id,position,team,confidence,reason,
  detail,candidates`), written by the caller.

The Evolving-Hockey skater GAR import gets `SkaterGarImport.report(path, matcher:, io:)`. It
combines the rows per player and season, matches each on name, position and, when the row lists
exactly one team, that team. A traded player's row lists several teams, so it's matched without a
team (tier 3 is skipped, tiers 2 and 4 still apply). The matcher is built by the caller from known
players (usually NHL rosters); the import never fetches anything.

Candidates are the same-name-key players, as canonical `hockey:<id>` keys. A fuzzy lookup for
suggestions is out of scope ([ADR 0028](0028-tiered-player-matcher.md) keeps fuzzy matching out
of the matcher).

## Alternatives considered

- **Return the report as CSV only.** A file nobody opens after an import. Console text shows the
  problems where the import runs; the CSV is for working through them.
- **Print every row, matched or not.** Hides the handful that need attention among hundreds of
  clean matches. The summary line still gives the totals.
- **Put the report inside each import (one copy per source).** Would repeat the formatting for
  every source. One class takes any records, so the next import reuses it.
- **Match a traded player on the first team.** EH doesn't say which team is current, so a wrong
  team could push a correct match into the wrong tier. Dropping the team only skips tier 3.

## Consequences

- Every import with a matcher can show its unresolved rows; the EH import is the first to do so.
- The report doesn't store anything: it's built from one run, so a re-run after an override
  (M3-04) shows the current state.
- `:low` rows are listed for review even though they matched. That's deliberate: tier 4 trusts that
  the known pool is complete (ADR 0028).
