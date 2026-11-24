# 0039. Namespace ESPN reads as `ESPN::Read` and reserve `ESPN::Write` behind an explicit opt-in

- **Status:** Proposed
- **Date:** 2026-11-24
- **Issue:** #39

## Context

M4 adds read-only adapters (client, drafts, filters, rosters). Lineup setting is the first write,
and it is later. ADR 0032 and #32's handoff note say a write path needs its own client method
behind an opt-in, not a flag on the client that only issues GETs. We want the read/write split in
the code layout now, so the write side has a place to land without moving the read classes again.

## Decision

- **Read side under `ESPN::Read`.** `Client`, `Filter`, `Drafts`, `Draft` and `DraftPick` move from
  `ESPN::` to `ESPN::Read::`, one folder (`lib/sports_ingest/espn/read/`), so the layout matches
  the namespace.
- **Write side reserved as `ESPN::Write`.** `lib/sports_ingest/espn/write.rb` defines an empty
  module with no methods. Nothing uses it yet.
- **Opt-in is by reference.** The ESPN loader autoloads on demand, so `require "sports_ingest/espn"`
  doesn't define `ESPN::Write`. Code that wants writes names the module, and the module stays
  unused until a write issue adds a client for it.
- **No aliases for the old names.** `ESPN::Client` and the others aren't kept as aliases. The gem
  is pre-release (0.1.0, nothing published under the old names), so a clean rename is safer than
  two names for one class.

## Alternatives considered

- **Keep `ESPN::Client` and only add `ESPN::Write` beside it.** Smallest change, but the read
  classes stay at the top level, so the layout wouldn't show the split and a reader could take
  `ESPN::Client` for a general client.
- **Keep old names as aliases.** Avoids breaking any caller, but nothing outside this repo uses
  the names yet, so the aliases would only be clutter.
- **Gate `ESPN::Write` behind a configuration flag or environment variable.** A flag checked on
  every call is easy to leave on. Loading the module only when named is the same boundary with
  less machinery, and a write client can add its own check when it lands.
