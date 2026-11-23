# 0008. CI on macOS Intel and Ubuntu ARM64; mise reads `.ruby-version` via a setting

- **Status:** Proposed
- **Date:** 2026-11-22
- **Issue:** #5

## Context

The gem has to work on the maintainer's Mac and on a Raspberry Pi (ARM64 Linux), so CI (M1-02)
should run on both kinds of machine. CI and local setup should also agree on one Ruby version,
pinned in `.ruby-version` (ADR 0007). mise 2026.x no longer reads `.ruby-version` by default:
`idiomatic_version_file_enable_tools` defaults to `[]`, so on a fresh clone `mise install`
installs nothing.

## Decision

- **CI runners.** One GitHub Actions workflow runs `bundle exec rspec` and `bundle exec rubocop`
  on `macos-15-intel` and `ubuntu-24.04-arm`, with `fail-fast: false` so one platform's failure
  doesn't hide the other's. Ruby comes from `ruby/setup-ruby` with
  `ruby-version-file: .ruby-version` and `bundler-cache: true`. Jobs set `LANG=C.UTF-8` because
  `script/claude/*` crash in `JSON.parse` under an ASCII locale.
- **Local Ruby.** Each machine runs `mise settings add idiomatic_version_file_enable_tools ruby`
  once (in the setup steps, and `bin/setup` adds it when missing). `.ruby-version` stays the
  only place the version is written.

## Alternatives considered

- **Apple Silicon (`macos-latest`) instead of Intel.** It matches newer Macs, but the issue asks
  for Intel, and ARM64 is already covered by the Ubuntu job. Adding it later is one matrix line.
- **Ubuntu x86_64 instead of ARM64.** The Pi is ARM64, and native-gem problems show up there.
- **Installing Ruby with mise in CI.** Same tool as local, but it compiles or downloads Ruby on
  every cold run and has no bundler cache; `ruby/setup-ruby` reads the same file.
- **A committed `mise.toml` with `[tools] ruby = "4.0.10"`.** Works without extra setup, but writes
  the version in two files that can drift.
- **A committed `mise.toml` with `[settings] idiomatic_version_file_enable_tools = ["ruby"]`.**
  Fails until every clone runs `mise trust`, which is one more step than the global setting.

## Consequences

- One extra setup line per machine; it changes the user's global mise settings (only adding Ruby
  to a list), which `bin/setup` does without asking.
- Bumping `.ruby-version` bumps CI; a just-released Ruby may not be in `ruby/setup-ruby` yet.
- If GitHub retires `macos-15-intel`, the Intel job moves to whatever Intel image remains, or is
  dropped by a new ADR.
