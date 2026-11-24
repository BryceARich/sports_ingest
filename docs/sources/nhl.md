# NHL

- **Module:** `sports_ingest/nhl` (M2)
- **Last verified:** 2026-11-22: every endpoint below returned 200 with the expected top-level
  keys, by hand with `curl`, during the 2026-27 regular season. The stats `skater/summary`
  call, `/standings/2026-11-22` and the stats `/team` list were also recorded as fixtures on
  2026-11-22 (`spec/fixtures/cassettes/nhl/`). `/schedule/2026-11-16`, `/club-schedule/TOR/week/2026-11-16`
  and `.../2026-11-23`, and `/club-schedule/TOR/month/2026-11` were recorded on 2026-11-23, and `/score/now` (redirecting
  to `/score/2026-11-23`, one game live) the evening of 2026-11-23.
- **Default raw-cache TTL:** 3600 seconds (`SPORTS_INGEST_TTL_NHL`); live-game calls will want far
  less (the polling helper, M2-10).

Two public hosts, neither documented by the NHL. Both sit behind Cloudflare.

## Endpoints used

### Web API: `https://api-web.nhle.com/v1`

| Path | Returns | Issue |
|---|---|---|
| `/schedule/{YYYY-MM-DD}` | the week (`gameWeek`) starting on that date | M2-02 |
| `/club-schedule-season/{TEAM}/{season}` | one team's season, e.g. `TOR/20252026` (~190 KB) | M2-02 |
| `/club-schedule/{TEAM}/week/{YYYY-MM-DD}` | one team's games in the 7 days from that date (~6 KB) | M2-02 |
| `/club-schedule/{TEAM}/month/{YYYY-MM}` | one team's games in that month (~26 KB) | M2-02 |
| `/score/{YYYY-MM-DD}`, `/score/now` | that day's games with `gameState`, scores, `clock`, `periodDescriptor`, `goals` (~25 to 40 KB) | M2-03 |
| `/scoreboard/now` | several days of games around today (~160 KB); not used, `/score` is lighter | — |
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
  on the next day in `startTimeUTC`). Club schedules carry `gameDate` on each game. A club
  week's `nextStartDate` jumps over the off-season (`week/2026-07-01` → `2026-09-16`), and the
  club month's `nextMonth` likewise skips empty months. `club-schedule-season` ignores query
  parameters such as `startDate`; use the week or month endpoints for less.
- **Scores and outcomes appear once a game starts.** `homeTeam.score` / `awayTeam.score` are
  absent before then; `gameOutcome.lastPeriodType` (`REG`, `OT`, `SO`) is there once it's final.
  `gameState` runs `FUT`, `PRE`, `LIVE` (`CRIT` late in close games), `FINAL`, then `OFF` when
  stats are official. The gem reads codes it doesn't know as `:unknown` (`:other` for
  `gameType`) and warns, rather than failing (ADR 0017).
- **Scores (`/score/{date}`):** each game carries `gameDate`, unlike schedule weeks. `clock`
  (`secondsRemaining`, `running`, `inIntermission`), `period` and `periodDescriptor`
  (`number`, `periodType` `REG`/`OT`/`SO`) are absent until the game starts (`FUT`, `PRE`); a final
  game keeps its last period and a `00:00` clock. A shootout is period 5 with `periodType` `SO`.
  Teams carry `sog` (shots on goal) and `goals` lists every goal with scorer and assists; the gem
  leaves both to M2-04 and M2-05. `/score/now` redirects to the NHL's current date (ET), which can
  differ from the caller's local date late at night.
- **2026-27 has 84 regular-season games per team** (82 before), plus preseason games, some
  split-squad (`homeSplitSquad`), in the club schedule.
- **Standings rows have no team ID.** Map `teamAbbrev` through `SportsIngest::Teams` (M2-06 does).
  `wildcardSequence` is `0` for a team in its division top three, and `placeName` reads
  "NY Rangers" / "NY Islanders" where `teamName` says "New York". `/standings/{date}` for an
  off-season date may come back with an empty `standings` list (unverified; `Standings` handles it).
- **Unknown IDs return `404`** (e.g. `/player/1/landing`); map that to `SportsIngest::NotFound`.
- **Rosters:** `/roster/{TEAM}/{season}` returns `forwards`, `defensemen` and `goalies`. Names and
  birth cities are localized objects (`{"default": "Jiří", "cs": ...}`); `sweaterNumber` and
  `birthStateProvince` are often missing. A team code with no roster that season (e.g.
  `ARI/20232024`) answers `200` with `{}`; an unknown code answers `404` with an HTML page.
  Recorded as `nhl/roster_edm_20252026` on 2026-11-23.
- **A past season's roster is an offseason snapshot, not everyone who played.** Checked on
  2026-11-23 against 2024-25 and 2023-24 (dates of moves are from memory, not the API):
  - **Mid-season and offseason trades:** players are listed under the team they were with at the
    snapshot. Rantanen (COL, CAR, DAL in 2024-25) is only on DAL's; Coyle and Wood, who finished
    2024-25 with COL, are on CBJ's; Dobson, traded NYI to MTL at the June 2025 draft, is on MTL's.
  - **2024-25 looks like June 30:** UFAs who left on July 1 are still on their old team (Marner on
    TOR, not VGK; Ehlers on WPG, not CAR), and 2025 draft picks aren't listed (Schaefer isn't on NYI).
  - **2023-24 differs:** Stamkos, a UFA who left TBL for NSH on July 1, 2024, is on neither roster,
    and the rosters are small (TBL 18, NSH 15 against 23 to 42 per team for 2024-25). Guentzel,
    whose rights TBL got in June 2024, is on TBL's. Whether expiring contracts are listed depends
    on the season.
  - **Who played is missing:** players traded away and most call-ups aren't listed (COL used 43
    skaters in 2024-25; its roster lists 21). For who played for a team in a season, use game logs
    or the stats REST tables (M2-08, M2-09).
- **Player landing and game logs:** `/player/{id}/landing` has the roster's bio fields (plus
  `isActive`, `currentTeamAbbrev`, `draftDetails`, missing for undrafted players), `careerTotals`
  (`regularSeason`, `playoffs`; NHL only) and `seasonTotals`, one row per season, game type and
  team in every league (junior, international), oldest first. Skater rows have `avgToi`, goalie
  rows `timeOnIce` (total, e.g. `"7578:38"`), `savePctg`, `goalsAgainstAvg`, `wins`. Game logs list
  games **newest first**; a season with no games answers `200` without a `gameLog` key. `/game-log/now`
  is the current season and game type (the playoffs while they're on). In `last5Games`, goalie rows
  say `penaltyMins`, not `pim`. Recorded as `nhl/player_8478402_*` (McDavid) and
  `nhl/player_8479361_*` (a goalie) on 2026-11-23.
- **Season stat tables:** `skater/summary` and `goalie/summary` give one row per player per
  season and game type, a traded player's teams joined in `teamAbbrevs` (`"TOR,EDM"`). Skater rows
  say `skaterFullName`, `positionCode`, `penaltyMinutes`, `ppGoals`, `shootingPct`, `faceoffWinPct`
  and `timeOnIcePerGame` (seconds, a float); goalie rows say `goalieFullName`, `goalsAgainstAverage`,
  `savePct` and `timeOnIce` (total seconds, an integer) and have no position. Without `sort` the
  order isn't stable across pages; the gem sorts by `playerId`. A regular season is ~800 to 950
  skaters (~10 pages) and ~100 goalies (1 to 2 pages). `cayenneExp` also takes ranges
  (`seasonId>=20242025 and seasonId<=20252026`), unused. Recorded as `nhl/stats_goalie_summary_2022_to_2026_regular`
  and `nhl/stats_skater_summary_2025_playoffs` on 2026-11-23.
- **Shapes change between seasons** without notice. Re-record fixtures at the start of each
  season and update the date above.

## Terms of use

The NHL publishes no terms for these APIs. The content belongs to the NHL, and NHL.com's terms of
use (<https://www.nhl.com/info/terms-of-service>) cover the site's data. Our reading: fine for
personal, non-commercial tools at modest request rates; don't redistribute bulk data or present it
as official.
