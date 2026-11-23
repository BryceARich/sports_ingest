# 0027. Normalize player names to a lossy match key

- **Status:** Proposed
- **Date:** 2026-11-23
- **Issue:** #27

## Context

Sources that have no player ID (Evolving-Hockey exports, and other name-only files) have to be
matched to the canonical ID ([ADR 0004](0004-canonical-player-ids.md)) by name. The same player is
spelled differently across sources: accents (`Stützle` / `Stutzle`), case (`MacKinnon` /
`Mackinnon`), order (`Stützle, Tim`), suffixes (`Jr.`, `III`), punctuation (`O'Connor`,
`Ekman-Larsson`, `J.T.`) and nicknames (`Mitch` / `Mitchell`, `Evgeni` / `Evgeny`). The tiered
matcher (M3-03) needs an exact-comparison step before fuzzy matching.

## Decision

`SportsIngest::Identity::NameNormalizer.key(name)` returns one String key, lowercase ASCII words
joined by single spaces:

1. One comma means "Last, First" and is swapped; suffixes written after a comma are dropped.
2. Accents are removed by Unicode decomposition (stdlib `unicode_normalize`), plus a small table
   for letters that don't decompose (`ø`, `æ`, `ß`, `ł`, ...).
3. Apostrophes and periods are deleted (`O'Connor` → `oconnor`, `J.T.` → `jt`); hyphens and other
   punctuation become spaces (`Ekman-Larsson` → `ekman larsson`). Runs of single letters merge
   (`J. T.` → `jt`).
4. Trailing `jr`, `sr`, `ii`, `iii`, `iv` are dropped while at least two words remain.
5. The first word goes through a nickname and transliteration table (`NICKNAMES`).

The key is for matching only, never displayed, and isn't unique: the matcher confirms a key match
with team or birth date.

## Alternatives considered

- **A structured result (first, last, suffix).** Lets the matcher weigh parts separately, but
  splitting first from last name is unreliable (`Pierre-Luc Dubois`, `Trevor van Riemsdyk`), and
  the matcher's fuzzy tier can compare whole keys.
- **German transliteration (`ü` → `ue`).** Would match `Stuetzle`, but no source we read spells it
  that way, and a `ue` → `u` rule would also change names like `Samuel`. Left to the fuzzy tier.
- **Nickname table applied to every word, or both ways.** Catches more, but turns surnames like
  `Alex` or `Will` into first names and makes keys harder to predict.
- **A gem (`i18n` transliteration, `namae`).** More coverage, but adds dependencies to core for a
  few lines of stdlib code.

## Consequences

- Variants that aren't in the table (`Max` / `Maxim`, `Ue` spellings) don't match exactly and fall
  through to the fuzzy tier. The table is easy to extend as unmatched reports show gaps.
- Changing these rules changes which names match exactly; matches already saved in the persisted
  crosswalk (M3-06) stay as they are until a player is re-matched.
