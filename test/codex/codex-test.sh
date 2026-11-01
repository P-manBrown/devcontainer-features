#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "codex_version" codex --version
check "unshare_user_ns" unshare --user --map-root-user true
check "bundled_bwrap_user_ns" bash -c '
	bwrap="$(find "$HOME/.codex/packages/standalone" -type f -path "*/codex-resources/bwrap" 2>/dev/null | head -1)"
	[ -n "$bwrap" ] && "$bwrap" --unshare-all --ro-bind / / true
'
check "codex_bwrap_dir_holds_only_link" bash -c '
	dir="$HOME/.local/share/codex-bwrap"
	[ "$(ls -A "$dir")" = "bwrap" ] \
		&& [ -L "$dir/bwrap" ] \
		&& [ "$(readlink "$dir/bwrap")" = "$HOME/.codex/packages/standalone/current/codex-resources/bwrap" ] \
		&& [ -x "$dir/bwrap" ]
'
check "codex_bwrap_dir_owned_by_user" bash -c '
	user="$(id -un)"
	[ "$(stat -c %U "$HOME/.local/share")" = "$user" ] \
		&& [ "$(stat -c %U "$HOME/.local/share/codex-bwrap")" = "$user" ] \
		&& [ "$(stat -c %U "$HOME/.local/share/codex-bwrap/bwrap")" = "$user" ]
'
check "no_bwrap_from_home_on_user_path" bash -c '
	path="$(bash -lc "command -v bwrap" || true)"
	case "$path" in
		"$HOME"/*) false ;;
		*) true ;;
	esac
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

# Report result
reportResults
