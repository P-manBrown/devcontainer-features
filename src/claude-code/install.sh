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
	curl -fsSL https://claude.ai/install.sh \
		| HOME="${USER_HOME}" bash -s -- "${VERSION}"
else
	curl -fsSL https://claude.ai/install.sh \
		| su -s /bin/bash \
			-c "HOME=$(printf '%q' "${USER_HOME}") bash -s -- $(printf '%q' "${VERSION}")" \
			"${USER_NAME}"
fi

ln -sf "${USER_HOME}/.local/bin/claude" /usr/local/bin/claude

# Pre-create the mount point owned by the target user. The entrypoint may
# run as a non-root user (e.g. when the base image sets USER), so it can't
# chown the volume itself; Docker copies this ownership into the named
# volume on its first mount, which is what makes that work.
mkdir -p /usr/local/share/claude-code-config
chown "${USER_NAME}" /usr/local/share/claude-code-config

# Create entrypoint
cat <<-EOF > /usr/local/share/claude-code.env
	USER_NAME="${USER_NAME}"
	USER_HOME="${USER_HOME}"
EOF
cat <<-'EOF' > /usr/local/share/claude-code-init.sh
	#!/usr/bin/env bash
	set -eu

	source /usr/local/share/claude-code.env

	CONFIG_ROOT="/usr/local/share/claude-code-config"
	VOLUME_CONFIG_DIR="${CONFIG_ROOT}/claude"
	VOLUME_CONFIG_FILE="${CONFIG_ROOT}/claude.json"
	HOME_CONFIG_DIR="${USER_HOME}/.claude"
	HOME_CONFIG_FILE="${USER_HOME}/.claude.json"

	err() {
		printf '\e[31m%s\e[m\n' "$*" >&2
	}

	migrate_config_dir() {
		if [[ -L "${HOME_CONFIG_DIR}" ]]; then
			return
		fi
		if [[ -e "${HOME_CONFIG_DIR}" ]] && [[ ! -d "${HOME_CONFIG_DIR}" ]]; then
			err "ERROR: ${HOME_CONFIG_DIR} exists but is not a directory; leaving it unchanged."
			return 1
		fi
		if [[ ! -d "${HOME_CONFIG_DIR}" ]]; then
			return
		fi
		if [[ -n "$(find "${VOLUME_CONFIG_DIR}" -mindepth 1 -print -quit)" ]]; then
			# The volume already holds data from a previous container;
			# the fresh install-time directory is disposable, so drop it
			# and let the volume win.
			rm -rf "${HOME_CONFIG_DIR}"
			return
		fi

		cp -a "${HOME_CONFIG_DIR}/." "${VOLUME_CONFIG_DIR}/"
		if ! diff -qr "${HOME_CONFIG_DIR}" "${VOLUME_CONFIG_DIR}" > /dev/null; then
			err "ERROR: Failed to verify the copy of ${HOME_CONFIG_DIR}; leaving the source unchanged."
			return 1
		fi
		rm -rf "${HOME_CONFIG_DIR}"
	}

	migrate_config_file() {
		if [[ -L "${HOME_CONFIG_FILE}" ]]; then
			return
		fi
		if [[ -e "${HOME_CONFIG_FILE}" ]] && [[ ! -f "${HOME_CONFIG_FILE}" ]]; then
			err "ERROR: ${HOME_CONFIG_FILE} exists but is not a regular file; leaving it unchanged."
			return 1
		fi
		if [[ ! -f "${HOME_CONFIG_FILE}" ]]; then
			return
		fi
		if [[ -e "${VOLUME_CONFIG_FILE}" ]]; then
			# The volume already holds a file from a previous container;
			# the fresh install-time file is disposable, so drop it and
			# let the volume win.
			rm -f "${HOME_CONFIG_FILE}"
			return
		fi

		cp -a "${HOME_CONFIG_FILE}" "${VOLUME_CONFIG_FILE}"
		if ! cmp -s "${HOME_CONFIG_FILE}" "${VOLUME_CONFIG_FILE}"; then
			err "ERROR: Failed to verify the copy of ${HOME_CONFIG_FILE}; leaving the source unchanged."
			return 1
		fi
		rm -f "${HOME_CONFIG_FILE}"
	}

	mkdir -p "${VOLUME_CONFIG_DIR}"
	migrate_config_dir
	migrate_config_file
	touch "${VOLUME_CONFIG_FILE}"
	chmod 600 "${VOLUME_CONFIG_FILE}"
	chown -R "${USER_NAME}" "${CONFIG_ROOT}"
	chmod 700 "${CONFIG_ROOT}"

	ln -sfn "${VOLUME_CONFIG_DIR}" "${HOME_CONFIG_DIR}"
	ln -sfn "${VOLUME_CONFIG_FILE}" "${HOME_CONFIG_FILE}"
EOF
chmod +x /usr/local/share/claude-code-init.sh

echo "Done!"
