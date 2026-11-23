# 0001. Build `sports_ingest` as a Ruby library (gem)

- **Status:** Accepted
- **Date:** 2026-11-22
- **Issue:** #2

## Context

Several projects need the same sports data: fantasy tools, dashboards, a GAR league app, and
possibly an HTTP API later. Each one re-implementing fetch, parse, cache and player matching would
duplicate the hardest parts (undocumented NHL endpoints, ESPN cookie auth, fuzzy name matching).
The consumers are Ruby projects, and one of the target machines is a Raspberry Pi.

## Decision

We will build `sports_ingest` as a Ruby gem that consumers `require`. Each source is a separately
loadable module (`require "sports_ingest/nhl"`), and core has no native-extension dependencies.
An HTTP API, if needed, is a thin layer on top of the library (M8-01), not a replacement for it.

## Alternatives considered

- **A standalone service with an HTTP API from day one.** Every consumer would depend on a running
  process, and the Pi would have to host it. More moving parts before there's a second consumer
  that needs it. Kept as an optional later layer.
- **Python (pandas ecosystem).** Strong data tooling, and nflverse has Python bindings, but the
  consumers are Ruby, so they would need a process or file boundary to use it.
- **Copy-paste helpers per project.** No upfront cost, but the matching logic and source quirks
  would drift apart between projects.

## Consequences

- Consumers get plain Ruby objects with no network hop.
- We need gem discipline: semantic versioning, a CHANGELOG, YARD docs, offline specs.
- Native extensions are off the table for core, which rules out some fast parsers and database
  drivers there. A source that needs one must prove it installs on the Pi.
- Modular loading must be tested (M1-03) so one source's dependencies don't leak into another's.
