#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "bru_version" bru --version
# npm should still be the one the node feature installed via nvm, proving
# the Node.js fallback in install.sh was skipped rather than overwriting it.
check "npm_from_nvm" bash -c 'command -v npm | grep -q nvm'

# Report result
reportResults
