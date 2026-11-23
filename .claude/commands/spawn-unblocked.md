---
description: Start a Claude desktop app session (own worktree, Remote Control on) for each issue whose blockers have merged
argument-hint: "[max sessions, default 3] [--dry-run]"
allowed-tools: Bash(script/claude/ready-issues:*), mcp__ccd_session__start_session, mcp__ccd_session_mgmt__set_remote_control
---

# Start sessions for unblocked issues

Arguments: `$ARGUMENTS`. A number is the most sessions to start (default 3); `--dry-run` only lists.

This needs the Claude desktop app (Code tab), whose session tools start and link sessions. If
`mcp__ccd_session__start_session` isn't available (for example in the terminal CLI), say so and
stop; `script/claude/spawn-unblocked` starts headless sessions from a terminal instead.

**Keep token use low.** Don't query GitHub, read issues or create worktrees yourself. The app
creates each worktree, and each session reads its own issue.

## 1. Find ready issues

Run `LANG=en_US.UTF-8 script/claude/ready-issues` (Ruby from `.ruby-version` must be on `PATH`;
if `ruby -v` is the system Ruby, prefix the command with `mise exec --`). Each `READY` line is
`READY  #<N>  <label>  <branch>`. Take the first `max` lines in order. If none are ready, or with
`--dry-run`, print the lines and stop.

## 2. Start one session per issue

For each one, call `mcp__ccd_session__start_session` with `initiation: "user_asked"`,
`context: "fresh"`, `use_worktree: true`, `name: "<branch>"` (cut to 24 characters),
`title: "<label> <issue title> (#<N>)"`, and:

- `background`: "`sports_ingest` is a Ruby gem that reads sports data into cached Ruby models.
  This session was started by `/spawn-unblocked` because every blocker of #<N> has merged. The
  maintainer follows it from their phone through Remote Control."
- `prompt` (fill in `<N>` and `<branch>`):

  > Work GitHub issue #<N> in this worktree.
  >
  > 1. Rename your branch to the project convention and bring it up to date (the worktree is
  >    new, so there's nothing to lose): `git branch -m <branch> && git fetch origin main &&
  >    git reset --hard origin/main`.
  > 2. Read `CLAUDE.md` and `docs/RESUME.md`, then read `.claude/commands/work-issue.md` and
  >    follow it for issue #<N> (its argument placeholder means <N>). You're already on the
  >    issue's branch, so skip branch creation.
  > 3. Run `script/claude/identity` once and act as the account it prints (`CLAUDE.md`, "Claude's
  >    GitHub identity"): its `gh` token prefix, commit identity and push remote. Never
  >    `gh auth switch`, never push to `main`, never merge.
  > 4. If `ruby -v` isn't the version in `.ruby-version`, mise isn't activated in this shell:
  >    prefix Ruby commands with `mise exec --` (run `bin/setup` once if gems are missing). Run
  >    `script/claude/*` with `LANG=en_US.UTF-8`.
  > 5. If you need a maintainer decision, ask in this session (they follow it from their phone)
  >    and also comment on the issue, leaving it In Progress.
  >
  > Done: a PR from `<branch>` that says `Closes #<N>`, the DoD ticked, #<N> at Awaiting Human
  > Review on the board, and handoff comments on dependents where useful.

Then call `mcp__ccd_session_mgmt__set_remote_control` with that session's id and
`enabled: true`. If it can't be turned on, say so for that session and carry on.

Start the sessions one after another, not in parallel, so a refusal (the app caps how many run
at once) stops the rest cleanly: report which started and which didn't.

## 3. Report

One line per issue: the session link, the issue number and label, and whether Remote Control is
on. Nothing else.
