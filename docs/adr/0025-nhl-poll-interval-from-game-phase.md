# 0025. Recommend an NHL poll interval from the game's phase

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #25

## Context

M2-10 asks for a helper that says how soon to read a game again: about 60 seconds before the
puck drops, 5 to 10 seconds while play is live, 30 between periods, and no more reads once the
game is final. M2-04 (ADR 0019) already gives `NHL::GameScore#phase` as the one symbol that sums
up that state, and the NHL's `/score` request reads a whole day at once (~250 KB on a 14-game
day), so the interval has to be chosen per game and then shared across the games a caller holds.

## Decision

- `NHL::PollInterval` maps a phase to seconds. `PollInterval.for(score)` takes a `GameScore`;
  `PollInterval.for_phase(phase)` takes the symbol directly.
- The table: `:pre` 60, `:regulation`, `:overtime` and `:shootout` 10, `:intermission` 30,
  `:final` `nil` (stop), `:unknown` 60. Unknown states poll at the slow pre-game rate, so a
  game the gem doesn't understand is still read, just not often.
- The helper only recommends a wait. It doesn't sleep, fetch or keep a timer. The caller owns
  the loop, so it works with the raw cache's TTL and with a Raspberry Pi's scheduler alike.

## Alternatives considered

- **A poll loop in the gem** (`NHL.watch(date) { ... }`). It would own sleeping and threads,
  which the core gem avoids and the consumers may already have, so it stays out of scope.
- **Five seconds while live.** The NHL's CDN serves an unchanged clock for a stopped game
  across calls a minute apart, so 10 seconds is enough for the score and clock to look live
  and halves the requests on a Pi. The table is one constant, so a later change is one line.
- **A per-game interval from `/gamecenter/{id}/landing`.** A single-game poll could use the
  same phase, but the interval depends only on the phase, so it doesn't need a second request.
