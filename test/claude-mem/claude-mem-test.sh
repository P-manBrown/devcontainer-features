#!/bin/bash
set -e

source dev-container-features-test-lib

check "claude_mem_version" claude-mem --version

reportResults
