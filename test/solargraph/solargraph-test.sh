#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "solargraph_version" solargraph --version
check "solargraph-rails_version" gem list solargraph-rails
check "config_file" test -e /home/vscode/.solargraph.yml
check "git_global_ignore" test -e /home/vscode/.config/git/ignore

# Report result
reportResults
