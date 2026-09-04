#!/bin/bash
set -e

source dev-container-features-test-lib

check "claude_mem_version" claude-mem --version

# entrypoint's `claude-mem install` runs asynchronously to this test script;
# wait for it to finish instead of racing it.
timeout 30 bash -c 'until jq -e '\''.enabledPlugins["claude-mem@thedotmack"] == true'\'' "${HOME}/.claude/settings.json" > /dev/null 2>&1; do sleep 1; done'

check "claude_code_plugin_registered" bash -c 'jq -e '\''.enabledPlugins["claude-mem@thedotmack"] == true'\'' "${HOME}/.claude/settings.json" > /dev/null'
check "claude_mem_cache_is_symlink" bash -c '[ -L "${HOME}/.claude-mem" ]'

reportResults
