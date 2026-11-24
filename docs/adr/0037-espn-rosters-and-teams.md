# 0037. ESPN rosters and teams: ESPN IDs kept until the crosswalk

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #37

## Context

ESPN's `mTeam` and `mRoster` views give a league's teams and, for each, its roster. A roster entry
carries ESPN's player ID and the real team as ESPN's `proTeamId`. The canonical player ID is the
NHL's (ADR 0026), and the crosswalk that maps other sources to it is M3, which isn't built yet.

## Decision

- `ESPN::Rosters#fetch(league_id, season:)` returns `ESPN::FantasyTeam` models, each with its
  `ESPN::RosterEntry` list. It writes them to the processed cache under
  `espn/<game>/leagues/<id>/<season>/teams`.
- `RosterEntry#player_id` is ESPN's ID. It is not canonical yet. The NHL ID is added to the
  player's `source_ids` when the crosswalk maps it (M3), not here.
- `RosterEntry#pro_team` is the NHL tri-code, from `Teams.find_by_source_id(:espn, proTeamId)`.
  Free agents (`proTeamId` 0) and unknown IDs give `nil`, which keeps a bad table entry from
  failing the whole roster.
- Both models are plain `Model`s with no team-level derivations beyond `FantasyTeam#name`.

## Alternatives considered

- **Map ESPN player IDs to NHL IDs in this issue.** Rejected: that's the crosswalk's job (M3), and
  it needs matching by name across sources. Doing it here would duplicate M3 and drift from it.
- **Raise on an unknown `proTeamId`.** Rejected: ESPN can add or rename teams between seasons; a
  roster should still parse with `pro_team: nil` and the gap visible.
- **One flat roster-entry list, without teams.** Rejected: the league's team structure (owners,
  names) is part of what consumers need, and the cache entry would have to rebuild it.

## Consequences

- Consumers get ESPN player IDs and tri-codes now, and join to NHL IDs once M3 lands.
- Keys under `espn/…/teams` are versioned by the models' `SCHEMA_VERSION`, so a later change to the
  roster fields invalidates old entries.
