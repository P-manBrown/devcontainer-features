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
			-c "HOME='${USER_HOME}' bash -s -- '${VERSION}'" \
			"${USER_NAME}"
fi

ln -sf "${USER_HOME}/.local/bin/claude" /usr/local/bin/claude

echo "Done!"
