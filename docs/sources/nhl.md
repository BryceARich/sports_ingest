# NHL

- **Module:** `sports_ingest/nhl` (M2)
- **Last verified:** 2026-11-22: every endpoint below returned 200 with the expected top-level
  keys, by hand with `curl`, during the 2026-27 regular season. The stats `skater/summary`
  call, `/standings/2026-11-22` and the stats `/team` list were also recorded as fixtures on
  2026-11-22 (`spec/fixtures/cassettes/nhl/`). `/schedule/2026-11-16`, `/schedule/2026-11-23` and
  `/club-schedule-season/TOR/20262027` were recorded on 2026-11-23.
- **Default raw-cache TTL:** 3600 seconds (`SPORTS_INGEST_TTL_NHL`); live-game calls will want far
  less (the polling helper, M2-10).

Two public hosts, neither documented by the NHL. Both sit behind Cloudflare.

## Endpoints used

### Web API: `https://api-web.nhle.com/v1`

| Path | Returns | Issue |
|---|---|---|
| `/schedule/{YYYY-MM-DD}` | the week (`gameWeek`) starting on that date | M2-02 |
| `/club-schedule-season/{TEAM}/{season}` | one team's season, e.g. `TOR/20252026` | M2-02 |
| `/score/{YYYY-MM-DD}` | that day's games with `gameState`, `clock`, `period`, `goals` | M2-03 |
| `/scoreboard/now` | lighter current-scores view across a few days | M2-03 |
| `/gamecenter/{gameId}/landing` | game summary | M2-04 |
| `/gamecenter/{gameId}/boxscore` | box score | M2-04 |
| `/gamecenter/{gameId}/play-by-play` | every event, including goals with strength and assists | M2-05 |
| `/standings/{YYYY-MM-DD}` | standings as of that date; also checks the team table's codes, names, conference and division | M2-06, M2-01 |
| `/roster/{TEAM}/{season}` | current roster by position | M2-07 |
| `/player/{playerId}/landing` | bio, career totals, last games | M2-08 |
| `/player/{playerId}/game-log/{season}/{gameType}` | game log; `gameType` 2 = regular season, 3 = playoffs | M2-08 |

### Stats REST API: `https://api.nhle.com/stats/rest/en`

| Path | Returns | Issue |
|---|---|---|
| `/skater/summary?cayenneExp=...` | skater season totals | M2-09 |
| `/goalie/summary?cayenneExp=...` | goalie season totals | M2-09 |
| `/team` | every team the NHL has had: `id`, `triCode`, `fullName`, `franchiseId`; checks the team table's IDs | M2-01 |

Filter with `cayenneExp`, e.g. `seasonId=20252026 and gameTypeId=2` (URL-encoded). Page with
`start` and `limit`, sort with `sort`; the response is `{"data": [...], "total": N}`.

Quick check:

```bash
curl -s https://api-web.nhle.com/v1/score/$(date +%F) | head -c 300
curl -s 'https://api.nhle.com/stats/rest/en/skater/summary?limit=1&cayenneExp=seasonId=20252026%20and%20gameTypeId=2'
```

## Auth

None.

## Rate limits

None published, and none hit during verification. Responses carry short CDN caching
(`Cache-Control: max-age` of roughly 10 to 20 seconds), so polling faster than that returns the
same data. Send the gem's `User-Agent` and keep request rates modest: one poll per game every few
seconds at most while live.

## Known quirks

- **`now` paths redirect.** `/standings/now`, `/roster/{TEAM}/current`, `/schedule/now` and
  `/score/now` answer `307` with a `Location` holding the concrete date or season. The HTTP client
  has to follow redirects, and the raw cache should key on the URL that was asked for.
- **Seasons are 8-digit strings** like `20252026`, not the `seasons: [2025]` convention
  (ADR 0006). Convert at the adapter edge; a season `2025` means the one starting in fall 2025.
- **Game IDs encode season and type**: `2026020359` is 2026-27 (`2026`), regular season (`02`),
  game 359.
- **Stats REST paging caps at 100 rows.** `limit` above 100, or `-1`, still returns 100 rows; read
  `total` and page with `start`.
- **Stats REST without `cayenneExp`** returns `500` (`Exception processing Agrest request`). A
  malformed `cayenneExp` returns the same message. Treat both as a request bug, not an outage.
- **The stats `/team` list keeps old teams under current tri-codes.** `UTA` is both 59 (Utah
  Hockey Club) and 68 (Utah Mammoth, the current one). Take current IDs from game or schedule
  payloads (`homeTeam.id`), or from `SportsIngest::Teams`, not by tri-code from `/team`.
- **Schedule weeks start on the date asked for.** `/schedule/{date}` returns seven days from
  that date (`gameWeek`), and `nextStartDate` is the day after the last one. Games in a week have
  no `gameDate`; the day's `date` is the game date, local to the venue (a late Pacific start falls
  on the next day in `startTimeUTC`). Club schedules carry `gameDate` on each game.
- **Scores and outcomes appear once a game starts.** `homeTeam.score` / `awayTeam.score` are
  absent before then; `gameOutcome.lastPeriodType` (`REG`, `OT`, `SO`) is there once it's final.
  `gameState` runs `FUT`, `PRE`, `LIVE` (`CRIT` late in close games), `FINAL`, then `OFF` when
  stats are official. The gem reads codes it doesn't know as `:unknown` (`:other` for
  `gameType`) and warns, rather than failing (ADR 0017).
- **2026-27 has 84 regular-season games per team** (82 before), plus preseason games, some
  split-squad (`homeSplitSquad`), in the club schedule.
- **Unknown IDs return `404`** (e.g. `/player/1/landing`); map that to `SportsIngest::NotFound`.
- **Shapes change between seasons** without notice. Re-record fixtures at the start of each
  season and update the date above.

## Terms of use

The NHL publishes no terms for these APIs. The content belongs to the NHL, and NHL.com's terms of
use (<https://www.nhl.com/info/terms-of-service>) cover the site's data. Our reading: fine for
personal, non-commercial tools at modest request rates; don't redistribute bulk data or present it
as official.
