#!/bin/bash
set -e

source dev-container-features-test-lib

# Precondition: another Feature (upstream common-utils) put a system bwrap
# on the user's PATH; without it this scenario would not exercise the bug.
check "system_bwrap_on_user_path" bash -c '
	path="$(command -v bwrap)"
	[ "$path" = "/usr/bin/bwrap" ] || [ "$path" = "/bin/bwrap" ]
'
# The following run inside Codex's own process tree. Codex prints a stale
# arg0 cleanup warning on stderr, so only stdout is compared.
check "codex_sandbox_bwrap_is_codex_bwrap_link" bash -c '
	[ "$(codex sandbox -- sh -c "command -v bwrap" 2>/dev/null)" = "$HOME/.local/share/codex-bwrap/bwrap" ]
'
check "codex_sandbox_bwrap_resolves_to_bundled" bash -c '
	target="$(codex sandbox -- sh -c "readlink -f \"\$(command -v bwrap)\"" 2>/dev/null)"
	case "$target" in
		"$HOME/.codex/packages/standalone/"*/codex-resources/bwrap) [ -f "$target" ] && [ -x "$target" ] ;;
		*) false ;;
	esac
'
check "codex_sandbox_keeps_usr_bin" bash -c '
	id_path="$(codex sandbox -- sh -c "command -v id" 2>/dev/null)"
	[ "$id_path" = "/usr/bin/id" ] || [ "$id_path" = "/bin/id" ]
'

reportResults
