# Source notes

One file per data source: how to use it (the usage examples moved out of the README, M1-14), what
we call, how we authenticate, the limits and quirks we've hit, the terms we read, and **the date it
was last verified working**. The APIs here are mostly undocumented,
so these notes are the only record of what we rely on (ADR 0015).

| Source | Note | Module | Last verified |
|---|---|---|---|
| NHL web API and stats REST API | [nhl.md](nhl.md) | `sports_ingest/nhl` | 2026-11-22 |
| ESPN Fantasy (read-only) | [espn.md](espn.md) | `sports_ingest/espn` | 2026-11-22 (public endpoints only) |
| nflverse data releases | [nflverse.md](nflverse.md) | `sports_ingest/nflverse` | 2026-11-22 |
| Evolving-Hockey and PuckPedia (licensed exports) | [advanced_hockey.md](advanced_hockey.md) | `sports_ingest/advanced_hockey` | not yet (M6) |

## Keeping them current

- **Every adapter issue adds to its source's note**: the endpoints or file columns it uses, and
  anything surprising it ran into. A new source starts with a note before any code
  ([ARCHITECTURE.md](../ARCHITECTURE.md#how-to-add-a-new-source)).
- **Update "Last verified"** (in the note and in the table above) whenever you check the source
  against the live service: re-recording fixtures, or a manual check like the `curl` lines in each
  note. Say what you checked; a date with no scope is no use when something breaks.
- A new note also goes in `.yardopts`, by name (a glob would pick up this README, whose page
  would replace the main README in the generated docs).
- When a source changes shape, record the old and new shape and the date under "Known quirks", then
  raise `SourceChangedError` in the adapter (ADR 0012) rather than guessing.
- Terms notes are our reading, not legal advice. Link the terms themselves and quote nothing long.

## Template

```markdown
# <Source>

- **Module:** `sports_ingest/<source>`
- **Last verified:** YYYY-MM-DD: what was checked, and how
- **Default raw-cache TTL:** N seconds (`SPORTS_INGEST_TTL_<SOURCE>`)

## Usage
## Endpoints used
## Auth
## Rate limits
## Known quirks
## Terms of use
```
