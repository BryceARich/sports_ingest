# 0007. Pin Ruby with mise, autoload with Zeitwerk, lint with Standard

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #4

## Context

The gem skeleton (M1-01) fixes the toolchain every later issue builds on. It has to work the
same way on the maintainer's Mac and on a Raspberry Pi, and in CI (M1-02). macOS ships an old
system Ruby (2.6) that can't run modern gems. Three choices had real alternatives: how Ruby is
installed and pinned, how files are loaded, and which lint rules apply.

## Decision

- **Ruby version.** We pin the newest stable Ruby, currently **4.0.10**, in `.ruby-version`, and
  install it with **mise** (`mise install`). The gemspec requires `>= 4.0`. CI reads
  `.ruby-version` so local and CI stay in sync. When a newer stable Ruby comes out, bump
  `.ruby-version` and update `docs/RESUME.md`.
- **Loading.** We use **Zeitwerk** (`Zeitwerk::Loader.for_gem`): one constant per file, file
  paths match constant names. Zeitwerk is pure Ruby, so it adds no native extension to core.
- **Lint.** We use **Standard Ruby**'s rules, run through RuboCop (`bundle exec rubocop`) by
  requiring `standard` in `.rubocop.yml`. Local overrides are rare and each carries a comment
  saying why.

## Alternatives considered

- **rbenv, rvm or asdf for Ruby.** rbenv and rvm only manage Ruby; asdf is slower and plugin-based.
  mise reads `.ruby-version`, also manages other tools if we ever need them, and has a one-line
  installer on the Pi.
- **Supporting older Rubies (for example `>= 3.2`).** Wider reach, but there are no outside
  consumers yet, and a test matrix across versions costs CI time and Pi build time for no user.
- **Plain `require_relative` instead of Zeitwerk.** No dependency, but every file needs manual
  requires in the right order, and modular loading (M1-03) is harder to keep honest.
- **A custom RuboCop config.** Endless style debates and per-cop tuning. Standard is fixed, so
  there's nothing to argue about; `standardrb` would work too, but plain `rubocop` keeps editor
  integrations simple.

## Consequences

- Setup is `mise install && bundle install` on both machines. On the Pi, `mise install` compiles
  Ruby, which takes 15+ minutes.
- Consumers must run Ruby 4.0 or newer. Lowering the floor later is a new ADR.
- Every file under `lib/` must follow Zeitwerk's naming; a spec eager-loads the gem to catch
  mismatches. Acronym constants (`NHL`, `ESPN`, `HTTP`) need inflector entries when they land
  (M1-03, M1-05).
- `Gemfile.lock` is committed so the Mac, the Pi and CI resolve the same gem versions.
