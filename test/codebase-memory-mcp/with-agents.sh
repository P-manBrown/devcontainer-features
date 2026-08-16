#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "codebase_memory_mcp_version" codebase-memory-mcp --version

# The entrypoint's install runs as part of the container's startup
# process, asynchronously to this test script; wait for it to finish
# writing the agent config instead of racing it.
timeout 30 bash -c 'until grep -q codebase-memory-mcp "${HOME}/.claude.json" 2>/dev/null; do sleep 1; done'

# Claude Code and Codex persist their config across container rebuilds by
# symlinking it into a named volume (see their features' init scripts).
# codebase-memory-mcp's installer refuses to write through a symlink, so
# these checks confirm install.sh's materialize-then-restore workaround
# both configured each agent and left the symlink intact afterward.
check "claude_code_mcp_configured" bash -c 'grep -q codebase-memory-mcp "${HOME}/.claude.json"'
check "claude_json_still_symlink" bash -c '[ -L "${HOME}/.claude.json" ]'
check "codex_mcp_configured" bash -c 'grep -q codebase-memory-mcp "${HOME}/.codex/config.toml"'
check "codex_config_still_symlink" bash -c '[ -L "${HOME}/.codex/config.toml" ]'

# Report result
reportResults
