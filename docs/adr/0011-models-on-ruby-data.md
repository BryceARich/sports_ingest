# 0011. Build models on Ruby's `Data`

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #11

## Context

Every source maps its payloads into models that the caches store as JSON and consumers read.
Models must be immutable, compare by value, round-trip through `to_h` / `to_json` / `from_h`, and
carry a schema version so the processed cache (M1-07) can spot entries written by older code.
Core must stay free of native extensions and light on dependencies (ADR 0001, Raspberry Pi).

## Decision

We will build models with `SportsIngest::Model.define(*fields, schema_version: 1)`, which returns
a `Data.define` subclass that includes `SportsIngest::Model`. The mixin:

- deep-freezes field values, copying unfrozen strings, arrays and hashes so callers' objects stay
  mutable;
- makes `to_h` recurse into nested models, arrays and hashes, and adds `to_json` on top of it;
- adds `from_h` (symbol or string keys) and `coerce` (instance, hash or `nil`) class methods.

Each model class gets a `SCHEMA_VERSION` constant. Bump it when fields or their meaning change.
`from_h` is strict: a missing or unknown key raises `ArgumentError`, as `Data.new` does.
Nested models and non-JSON types (dates, times) are rebuilt in the model's own `initialize`
override, for example `super(team: Team.coerce(team), **fields)`.

## Alternatives considered

- **dry-struct.** Typed attributes and coercion for free, but pulls in dry-types, dry-core,
  dry-logic and concurrent-ruby. Too heavy for core, and the type system is more than the models
  need today.
- **Plain classes or `Struct`.** No built-in immutability or keyword-only construction; we'd
  rewrite what `Data` already gives us (`==`, `hash`, `with`, `inspect`, pattern matching).
- **A type DSL on top of `Data`** (declare `team: Team` and coerce automatically). Less code per
  model, but a mini-framework to maintain before we know which coercions we need. Can be added
  later without changing the public methods.

## Consequences

- No new runtime dependency; `json` ships with Ruby.
- Models get `==`, `hash`, `with`, `deconstruct_keys` and pattern matching from `Data`.
- Nested models need a short `initialize` override; that's the price of skipping a type DSL.
- `from_h` raises `ArgumentError` for now. Once the gem's error hierarchy lands (M1-09), callers
  that read cached data (M1-07) should wrap it in a gem error.
- Bumping `SCHEMA_VERSION` is a manual step; reviewers should check it when a model's fields change.
