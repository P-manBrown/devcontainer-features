#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "codex_version" codex --version
check "unshare_user_ns" unshare --user --map-root-user true

# Report result
reportResults
