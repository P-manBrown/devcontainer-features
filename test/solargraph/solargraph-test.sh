#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "solargraph_version" solargraph --version
check "solargraph-rails_version" gem list solargraph-rails
global_config="/home/vscode/.config/solargraph/config.yml"
check "config_file" test -e "${global_config}"
check "config_file_rails" grep -q 'solargraph-rails' "${global_config}"

# Report result
reportResults
