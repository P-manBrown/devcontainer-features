#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "codebase_memory_mcp_version" codebase-memory-mcp --version

# Report result
reportResults
