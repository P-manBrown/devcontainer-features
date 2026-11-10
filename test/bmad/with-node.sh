#!/usr/bin/env bash
set -euo pipefail
source dev-container-features-test-lib
export PATH="/usr/local/share/bmad-feature/bin:$PATH"
check 'node' node --version
check 'python' python3 --version
check 'uv' uv --version
check 'git' git --version
check 'selected_bmad' python3 -c 'import json, subprocess; expected=json.load(open("/usr/local/share/bmad-feature/options.json"))["bmad"]; assert subprocess.check_output(["bmad", "--version"], text=True).strip().lstrip("v") == expected'
check 'state_path_safety' python3 "$(dirname "$0")/path-safety.py"
check 'real_installer_matrix_and_persistence' python3 "$(dirname "$0")/verify.py"
check 'reuse_node' bash -c 'test ! -d /usr/local/share/bmad-feature/node'
reportResults
