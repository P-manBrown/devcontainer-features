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
check "codex_bwrap_dir_holds_only_bundled_copy" bash -c '
	dir="/tmp/codex-bwrap-$(id -u)"
	bundled="$HOME/.codex/packages/standalone/current/codex-resources/bwrap"
	[ "$(ls -A "$dir")" = "bwrap" ] \
		&& [ -f "$dir/bwrap" ] && [ ! -L "$dir/bwrap" ] \
		&& [ -x "$dir/bwrap" ] \
		&& cmp -s "$dir/bwrap" "$bundled"
'
check "no_build_time_bwrap_dir" test ! -e /usr/local/share/codex-bwrap
check "no_bwrap_from_home_on_user_path" bash -c '
	path="$(bash -lc "command -v bwrap" || true)"
	case "$path" in
		"$HOME"/*) false ;;
		*) true ;;
	esac
'
# The following run inside Codex's own process tree. Codex prints a stale
# arg0 cleanup warning on stderr, so only stdout is compared.
check "codex_sandbox_bwrap_is_codex_bwrap" bash -c '
	[ "$(codex sandbox -- sh -c "command -v bwrap" 2>/dev/null)" = "/tmp/codex-bwrap-$(id -u)/bwrap" ]
'
check "codex_sandbox_bwrap_matches_bundled" bash -c '
	bundled="$HOME/.codex/packages/standalone/current/codex-resources/bwrap"
	target="$(codex sandbox -- sh -c "readlink -f \"\$(command -v bwrap)\"" 2>/dev/null)"
	[ "$target" = "/tmp/codex-bwrap-$(id -u)/bwrap" ] && [ -x "$target" ] && cmp -s "$target" "$bundled"
'
# Which bwrap Codex itself executes, not just what its child sees on PATH.
# A recording probe stands in for a system bwrap behind the wrapper's
# directory; it must never be called. Codex skips a PATH bwrap whose real
# path is under its working directory, so run from $HOME and /workspaces,
# where the copy under /tmp is used.
for dir in "$HOME" /workspaces; do
	[ -d "$dir" ] || continue
	check "codex_runs_bundled_bwrap_from_${dir//\//_}" bash -c '
		probe="$(mktemp -d)"
		printf "#!/bin/sh\ntouch \"%s/called\"\nexec \"%s\" \"\$@\"\n" "$probe" "$HOME/.codex/packages/standalone/current/codex-resources/bwrap" > "$probe/bwrap"
		chmod +x "$probe/bwrap"
		(cd "$1" && PATH="$PATH:$probe" codex sandbox -- true > /dev/null 2>&1)
		status=0
		[ -e "$probe/called" ] && status=1
		rm -rf "$probe"
		exit "$status"
	' _ "$dir"
done
check "codex_sandbox_keeps_usr_bin" bash -c '
	id_path="$(codex sandbox -- sh -c "command -v id" 2>/dev/null)"
	[ "$id_path" = "/usr/bin/id" ] || [ "$id_path" = "/bin/id" ]
'

# Report result
reportResults
