## Claude Code hook in worktrees

With `claudeCodeHook` enabled, the registered command is `/usr/local/share/rtk-claude-hook/rtk hook claude`, a wrapper around `rtk hook claude`. Inside Claude Code worktrees (`/.claude/worktrees/`), commands whose rewrite would involve git are left unrewritten because Claude Code’s worktree isolation refuses git run as an operand of rtk. Everything else is compressed as usual.

On each container start, the entrypoint normalizes `settings.json` to exactly one wrapper entry, leaving other hooks alone.
