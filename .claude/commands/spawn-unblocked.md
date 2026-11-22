---
description: Start a fresh headless Claude session (own worktree) for each issue whose blockers have merged
argument-hint: "[max sessions, default 3] [--dry-run] [--all]"
allowed-tools: Bash(script/claude/spawn-unblocked:*)
---

Run this and nothing else:

```bash
script/claude/spawn-unblocked $ARGUMENTS
```

Relay its output to the user as is. Don't query GitHub, read issues or create worktrees yourself;
the script does all of that. If it fails, show the error and stop.

(The script needs no Claude at all, so running `script/claude/spawn-unblocked` straight from a
terminal is the cheapest way to do this.)
