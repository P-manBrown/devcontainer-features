#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

install_dir="/usr/local/share/openpencil"
port=7391
work_dir="$(mktemp -d)"
trap 'op stop > /dev/null 2>&1 || true; rm -rf "${work_dir}"' EXIT

op_version() {
	op --version | grep -qF '0.8.5'
}
desktop_bin_env() {
	[[ "${OPENPENCIL_DESKTOP_BIN:-}" == "${install_dir}/openpencil-desktop" ]] \
		&& [[ -x "${OPENPENCIL_DESKTOP_BIN}" ]]
}
no_missing_libraries() {
	local bin output
	for bin in "${install_dir}/op" "${install_dir}/openpencil-desktop"; do
		output="$(ldd "${bin}")" || return
		if grep -q 'not found' <<< "${output}"; then
			printf '%s\n' "${output}" >&2
			return 1
		fi
	done
}
headless_start() {
	timeout 120 op --port "${port}" start --headless --file "${work_dir}/t.op"
}
headless_status() {
	local attempt
	for attempt in $(seq 1 30); do
		if op --port "${port}" status | grep -qE '"running"[[:space:]]*:[[:space:]]*true'; then
			return 0
		fi
		sleep 1
	done
	op --port "${port}" status >&2 || true
	return 1
}
headless_tools() {
	local output
	output="$(op --port "${port}" tools)" || return
	grep -qF '"name"' <<< "${output}"
}

# Definition specific tests
check "op_version" op_version
check "desktop_bin_env" desktop_bin_env
check "no_missing_libraries" no_missing_libraries
check "font_notices" test -f "${install_dir}/font-notices/NOTICE.txt"
check "headless_start" headless_start
check "headless_status_running" headless_status
check "headless_tools" headless_tools
check "headless_stop" op stop

# Report result
reportResults
