# 0023. Wrap `NHL::Player` in `PlayerDetails` and share one stat model across skaters and goalies

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #23

## Context

M2-08 reads `/player/{id}/landing` (bio, draft, career and season totals) and
`/player/{id}/game-log/{season}/{gameType}`. The bio fields are the ones M2-07 already models as
`NHL::Player` (ADR 0022). Skaters and goalies come back from the same endpoints with different
stat keys, and season totals mix NHL rows with junior and international ones. ADR 0006 says spans
of seasons take `seasons:` or `last: N`, but the gem has no current-season helper yet.

## Decision

- `NHL::Players#fetch(id)` returns an `NHL::PlayerDetails` that **wraps** the existing
  `NHL::Player` (`player.team` is the current team, `nil` when there is none) and adds `active`,
  `draft` (`NHL::Draft` or `nil`), `career_regular_season`, `career_playoffs` and `seasons`.
- One `NHL::StatLine` model holds a span's totals for **both** skaters and goalies; stats the NHL
  doesn't send for that line are `nil`. `seasons` keeps every league; `nhl_seasons(game_type:)`
  filters to the NHL. Times on ice become integer seconds.
- `NHL::Players#game_log(id, season:, game_type: :regular)` returns `NHL::GameLogEntry` models,
  oldest first, skater and goalie stats in one model as above. With neither keyword it reads
  `/game-log/now`. It reads **one season**; spans (`seasons:` / `last:`) wait for the
  current-season helper ADR 0006 calls for.
- Details are cached under `nhl/players/<id>`, logs under
  `nhl/game_logs/<id>/<season ID>/<regular|playoffs>`; the `now` log is saved under the season it
  turned out to be.

## Alternatives considered

- **Add the landing fields to `NHL::Player` (bump its `SCHEMA_VERSION`).** Roster players would
  carry a dozen always-`nil` fields, and a roster entry would look like it had career data. A
  wrapper keeps `Player` the shared bio shape both endpoints fill.
- **Separate skater and goalie stat models.** Cleaner types, but a player's position doesn't
  always match the rows (a skater who once played goal in an emergency), the parser would need to
  pick a class per row, and consumers would branch on class. `nil` fields cost less.
- **Keep times on ice as `"mm:ss"` strings.** Faithful to the payload, but every consumer would
  parse them to add or average.
- **`game_log(id, seasons:, last:)` now.** `last:` needs to know the current season; guessing it
  from the date or from the player's own rows would be wrong around the season boundary and for
  retired players. A loop over `season:` covers spans until the helper exists.

## Consequences

- Consumers read bio through `details.player`, the same model rosters return, so the crosswalk
  (M3) has one NHL player shape to match.
- Code that sums stats has to skip `nil`s (`log.sum { it.shots.to_i }`).
- Season totals include junior and international rows; consumers wanting NHL only use
  `nhl_seasons`.
- A spans-of-seasons game-log method is still to do once the current-season helper lands.
