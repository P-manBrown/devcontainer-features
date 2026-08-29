#!/usr/bin/env bash
set -eu

USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"

VERSION="${VERSION:-"latest"}"

err() {
	printf '\e[31m%s\e[m\n' "$*" >&2
}

# Check
## User
if [[ "$(id -u)" -ne 0 ]]; then
	message="$(
		cat <<-EOF
		--------------------------------------------------------
		  Script must be run as root.
		  Use sudo, su, or add "USER root" to your Dockerfile.
		--------------------------------------------------------
		EOF
	)"
	err "${message}"
	exit 1
fi
## curl
if ! curl --version > /dev/null 2>&1; then
	err "ERROR: Install 'curl' before running this script."
	exit 1
fi

# Install
if [[ "${USER_NAME}" == "root" ]]; then
	curl -fsSL https://chatgpt.com/codex/install.sh \
		| HOME="${USER_HOME}" CODEX_NON_INTERACTIVE=true \
			sh -s -- --release "${VERSION}"
else
	curl -fsSL https://chatgpt.com/codex/install.sh \
		| su -s /bin/sh \
			-c "HOME=$(printf '%q' "${USER_HOME}") CODEX_NON_INTERACTIVE=true sh -s -- --release $(printf '%q' "${VERSION}")" \
			"${USER_NAME}"
fi

ln -sf "${USER_HOME}/.local/bin/codex" /usr/local/bin/codex

# Pre-create the mount point owned by the target user. The entrypoint may
# run as a non-root user (e.g. when the base image sets USER), so it can't
# chown the volume itself; Docker copies this ownership into the named
# volume on its first mount, which is what makes that work.
mkdir -p /usr/local/share/codex-config
chown "${USER_NAME}" /usr/local/share/codex-config

# Create entrypoint
cat <<-EOF > /usr/local/share/codex.env
	USER_NAME="${USER_NAME}"
	USER_HOME="${USER_HOME}"
EOF
cat <<-'EOF' > /usr/local/share/codex-init.sh
	#!/usr/bin/env bash
	set -eu

	source /usr/local/share/codex.env

	CONFIG_ROOT="/usr/local/share/codex-config"
	HOME_CODEX_DIR="${USER_HOME}/.codex"
	PERSISTENT_DIRS="sessions archived_sessions log"
	PERSISTENT_FILES="auth.json config.toml history.jsonl session_index.jsonl"

	err() {
		printf '\e[31m%s\e[m\n' "$*" >&2
	}

	migrate_config_dir() {
		name="$1"
		home_path="${HOME_CODEX_DIR}/${name}"
		volume_path="${CONFIG_ROOT}/${name}"

		if [[ -L "${home_path}" ]]; then
			return
		fi
		if [[ -e "${home_path}" ]] && [[ ! -d "${home_path}" ]]; then
			err "ERROR: ${home_path} exists but is not a directory; leaving it unchanged."
			return 1
		fi
		mkdir -p "${volume_path}"
		if [[ -d "${home_path}" ]]; then
			if [[ -n "$(find "${volume_path}" -mindepth 1 -print -quit)" ]]; then
				# The volume already holds data from a previous container;
				# discard the fresh container-local state and let it win.
				rm -rf "${home_path}"
			else
				cp -a "${home_path}/." "${volume_path}/"
				if ! diff -qr "${home_path}" "${volume_path}" > /dev/null; then
					err "ERROR: Failed to verify the copy of ${home_path}; leaving the source unchanged."
					return 1
				fi
				rm -rf "${home_path}"
			fi
		fi

		ln -sfn "${volume_path}" "${home_path}"
	}

	migrate_config_file() {
		name="$1"
		home_path="${HOME_CODEX_DIR}/${name}"
		volume_path="${CONFIG_ROOT}/${name}"

		if [[ -L "${home_path}" ]]; then
			return
		fi
		if [[ -e "${home_path}" ]] && [[ ! -f "${home_path}" ]]; then
			err "ERROR: ${home_path} exists but is not a regular file; leaving it unchanged."
			return 1
		fi
		if [[ -f "${home_path}" ]]; then
			if [[ -e "${volume_path}" ]]; then
				# The volume already holds data from a previous container;
				# discard the fresh container-local state and let it win.
				rm -f "${home_path}"
			else
				cp -a "${home_path}" "${volume_path}"
				if ! cmp -s "${home_path}" "${volume_path}"; then
					err "ERROR: Failed to verify the copy of ${home_path}; leaving the source unchanged."
					return 1
				fi
				rm -f "${home_path}"
			fi
		fi

		ln -sfn "${volume_path}" "${home_path}"
	}

	mkdir -p "${HOME_CODEX_DIR}"
	for name in ${PERSISTENT_DIRS}; do
		migrate_config_dir "${name}"
	done
	for name in ${PERSISTENT_FILES}; do
		migrate_config_file "${name}"
	done
	chown -R "${USER_NAME}" "${CONFIG_ROOT}"
	chmod 700 "${CONFIG_ROOT}"
EOF
chmod +x /usr/local/share/codex-init.sh

echo "Done!"
