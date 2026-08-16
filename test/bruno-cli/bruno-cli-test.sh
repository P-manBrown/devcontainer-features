#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "bru_version" bru --version
# The Node.js fallback extracts an upstream tarball into /usr/local; without
# --no-same-owner, tar restores the archive's original uid/gid and corrupts
# ownership of shared directories like /usr/local/bin and /usr/local/share.
check "usr_local_bin_owned_by_root" bash -c '[ "$(stat -c %U /usr/local/bin)" = "root" ]'
check "usr_local_share_owned_by_root" bash -c '[ "$(stat -c %U /usr/local/share)" = "root" ]'

# Report result
reportResults
