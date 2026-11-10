#!/usr/bin/env bash
set -euo pipefail
source dev-container-features-test-lib
export PATH="/usr/local/share/bmad-feature/bin:$PATH"
check 'node' node --version
check 'python' python3 --version
check 'uv' uv --version
check 'git' git --version
check 'pinned_bmad' bash -c 'bmad --version | grep -F 6.12.4'
check 'state_path_safety' python3 "$(dirname "$0")/path-safety.py"
check 'real_installer_matrix_and_persistence' python3 "$(dirname "$0")/verify.py"
reportResults
