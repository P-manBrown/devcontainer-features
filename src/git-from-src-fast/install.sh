#!/usr/bin/env bash
#-------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Modifications Copyright (c) P-manBrown<https://github.com/P-manBrown>
# Licensed under the MIT License.
# See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------

set -e

GIT_VERSION=${VERSION}

# Check
## User
if [ "$(id -u)" -ne 0 ]; then
	cat <<-EOF
		--------------------------------------------------------
		  Script must be run as root.
		  Use sudo, su, or add "USER root" to your Dockerfile.
		--------------------------------------------------------
	EOF
	exit 1
fi
## OS
### Source /etc/os-release to get OS info
. /etc/os-release
if [ "${ID}" = "ubuntu" ]; then
	cat <<-EOF
		---------------------------------------------------------------------
		  Use 'ghcr.io/devcontainers/features/git' instead of this feature.
		  The above feature can use PPAs.
		---------------------------------------------------------------------
	EOF
	exit 1
fi

# Clean up
rm -rf /var/lib/apt/lists/*

apt_get_update() {
	if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
		echo "Running apt-get update..."
		apt-get update -y
	fi
}

check_packages() {
	if ! dpkg -s "$@" > /dev/null 2>&1; then
		apt_get_update
		apt-get -y install --no-install-recommends "$@"
	fi
}

export DEBIAN_FRONTEND=noninteractive

# Partial version matching
if [ "$(echo "${GIT_VERSION}" | grep -o '\.' | wc -l)" != "2" ]; then
	requested_version="${GIT_VERSION}"
	version_list="$(
		curl -sSL -H "Accept: application/vnd.github.v3+json" \
			"https://api.github.com/repos/git/git/tags" \
		| grep -oP '"name":\s*"v\K[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -rV
	)"
	if [ "${requested_version}" = "latest" ]; then
		GIT_VERSION="$(echo "${version_list}" | head -n 1)"
	else
		set +e
		GIT_VERSION="$(
			echo "${version_list}" \
			| grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)"
		)"
		set -e
	fi
	if [ -z "${GIT_VERSION}" ] \
		|| ! echo "${version_list}"| grep -q "^${GIT_VERSION//./\\.}$"
	then
		printf "\e[31m%s\e[m\n" "Invalid git version: ${requested_version}" >&2
		exit 1
	fi
fi

# Check that the requested version is not already installed
set +e
if [[ "$(git --version)" =~ "${GIT_VERSION}" ]]; then
	printf "\e[31m%s\e[m\n" "Git(v${GIT_VERSION}) is already installed."
	exit 1
fi
set -e

# Install required packages to build if missing
check_packages \
	build-essential \
	curl \
	ca-certificates \
	tar \
	gettext \
	libssl-dev \
	zlib1g-dev \
	libcurl?-openssl-dev \
	libexpat1-dev

# Install Git
echo "Downloading source for ${GIT_VERSION}..."
curl -sL https://github.com/git/git/archive/v${GIT_VERSION}.tar.gz \
| tar -xzC /tmp 2>&1
echo "Building..."
cd /tmp/git-${GIT_VERSION}
make -s prefix=/usr/local all -j "$(nproc)" \
&& make -s prefix=/usr/local install 2>&1
rm -rf /tmp/git-${GIT_VERSION}
rm -rf /var/lib/apt/lists/*
echo "Done!"
