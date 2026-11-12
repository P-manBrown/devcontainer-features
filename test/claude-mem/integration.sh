#!/bin/bash
# Shared assertions for the real Feature scenarios (run as remoteUser).
set -eu
source dev-container-features-test-lib
source /usr/local/share/claude-mem.env

check "claude_mem_version" claude-mem --version
check "uv_version" uv --version
check "uvx_version" uvx --version
check "user_login_uvx" bash -lc 'uvx --version'
# The Worker is a child process too: check executable resolution without a shell.
check "child_process_uvx" node -e 'require("child_process").execFileSync("uvx", ["--version"], {stdio: "inherit"})'

verify_integrations() {
    if [[ ",${IDE//[[:space:]]/}," == *,claude-code,* ]]; then
        jq -e '.enabledPlugins["claude-mem@thedotmack"] == true' "${HOME}/.claude/settings.json" >/dev/null || return 1
        test -f "${HOME}/.claude/plugins/marketplaces/thedotmack/plugin/scripts/worker-service.cjs" || return 1
    fi
    if [[ ",${IDE//[[:space:]]/}," == *,codex-cli,* ]]; then
        # Ask Codex to load its installed plugin state, rather than matching a
        # string in a config that could point to a missing plugin bundle.
        codex plugin list | grep -F 'claude-mem@claude-mem-local' || return 1
        test -f "${HOME}/.claude/plugins/marketplaces/thedotmack/plugin/hooks/codex-hooks.json" || return 1
    fi
}
# Feature entrypoints can run asynchronously to the scenario test command.
ready=false
for ((attempt=0; attempt<120; attempt++)); do
    if verify_integrations >/dev/null 2>&1; then ready=true; break; fi
    sleep 1
done
check "initial_registration" test "${ready}" = true
verify_provider_settings() {
    local expected="${PROVIDER}"
    [[ "${expected}" != by-source ]] || expected=claude
    jq -e --arg expected "${expected}" '.CLAUDE_MEM_PROVIDER == $expected' "${HOME}/.claude-mem/settings.json" >/dev/null || return 1
    if [[ "${PROVIDER}" == by-source ]]; then
        jq -e '(.CLAUDE_MEM_PROVIDER_BY_SOURCE | fromjson) == {claude: "claude", codex: "codex"}' "${HOME}/.claude-mem/settings.json" >/dev/null
    else
        jq -e '.CLAUDE_MEM_PROVIDER_BY_SOURCE == ""' "${HOME}/.claude-mem/settings.json" >/dev/null
    fi
}
check "provider_settings" verify_provider_settings
check "cache_is_symlink" test -L "${HOME}/.claude-mem"

if [[ ",${IDE//[[:space:]]/}," == *,claude-code,* ]]; then
    jq '.env.CLAUDE_MEM_FEATURE_TEST = "preserved"' "${HOME}/.claude/settings.json" > "${HOME}/.claude/settings.json.tmp"
    mv "${HOME}/.claude/settings.json.tmp" "${HOME}/.claude/settings.json"
fi
if [[ ",${IDE//[[:space:]]/}," == *,codex-cli,* ]]; then
    printf '\n# claude-mem feature test sentinel\n' >> "${HOME}/.codex/config.toml"
fi
printf 'preserved\n' > "${HOME}/.claude-mem/feature-test-sentinel"
# Exercise the non-root entrypoint and repeat registration against existing
# config and memory. Actual Docker restart/rebuild is a separate manual check.
check "repeat_initialization" /usr/local/share/claude-mem-init.sh
check "registrations_survive_reinitialization" verify_integrations
check "provider_settings_survive_reinitialization" verify_provider_settings
if [[ ",${IDE//[[:space:]]/}," == *,claude-code,* ]]; then
    check "claude_settings_preserved" jq -e '.env.CLAUDE_MEM_FEATURE_TEST == "preserved"' "${HOME}/.claude/settings.json"
fi
if [[ ",${IDE//[[:space:]]/}," == *,codex-cli,* ]]; then
    check "codex_settings_preserved" grep -qx '# claude-mem feature test sentinel' "${HOME}/.codex/config.toml"
fi
check "memory_survives_reinitialization" grep -qx preserved "${HOME}/.claude-mem/feature-test-sentinel"

check "worker_start" claude-mem start
check "worker_environment_uvx" node - <<'JS'
const fs = require('fs');
const cp = require('child_process');
let checked = false;
for (const pid of fs.readdirSync('/proc').filter(p => /^\d+$/.test(p))) {
    let command, environment;
    try {
        if (fs.statSync(`/proc/${pid}`).uid !== process.getuid()) continue;
        command = fs.readFileSync(`/proc/${pid}/cmdline`, 'utf8');
        if (!command.includes('worker-service.cjs')) continue;
        environment = fs.readFileSync(`/proc/${pid}/environ`, 'utf8');
    } catch { continue; }
    const path = environment.split('\0').find(item => item.startsWith('PATH='));
    if (!path) throw new Error(`Worker ${pid} has no PATH`);
    cp.execFileSync('uvx', ['--version'], {
        env: {...process.env, PATH: path.slice(5)}, stdio: 'inherit'
    });
    checked = true;
}
if (!checked) throw new Error('No running Worker found for the remote user');
JS

reportResults
