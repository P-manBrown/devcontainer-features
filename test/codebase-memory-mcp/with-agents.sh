#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "codebase_memory_mcp_version" codebase-memory-mcp --version

# The entrypoint's install runs as part of the container's startup
# process, asynchronously to this test script; wait for it to finish
# instead of racing it. The installer writes the config first, and
# install.sh restores the symlinks afterward in an EXIT trap, so wait
# for both. If either never happens, the wait times out and the checks
# below report which one is missing.
timeout 60 bash -c 'until grep -q codebase-memory-mcp "${HOME}/.claude.json" 2>/dev/null \
	&& [ -L "${HOME}/.claude.json" ] && [ -L "${HOME}/.codex" ]; do sleep 1; done' || true

# Claude Code and Codex persist their config across container rebuilds by
# symlinking it into a named volume (see their features' init scripts);
# Codex links its whole ~/.codex directory. codebase-memory-mcp's
# installer refuses to write through a symlink, so these checks confirm
# install.sh's materialize-then-restore workaround both configured each
# agent and left the symlink intact afterward.
check "claude_code_mcp_configured" bash -c 'grep -q codebase-memory-mcp "${HOME}/.claude.json"'
check "claude_json_still_symlink" bash -c '[ -L "${HOME}/.claude.json" ]'
check "codex_mcp_configured" bash -c 'grep -q codebase-memory-mcp "${HOME}/.codex/config.toml"'
check "codex_dir_still_symlink" bash -c '[ -L "${HOME}/.codex" ]'

check "no_restore_leftover" bash -c '[ ! -e /usr/local/share/codex-config/codex.restore ]'

# Report result
reportResults
