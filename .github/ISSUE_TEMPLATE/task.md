---
name: Task
about: A unit of planned work from the build order (one branch, one PR)
title: "[Mx-yy] "
labels: []
assignees: []
---

**Build order:** `Mx-yy` · **Milestone:** Mx <milestone name>

## Context

<!-- Why this is needed and what it builds on. Link ADRs, docs or earlier issues. -->

## Task

<!-- What to build or change, concretely. -->

## Acceptance criteria

<!-- How a reviewer can tell it works. Prefer things that can be checked, e.g. a command that passes. -->

## Blocked by

<!-- Issues that must merge first, as #123, or "Nothing." -->

Nothing. Can start once its milestone opens.

## Definition of Done

- [ ] Tests added or updated; CI green
- [ ] Public methods have YARD comments (what, params, returns, raises; an example if usage isn't obvious)
- [ ] README / `docs/RESUME.md` / `docs/ARCHITECTURE.md` updated if setup, behavior, or structure changed
- [ ] An ADR in `docs/adr/` for any decision that had real alternatives
- [ ] A CHANGELOG entry under "Unreleased"
