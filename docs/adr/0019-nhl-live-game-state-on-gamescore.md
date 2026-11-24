# 0019. Live NHL game state on `GameScore`, from the same `/score` request

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #19

## Context

M2-04 asks for a live game state model: period, clock, intermission, power play, shots on goal,
and the game's state (pre, live, final, overtime, shootout). M2-03 (ADR 0018) already put period,
period type, clock and intermission on `NHL::GameScore`, read from `/score/{date}`, and left shots
and game detail here.

Recordings on 2026-11-23 showed `/score` carries everything else too: per-team `sog`, and a
`situation` object (the same shape `/gamecenter/{id}/landing` has) while a game isn't five-on-five
with both goalies in. Its `situationCode` is four digits: away goalie, away skaters, home skaters,
home goalie.

## Decision

- Live state stays on `NHL::GameScore`, now schema 2, with `home_shots`, `away_shots` and
  `situation`, all read from the same `/score` game object. No new request.
- `NHL::Situation` holds the decoded `situationCode` (skaters per side, goalies in or out), the
  penalty time left and the NHL's raw labels (`PP`, `EN`). `power_play` is the side with more
  skaters while both goalies are in, so an extra attacker for a pulled goalie isn't a power play;
  `empty_net` lists sides with no goalie; `strength(side)` reads `"5v4"`.
- `GameScore#phase` sums up the state as one symbol: `:pre`, `:regulation`, `:intermission`,
  `:overtime`, `:shootout`, `:final`, or `:unknown` for codes the gem doesn't know. How a final game
  ended stays on `Game#ended_in`.

## Alternatives considered

- **A separate `GameState` model from `/gamecenter/{id}/landing`.** About 10 KB per game instead of
  one 25 to 40 KB request for the whole day, and it has a summary, but a scoreboard of seven live
  games would cost seven requests. It has the same `clock`, `periodDescriptor`, `sog` and
  `situation` fields, so a single-game reader can reuse these models later (M2-10 can decide).
- **Shots on `GameTeam`.** Where the score lives, but it would bump `Game`'s schema and every
  schedule game would carry an always-empty field, the same reason ADR 0018 kept period and clock
  off `Game`.
- **Power play from `situationDescriptions` (`PP`).** The NHL's own label, but it's optional per
  side and its vocabulary isn't documented; the code always comes. The labels are kept raw.
- **`phase` with live and final variants for overtime and shootout** (`:final_overtime`, ...).
  Fewer calls for a display, but it repeats `Game#ended_in`.

## Consequences

- Cached scoreboards from schema 1 are refetched once.
- The situation only exists while it lasts; an even-strength game has `situation: nil`.
- Fixtures: `/score/now` late on 2026-11-23 (a power play, an intermission, finals) and
  `/score/2026-11-11` (six games: overtime and shootout finals, about 95 KB). Live overtime, live
  shootout and pulled goalies are stubbed in the recorded shape.
