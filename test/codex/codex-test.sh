#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "codex_version" codex --version
check "bwrap_installed" bwrap --version
check "unshare_user_ns" unshare --user --map-root-user true
check "bwrap_user_ns" bwrap --ro-bind / / true

# Report result
reportResults
