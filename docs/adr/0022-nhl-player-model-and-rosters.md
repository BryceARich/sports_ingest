# 0022. Model NHL roster players as `NHL::Player` and return rosters as arrays

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #22

## Context

M2-07 is the first NHL adapter that returns players. The acceptance criteria ask for Player models
with NHL IDs, position and birth date. Later issues read players from other NHL endpoints (player
landing and game logs, M2-08) and from other sources (ESPN, nflverse, Evolving-Hockey), and the
crosswalk (M3) ties them together through `Identity::PlayerRef`. The NHL module had no shared
client yet, and M2-02 and M2-06 were being built at the same time.

## Decision

- We add `SportsIngest::NHL::Player`, a model for the NHL's view of a player: a hockey
  `PlayerRef` (the NHL ID is the canonical ID), first and last name, the NHL position code
  (`C`, `L`, `R`, `D`, `G`) as a String, the team tri-code the roster listed them under, and bio
  fields (`birth_date` as a `Date`, height, weight, birthplace, sweater number, headshot). Bio
  fields the NHL leaves out are `nil`; a missing ID, name or position, or an unknown position,
  raises `SourceChangedError`.
- `SportsIngest::NHL::Rosters#fetch(team, season: nil)` returns `Array<Player>`, forwards then
  defensemen then goalies, and writes them to the processed cache under
  `nhl/rosters/<TRI_CODE>/<season ID or current>`. `team` is anything `Teams.fetch` resolves.
  `season: nil` asks for `/current` rather than computing the current season.
- Rosters reach `api-web.nhle.com` through the shared `SportsIngest::NHL::Client` (the same file
  M2-02 and M2-06 add); `SportsIngest::NHL::Season.id(2025)` turns ADR 0006's start year into
  `"20252026"`.

## Alternatives considered

- **A core `SportsIngest::Player` shared by every source.** Each source knows different things
  (ESPN has fantasy positions and injury status, EH a name and team codes), so one model would be
  mostly `nil`s or a lowest common denominator. Sources share identity through `PlayerRef`
  instead; a merged cross-source view can come with the crosswalk (M3) if consumers need it.
- **A `Roster` model wrapping players with team and season.** Adds a type for little: the
  players already carry `team`, and the season is the caller's argument and the cache key.
- **Positions as Symbols or a `forward`/`defense`/`goalie` group only.** Symbols turn into
  Strings in JSON, so the model would need coercion either way; the NHL's codes keep L/R wing
  information that fantasy tools use. `forward?`, `defense?` and `goalie?` cover the grouping.
- **Resolve the current season ourselves.** Needs the season-boundary helper ADR 0006 describes,
  which nothing else needs yet; the NHL's `/current` redirect already answers it.

## Consequences

- M2-08 can extend `NHL::Player` (bump `SCHEMA_VERSION`) or add a separate details model; either
  way the ref and bio fields here stay the base.
- `team` on a player means "the roster it came from", not necessarily the current team.
- Relocated teams' past rosters (`ARI`) can't be fetched, since `Teams.fetch` only knows current
  codes.
- Other NHL adapters reuse `NHL::Client` and `NHL::Season`, so parallel M2 PRs should not each
  add their own.
