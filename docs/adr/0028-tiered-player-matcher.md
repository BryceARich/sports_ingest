# 0028. Match source players to canonical IDs in four tiers, stopping at ambiguity

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #28

## Context

Every source's player record has to be tied to a canonical `PlayerRef`
([ADR 0026](0026-canonical-id-scheme.md)). Some sources carry an ID we've already mapped, most
only carry a name plus some of birth date, position and team. Name keys
([ADR 0027](0027-name-match-keys.md)) aren't unique: two Elias Petterssons play for Vancouver (a
centre and a defenceman), and two Sebastian Ahos are active (Carolina forward, Islanders
defenceman). A wrong match is worse than no match, because it silently merges two players' stats
and gets persisted by the crosswalk (M3-06). Overrides (M3-04) and the unmatched report (M3-05)
build on the result.

## Decision

`SportsIngest::Identity::Matcher.new(players)` indexes the known players of one sport (anything
with `ref`, `full_name`, `birth_date`, `position`, `team`, such as `NHL::Player`).
`#match(source:, name:, id:, birth_date:, position:, team:)` tries, in order:

1. **Source ID** already on a known ref → confidence `:exact`.
2. **Name key + birth date** → `:high`.
3. **Name key + position + team** → `:medium`.
4. **A name key only one known player has** → `:low`.

Before tiers 2 to 4, players whose known birth date or position group contradicts the record are
set aside. Hockey positions are compared as groups (forward, defence, goalie), because sources
disagree about centre versus wing for the same player. Teams are compared through `Teams.find`,
so any source's code or name works. A team mismatch is not a contradiction (trades), it only skips
tier 3.

The first tier that finds exactly one player wins. If a tier finds more than one, the result is
`:ambiguous` and later tiers aren't tried; if no player is left, it's `:no_match`. Unmatched
results carry the candidate refs (same name key) for the unmatched report. A matched ref comes back
with the source's ID added (`with_source_id`), ready for the crosswalk. A record from the canonical
source (`:nhl`) whose ID isn't known is never name-matched, since that would give one player two
NHL IDs.

The result is a `SportsIngest::Identity::Match` model: `ref`, `confidence`
(`:exact`/`:high`/`:medium`/`:low`/`:none`), `reason` (the tier's name, `:ambiguous` or
`:no_match`), a `detail` string, and `candidates`. The confidence follows from the reason, so they
can't disagree.

## Alternatives considered

- **A score (weighted sum of matching fields) instead of tiers.** More flexible, but scores need
  tuning, are hard to explain in a report, and a high name weight can outvote a contradicting
  birth date. Tiers give a reason anyone can check.
- **Keep trying later tiers after an ambiguous one.** Tier 4 can't split what tier 3 couldn't, so
  it would only ever turn ambiguity into a guess.
- **Exact positions (C ≠ LW).** Catches more contradictions in theory, but ESPN and others list
  centres as wingers, so real players would fall out of tiers 3 and 4.
- **Fuzzy (edit-distance) matching as a fifth tier.** Would catch `Stuetzle` and nickname gaps,
  but it's the riskiest tier and the issue scopes the four exact-key tiers. Unmatched rows go to
  the report (M3-05) and overrides (M3-04) instead; a fuzzy tier can be added later as candidates
  only.
- **Raise on ambiguity.** Callers import whole files; one ambiguous row shouldn't stop the import.

## Consequences

- Tier 4 (`:low`) trusts that the known pool is complete: a unique name in a pool that's missing
  the namesake will match the wrong player. Build the matcher from every roster (and recent
  players) of the sport, and have M3-05 list `:low` matches for review.
- A known player's `team` is the current team; records from past seasons skip tier 3 and rely on
  birth date or a unique name.
- Overrides (M3-04) go in front of tier 1; the crosswalk (M3-06) stores matched refs so a player is
  matched once.
