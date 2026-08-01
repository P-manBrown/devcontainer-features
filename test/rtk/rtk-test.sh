#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "rtk_version" rtk --version

# Report result
reportResults
