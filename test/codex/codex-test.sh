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

# Report result
reportResults
