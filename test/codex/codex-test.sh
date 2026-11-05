#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "codex_version" codex --version
# The Feature no longer adds SYS_ADMIN (bit 21 of the bounding set).
check "no_sys_admin" bash -c '
	(( (0x$(awk "/^CapBnd:/ {print \$2}" /proc/self/status) >> 21 & 1) == 0 ))
'
check "system_config_turns_sandbox_off" bash -c '
	[ "$(cat /etc/codex/config.toml)" = "sandbox_mode = \"danger-full-access\"" ]
'
# Codex reports its effective sandbox mode in the model-visible prompt,
# which renders without logging in. A user config must still win.
check "codex_uses_system_sandbox_mode" bash -c '
	CODEX_HOME="$(mktemp -d)" codex debug prompt-input 2>/dev/null \
		| grep -q "sandbox_mode\` is \`danger-full-access\`"
'
check "user_config_overrides_system_config" bash -c '
	home="$(mktemp -d)"
	printf "sandbox_mode = \"workspace-write\"\n" > "$home/config.toml"
	CODEX_HOME="$home" codex debug prompt-input 2>/dev/null \
		| grep -q "sandbox_mode\` is \`workspace-write\`"
'

# Report result
reportResults
