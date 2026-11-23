# Changelog fragments

Each PR adds one file here instead of editing [`CHANGELOG.md`](../CHANGELOG.md), so parallel PRs
don't conflict ([ADR 0072](../docs/adr/0072-changelog-fragments-and-issue-numbered-adrs.md)).

- **Name:** `<issue>.md`, for example `72.md`. If one issue needs more than one, use
  `<issue>-<slug>.md`.
- **Content:** one or more [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) sections
  (`### Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`), each followed by
  `- ` entries. Wrap long entries onto lines indented by two spaces. End each entry with the
  build order, for example `(M1-05)`, or with the issue, `(#72)`, for tooling work.

```markdown
### Added

- The shared HTTP client, with retries and a per-source user agent (M1-05).
```

Commands:

```bash
bundle exec rake changelog:check              # every fragment parses (CI runs this)
bundle exec rake changelog:preview            # print the release section they'd make
bundle exec rake release:prepare[0.2.0]       # at release: compile fragments into CHANGELOG.md, rewrite the ADR index
```

`changelog:compile` also folds in the entries still listed under "Unreleased" in `CHANGELOG.md`,
then deletes the fragments.
