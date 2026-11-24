# 0020. NHL goal events from the play-by-play, with a diff keyed on `eventId`

- **Status:** Proposed
- **Date:** 2026-11-24
- **Issue:** #20

## Context

M2-05 asks for goal events (scorer, assists, strength, time) and a helper that reports the events
new since the last poll. ADR 0019 noted that play-by-play events carry the same `situationCode` as
`/score`, so strength can reuse `NHL::Situation`. The play-by-play is `/gamecenter/{id}/play-by-play`,
one request for the whole game: every event in order, with a stable `eventId`, a `periodDescriptor`,
`timeInPeriod`, and on goals a `details` object (scorer, assists, shot type, score after the goal,
and the event owner's team ID).

Two questions had real alternatives: what counts as a goal, and how a poll finds the new one.

## Decision

- **`NHL::Goal`** is one goal: `event_id`, `game_id`, `period`, `time_in_period`, `time_remaining`,
  `side` (`:home`/`:away`), `team_id`, `scorer_id`, `assist_ids` (up to two), `strength`,
  `situation` (a `Situation` from the goal's own `situationCode`), `shot_type`, and the score after it.
- **`NHL::GoalEvents`** fetches the play-by-play and keeps only `typeDescKey == "goal"` plays.
  `fetch(game_id)` makes the request; `parse(payload)` maps a payload, so tests and callers with a
  saved payload skip the network.
- **Strength** is read from the goal's own situation, from the scoring side's point of view.
  `EN` when the other side's goalie is out. Otherwise the scoring side's skaters against the other
  side's: `PP` when more, `SH` when fewer, `EV` when equal.
- **Shootout attempts are not goals.** The play-by-play marks them with period type `SO`; the gem
  leaves them out, because they don't count for scoring or stats. A shootout result stays on
  `Game#ended_in`.
- **The diff is `GoalEvents.new_since(previous, current)`**, matched on `eventId`, and returned in
  `current`'s order. Plays are append-only in the NHL's order, so the new goals are the ones with an
  unseen ID. `NHL.new_goals(previous:, current:)` is the public name.
- **Polling freshness:** `GoalEvents.new` with no client keeps entries fresh for
  `Scoreboard::TTL` (30 seconds), the same as the scoreboard, instead of the schedule TTL, so a
  poll sees new plays.

## Alternatives considered

- **Diff on the goal count, or the score.** Simpler, but a count can't say which goal is new, and a
  score can't tell a goal that was taken back. An `eventId` is stable for the game and says which
  event is new.
- **Diff on `sortOrder`.** It orders the plays, but `eventId` is the identifier the payload uses
  for an event elsewhere (the `pptReplayUrl` of a goal ends in `ev<eventId>`), so it's the key.
- **Include shootout goals with a `:shootout` period type.** It would keep every "goal" event, but a
  shootout attempt has no assists, its strength is meaningless, and stats and standings don't count
  it. A consumer that wants shootouts can add them later from `plays` with the same parser.
- **Return every play, not just goals.** The issue asks for goal events; penalties and shots are
  out of scope and would need their own models. Keeping the `Goal` model to goals keeps it small.
- **Strength from `situationDescriptions` (`PP`, `EN`).** Those are on `/score`, not on plays, and
  ADR 0019 already rejected them as optional. Deriving strength from the situation code gives the
  same answer on every goal.
- **A separate `GameState` or `Play` model.** Covered by ADR 0019 for live state; a play model is
  more than this issue needs.

## Consequences

- One request per poll for the whole game. A goal's `situation` duplicates the situation on
  `/score` at that moment, not the current one.
- `scorer_id` and `assist_ids` are NHL player IDs. Mapping them to canonical IDs is M3's job
  (the crosswalk, ADR 0026).
- Strength is checked against recorded goals (even strength, short-handed) and synthetic plays
  (power play, empty net); the NHL's play-by-play hasn't been checked for every case.
