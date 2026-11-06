#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Each scenario runs in one container, so a rebuild is simulated by
# putting ~/.codex into the state a new image would leave and rerunning
# the start script, which is what runs on every container start.
CONFIG_ROOT="/usr/local/share/codex-config"
VOLUME_CODEX_DIR="${CONFIG_ROOT}/codex"
USER_STATE_NAMES="auth.json config.toml history.jsonl session_index.jsonl sessions archived_sessions log"

# The start script runs as part of the container's startup, possibly
# after this test begins; wait for its link instead of racing it.
timeout 60 bash -c 'until [ -L "${HOME}/.codex" ]; do sleep 1; done' || true

# Runs the start script and keeps its output and exit status, so a
# failing run is reported by the checks below instead of ending the test.
run_init() {
	if INIT_OUTPUT="$(sudo /usr/local/share/codex-init.sh 2>&1)"; then
		INIT_STATUS=0
	else
		INIT_STATUS=$?
	fi
	printf '%s\n' "${INIT_OUTPUT}"
}

# Logs in with a dummy API key so Codex writes auth.json itself. If that
# does not leave the key in ~/.codex/auth.json (for example because the
# command needs the network), write the file the way Codex saves it: a
# temp file in ~/.codex renamed over auth.json.
login() {
	local key="$1"
	local tmp
	if printf '%s' "${key}" | codex login --with-api-key > /dev/null 2>&1 \
		&& grep -qF "${key}" "${HOME}/.codex/auth.json" 2> /dev/null; then
		echo "Logged in with codex login --with-api-key."
		return
	fi
	echo "codex login --with-api-key did not store the key; writing auth.json by rename."
	tmp="$(mktemp "${HOME}/.codex/auth.json.XXXXXX")"
	printf '{"OPENAI_API_KEY":"%s"}\n' "${key}" > "${tmp}"
	mv "${tmp}" "${HOME}/.codex/auth.json"
}

logout() {
	codex logout > /dev/null 2>&1 || true
	rm -f "${HOME}/.codex/auth.json"
}

# The login is readable through ~/.codex and stored in the volume.
login_is() {
	grep -qF "$1" "${HOME}/.codex/auth.json" \
		&& grep -qF "$1" "${VOLUME_CODEX_DIR}/auth.json" \
		&& cmp -s "${HOME}/.codex/auth.json" "${VOLUME_CODEX_DIR}/auth.json"
}

home_codex_is_volume_link() {
	[ -L "${HOME}/.codex" ] && [ "$(readlink "${HOME}/.codex")" = "${VOLUME_CODEX_DIR}" ]
}

init_succeeded() {
	[ "${INIT_STATUS}" -eq 0 ]
}

init_failed() {
	[ "${INIT_STATUS}" -ne 0 ]
}

init_output_has() {
	grep -qF -- "$1" <<< "${INIT_OUTPUT}"
}

content_is() {
	[ "$(cat "$1")" = "$2" ]
}

# What a new image's ~/.codex can hold before the start script runs.
fresh_home_codex() {
	rm -rf "${HOME}/.codex"
	mkdir -p "${HOME}/.codex/skills/x"
	printf 'image agents\n' > "${HOME}/.codex/AGENTS.md"
	printf 'image skill\n' > "${HOME}/.codex/skills/x/SKILL.md"
}

snapshot() {
	sudo bash -c 'cd /usr/local/share/codex-config \
		&& find . -printf "%p %y %u %m %l\n" | sort \
		&& find . -type f -exec sha256sum {} + | sort'
	readlink "${HOME}/.codex"
}

# Case 1: first creation
check "home_codex_links_to_volume" home_codex_is_volume_link
check "config_root_owned_by_user_mode_700" bash -c \
	'[ "$(stat -c "%U %a" /usr/local/share/codex-config)" = "$(id -un) 700" ]'
check "codex_binary_in_image" bash -c \
	'case "$(readlink -f "${HOME}/.local/bin/codex")" in "${HOME}/.local/share/codex/"*) true ;; *) false ;; esac'
check "usr_local_bin_codex_links_user_bin" bash -c \
	'[ "$(readlink /usr/local/bin/codex)" = "${HOME}/.local/bin/codex" ]'
check "no_packages_in_volume" bash -c '[ ! -e /usr/local/share/codex-config/codex/packages ]'
check "codex_home_not_set" bash -c '[ -z "${CODEX_HOME:-}" ]'
check "codex_version_after_start" codex --version
login "sk-test-dummy-a"
check "case1_login_in_volume" login_is "sk-test-dummy-a"

# Case 2: rebuild with an existing volume. The volume already holds a
# file the image lacks and an older copy of an image file.
mkdir -p "${VOLUME_CODEX_DIR}/skills/keep"
printf 'keep\n' > "${VOLUME_CODEX_DIR}/skills/keep/SKILL.md"
printf 'old agents\n' > "${VOLUME_CODEX_DIR}/AGENTS.md"
fresh_home_codex
printf '{"OPENAI_API_KEY":"sk-test-image"}\n' > "${HOME}/.codex/auth.json"
run_init
check "case2_init_succeeds" init_succeeded
check "case2_link_restored" home_codex_is_volume_link
check "case2_volume_login_kept" login_is "sk-test-dummy-a"
check "case2_warns_ignored_auth" init_output_has "WARNING: Ignored ${HOME}/.codex/auth.json"
check "case2_image_file_replaces_old_copy" content_is "${HOME}/.codex/AGENTS.md" "image agents"
check "case2_image_dir_visible" content_is "${HOME}/.codex/skills/x/SKILL.md" "image skill"
check "case2_volume_only_file_kept" content_is "${HOME}/.codex/skills/keep/SKILL.md" "keep"

# Case 3: auth.json replaced by rename after login
tmp="$(mktemp "${HOME}/.codex/auth.json.XXXXXX")"
printf '{"OPENAI_API_KEY":"sk-test-dummy-renamed"}\n' > "${tmp}"
mv "${tmp}" "${HOME}/.codex/auth.json"
check "case3_rename_resolves_into_volume" bash -c \
	'[ "$(readlink -f "${HOME}/.codex/auth.json")" = /usr/local/share/codex-config/codex/auth.json ]'
check "case3_volume_has_new_login" login_is "sk-test-dummy-renamed"

# Case 4: logout, login with another key, then a rebuild
logout
check "case4_logout_removes_volume_login" bash -c '[ ! -e /usr/local/share/codex-config/codex/auth.json ]'
login "sk-test-dummy-b"
fresh_home_codex
run_init
check "case4_init_succeeds" init_succeeded
check "case4_second_login_kept" login_is "sk-test-dummy-b"
check "case4_first_login_not_back" bash -c '! grep -qF sk-test-dummy-a "${HOME}/.codex/auth.json"'

# Case 5: migration from the 3.0.0 layout (files at the top of the
# volume, ~/.codex a real directory of per-file links into it)
mkdir -p "${VOLUME_CODEX_DIR}/sessions/2026"
printf 'session\n' > "${VOLUME_CODEX_DIR}/sessions/2026/s.jsonl"
printf 'history\n' > "${VOLUME_CODEX_DIR}/history.jsonl"
rm "${HOME}/.codex"
sudo find "${VOLUME_CODEX_DIR}" -mindepth 1 -maxdepth 1 -exec mv -t "${CONFIG_ROOT}" {} +
sudo rmdir "${VOLUME_CODEX_DIR}"
mkdir "${HOME}/.codex"
for name in ${USER_STATE_NAMES}; do
	ln -s "${CONFIG_ROOT}/${name}" "${HOME}/.codex/${name}"
done
run_init
check "case5_init_succeeds" init_succeeded
check "case5_link_restored" home_codex_is_volume_link
check "case5_login_kept" login_is "sk-test-dummy-b"
check "case5_sessions_moved" content_is "${VOLUME_CODEX_DIR}/sessions/2026/s.jsonl" "session"
check "case5_history_moved" content_is "${VOLUME_CODEX_DIR}/history.jsonl" "history"
check "case5_top_level_only_codex" bash -c '[ "$(sudo ls -A /usr/local/share/codex-config)" = codex ]'
check "case5_no_dangling_links" bash -c '[ -z "$(find /usr/local/share/codex-config/codex -xtype l)" ]'

# A 3.0.0 leftover whose name already exists in codex/ is kept and reported.
printf '{"OPENAI_API_KEY":"sk-test-leftover"}\n' | sudo tee "${CONFIG_ROOT}/auth.json" > /dev/null
run_init
check "leftover_init_succeeds" init_succeeded
check "leftover_kept" bash -c 'sudo grep -qF sk-test-leftover /usr/local/share/codex-config/auth.json'
check "leftover_warns" init_output_has "WARNING: Left ${CONFIG_ROOT}/auth.json in place"
check "leftover_volume_login_unchanged" login_is "sk-test-dummy-b"
sudo rm "${CONFIG_ROOT}/auth.json"

# A ~/.codex link the user points elsewhere is left alone, and the volume
# is still owned by the user with mode 700.
rm "${HOME}/.codex"
mkdir -p /tmp/other-codex
ln -s /tmp/other-codex "${HOME}/.codex"
sudo chown root "${CONFIG_ROOT}"
sudo chmod 755 "${CONFIG_ROOT}"
run_init
check "user_link_init_succeeds" init_succeeded
check "user_link_unchanged" bash -c '[ "$(readlink "${HOME}/.codex")" = /tmp/other-codex ]'
check "user_link_warns" init_output_has "is a symlink to /tmp/other-codex"
check "user_link_volume_owner_and_mode" bash -c \
	'[ "$(sudo stat -c "%U %a" /usr/local/share/codex-config)" = "$(id -un) 700" ]'
rm "${HOME}/.codex"

# A ~/.codex that is not a directory stops the start with an error.
printf 'not a directory\n' > "${HOME}/.codex"
run_init
check "not_dir_init_fails" init_failed
check "not_dir_error" init_output_has "exists but is not a directory"
check "not_dir_unchanged" content_is "${HOME}/.codex" "not a directory"
rm "${HOME}/.codex"

# A codex.restore left by an interrupted codebase-memory-mcp restore is not
# moved into the volume; that feature removes it on its next run.
sudo mkdir "${CONFIG_ROOT}/codex.restore"
printf 'partial\n' | sudo tee "${CONFIG_ROOT}/codex.restore/partial.jsonl" > /dev/null
run_init
check "restore_leftover_init_succeeds" init_succeeded
check "restore_leftover_not_moved" bash -c \
	'sudo test -f /usr/local/share/codex-config/codex.restore/partial.jsonl && ! sudo test -e /usr/local/share/codex-config/codex/codex.restore'
sudo rm -rf "${CONFIG_ROOT}/codex.restore"

# A missing ~/.codex gets the link again, and further starts change nothing.
rm -f "${HOME}/.codex"
run_init
check "missing_init_succeeds" init_succeeded
check "missing_link_created" home_codex_is_volume_link
before="$(snapshot)"
run_init
run_init
after="$(snapshot)"
check "idempotent" [ "${before}" = "${after}" ]

# Report result
reportResults
