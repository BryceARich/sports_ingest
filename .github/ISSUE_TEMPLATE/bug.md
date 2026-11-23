---
name: Bug
about: Something in the gem returns wrong data, raises, or behaves unexpectedly
title: ""
labels: ["bug"]
assignees: []
---

## Context

<!-- Which source and module (e.g. `sports_ingest/nhl`), gem version or commit, Ruby version,
     and machine (Mac or Pi). -->

## What happened

<!-- Steps or a minimal snippet that reproduces it, and the actual result or error.
     Do NOT paste `espn_s2` / `SWID` cookies, or Evolving-Hockey / PuckPedia data. -->

## What you expected

## Acceptance criteria

<!-- Usually: a spec that reproduces the bug now passes. -->

- [ ] A regression spec covers this case and passes offline

## Blocked by

Nothing.

## Definition of Done

- [ ] Tests added or updated; CI green
- [ ] Public methods have YARD comments (what, params, returns, raises; an example if usage isn't obvious)
- [ ] README / `docs/RESUME.md` / `docs/ARCHITECTURE.md` updated if setup, behavior, or structure changed
- [ ] An ADR in `docs/adr/` for any decision that had real alternatives
- [ ] A CHANGELOG entry under "Unreleased"
