# 0018. Read NHL scores from `/score/{date}` into `NHL::GameScore`, wrapping `Game`

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #18

## Context

M2-03 asks for one lightweight call, suited to a Raspberry Pi, that returns all of today's games
with scores and state. The NHL web API has three candidates:

- `/score/{date}` (and `/score/now`, a redirect to the NHL's current date): one day's games with
  state, scores, shots, period, clock and every goal. About 25 KB for seven games, 40 KB for five
  finished ones.
- `/scoreboard/now`: several days around today, about 160 KB.
- `/schedule/{date}` (M2-02, ADR 0017): a whole week, about 100 KB, with scores but no period or
  clock.

ADR 0017 left live detail to M2-03 and M2-04, saying they could reuse `Game` and `GameTeam` or bump
their schema. "Today" also needs a definition: a Pi on Pacific time after 9 p.m. is already on the
next UTC day, and its local date can disagree with the NHL's.

## Decision

- `NHL::Scoreboard#on(date = nil)` reads `/score/{date}`; with no date it reads `/score/now` and lets
  the NHL pick the day. `NHL.scores(date: nil)` calls it.
- It returns `NHL::GameScore` models (schema 1): the schedule's `Game`, unchanged, plus `period`,
  `period_type` (`:regulation` / `:overtime` / `:shootout` / `:unknown`, from the same map as
  `Game#ended_in`), `seconds_remaining`, `clock_running`, `in_intermission`, and `codes` with the raw
  period type. These are `nil` before a game starts. `GameScore` delegates `id`, `home_team`,
  `away_team`, `state`, `live?` and `final?` to the game and adds `clock` (`"MM:SS"`).
- The schedule's game parsing moves to `Game.parse` (private API), so both adapters build games
  the same way, with the same unknown-code warnings (ADR 0017).
- The default client for `Scoreboard` keeps raw-cache entries fresh for 30 seconds
  (`Scoreboard::TTL`), about the CDN's own caching, instead of the hour the `:nhl` TTL gives
  schedules. `NHL::Client.new` gains `ttl:` for this. Callers can pass their own client.
- Shots on goal and the goals list are left out; game detail is M2-04 and goals M2-05.

## Alternatives considered

- **`/scoreboard/now`.** One call for a few days, but six times the bytes for what M2-03 needs, a
  poor fit for a Pi polling during games.
- **Add period and clock to `Game` (schema 2).** One model instead of two, but every schedule game
  would carry fields that are always empty there, and cached schedules would go stale on the bump.
- **Today as the caller's local date.** Predictable, but late on the West Coast it asks for
  tomorrow's (empty) games; the NHL's own date matches what NHL.com shows.
- **Keep the `:nhl` TTL.** Simpler, but a scoreboard an hour old isn't a scoreboard. The polling
  helper (M2-10) may still tune this per game state.

## Consequences

- A scoreboard costs one request per call, at most one every 30 seconds per process with the raw
  cache on.
- `GameScore` nests a full `Game`, so a processed-cache entry repeats the schedule's fields; a
  scoreboard is small, so that's fine.
- An unknown period type warns as an unknown `ended_in` code (the same map) and reads `:unknown`.
- The spec cassette is one recorded `/score/now` (redirect plus one day, one game live, about
  55 KB); edge cases (shootouts, intermissions, unknown codes) use stubbed payloads.
