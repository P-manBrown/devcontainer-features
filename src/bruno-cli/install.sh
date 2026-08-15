#!/usr/bin/env bash
set -eu

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
## npm
if ! npm --version > /dev/null 2>&1; then
	err "ERROR: Install 'npm' before running this script."
	exit 1
fi

# Install
if [[ "${VERSION}" == "latest" ]]; then
	npm install -g @usebruno/cli
else
	npm install -g "@usebruno/cli@${VERSION}"
fi

echo "Installed: $(bru --version)"
