#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

wrapper='/usr/local/share/rtk-claude-hook/rtk hook claude'
settings="${HOME}/.claude/settings.json"

check "hook_registered" timeout 30 bash -c 'until jq -e --arg wrapper "/usr/local/share/rtk-claude-hook/rtk hook claude" '\''any(.hooks.PreToolUse[]?.hooks[]?; .command == $wrapper)'\'' "${HOME}/.claude/settings.json" >/dev/null 2>&1; do sleep 1; done'

hook_output() {
	jq -n --arg cwd "$1" --arg command "$2" '{cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' \
		| /usr/local/share/rtk-claude-hook/rtk hook claude
}

worktree_git() {
	local output
	output="$(hook_output /workspaces/x/.claude/worktrees/agent-abc 'git status')" || return
	[[ -z "${output}" ]]
}
worktree_git_log() {
	local output
	output="$(hook_output /workspaces/x/.claude/worktrees/my-feature 'git -C /tmp log')" || return
	[[ -z "${output}" ]]
}
regular_git() {
	hook_output /workspaces/x 'git status' | jq -e '.hookSpecificOutput.updatedInput.command | contains("rtk git status")'
}
worktree_non_git() {
	local command
	for command in 'ls -la' 'cargo test'; do
		if rtk rewrite "${command}" | grep -q rtk; then
			hook_output /workspaces/x/.claude/worktrees/agent-abc "${command}" | jq -e '.hookSpecificOutput.updatedInput'
			return
		fi
	done
	return 1
}
no_hook_warning() {
	local output
	output="$(rtk ls 2>&1)" || return
	[[ "${output}" != *'No hook installed'* ]]
}

check "worktree_git_passthrough" worktree_git
check "enter_worktree_git_passthrough" worktree_git_log
check "regular_git_rewritten" regular_git
check "worktree_non_git_rewritten" worktree_non_git
check "no_missing_hook_warning" no_hook_warning

# Seed duplicates and unrelated hooks without replacing the settings inode.
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
jq '.hooks.PreToolUse += [{matcher: "Bash", hooks: [{type: "command", command: "echo other-hook"}]}, {matcher: "Bash", hooks: [{type: "command", command: "rtk hook claude"}]}] | .hooks.PostToolUse = [{matcher: "Bash", hooks: [{type: "command", command: "echo post-hook"}]}]' "${settings}" > "${tmp}"
cat "${tmp}" > "${settings}"
settings_stat="$(stat -L -c '%U:%G %a %i' "${settings}")"
sudo /usr/local/share/rtk-init.sh
sudo /usr/local/share/rtk-init.sh

check "exactly_one_wrapper" jq -e --arg wrapper "${wrapper}" '[.hooks.PreToolUse[]?.hooks[]? | select(.command == $wrapper)] | length == 1' "${settings}"
check "no_plain_hook" jq -e '[.hooks.PreToolUse[]?.hooks[]? | select(.command == "rtk hook claude")] | length == 0' "${settings}"
check "other_hook_preserved" jq -e 'any(.hooks.PreToolUse[]?.hooks[]?; .command == "echo other-hook")' "${settings}"
check "post_hook_preserved" jq -e 'any(.hooks.PostToolUse[]?.hooks[]?; .command == "echo post-hook")' "${settings}"
check "settings_metadata_preserved" test "${settings_stat}" = "$(stat -L -c '%U:%G %a %i' "${settings}")"
check "claude_directory_still_symlink" test -L "${HOME}/.claude"

# Report result
reportResults
