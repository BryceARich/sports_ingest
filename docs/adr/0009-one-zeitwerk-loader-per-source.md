# 0009. Give each source its own Zeitwerk loader

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #6

## Context

`require "sports_ingest/<source>"` must load core plus that one source and nothing else: requiring
`nhl` must not load `CSV` or anything under `ESPN`. Core uses `Zeitwerk::Loader.for_gem`, which by
default manages everything under `lib/sports_ingest/`, sources included. Left alone, `require
"sports_ingest"` would make every source autoloadable, and `eager_load` would load all of them and
their dependencies.

## Decision

The core loader ignores each source's entry point and folder, listed in `SportsIngest::SOURCES`.
Each entry point (`lib/sports_ingest/<source>.rb`) requires core and defines the source's module,
which extends `SportsIngest::SourceLoader` and calls `load_from` to build a separate Zeitwerk
loader for `lib/sports_ingest/<source>/`. Acronyms (`nhl` → `NHL`, `espn` → `ESPN`) live in
`SourceLoader::INFLECTIONS`.

A spec requires each entry point in a fresh Ruby process and checks that no other source module and
no `CSV` got defined.

## Alternatives considered

- **One loader that ignores sources, with entry points `require` their files by hand.** Keeps one
  loader but gives up autoloading inside sources, and every new file needs a manual `require`.
- **One loader with no ignores, relying on autoload being lazy.** Constants are only loaded when
  referenced, but `SportsIngest::ESPN` would still be reachable without requiring it, and
  `eager_load` (used in production and in the naming spec) would pull in every source and its
  dependencies.
- **Separate gems per source.** Strongest isolation, but versioning and releasing five gems is too
  much overhead for a single-maintainer project at this stage.

## Consequences

- Adding a source means adding its name to `SportsIngest::SOURCES` and its module to the
  modular-loading spec, in addition to the entry point (see `ARCHITECTURE.md`).
- Each source's folder must exist (Zeitwerk refuses missing root directories), so empty source
  folders carry a `.keep` file until they get code.
- There are five loaders to eager-load when checking file names; the specs do this per source.
