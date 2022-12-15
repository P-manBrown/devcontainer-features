#!/usr/bin/env bash
set -eu

CONFIG_FILE_DIR="${CONFIGFILEDIR:-''}"
IGNORE_CONFIG_FILE="${IGNORECONFIGFILE:-'true'}"
INSTALL_SOLARGRAPH_RAILS="${INSTALLSOLARGRAPHRAILS:-'true'}"
SKIP_YARD_GEMS="${SKIPYARDGEMS:-'false'}"
SOLARGRAPH_VERSION="${SOLARGRAPHVERSION:-'latest'}"
SOLARGRAPH_RAILS_VERSION="${SOLARGRAPHRAILSVERSION:-'latest'}"

USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"
CONFIG_HOME="${XDG_CONFIG_HOME:-${USER_HOME}/.config}"
SOLARGRAPH_CONFIG_FILE="${CONFIG_FILE_DIR}/.solargraph.yml"

err() {
	printf '\e[31m%s\e[m\n' "$*" >&2
}

retry() {
	local cmd_status=1
	local retry_count=0
	local max_retry=3
	set +e
	until [[ ${cmd_status} -eq 0 ]] || [[ ${retry_count} -eq ${max_retry} ]]; do
		echo "Retry count: ${retry_count}"
		"$@"
		cmd_status=$?
		(( retry_count++ ))
		sleep 1
	done
	set -e
}

# Check
## Project root
if [[ -z "${CONFIG_FILE_DIR}" ]]; then
	message="$(
		cat <<-EOF
		--------------------------------------------------------
		  Config file directory is not set.
		  Set configFileDir in devcontainer.json.
		--------------------------------------------------------
		EOF
	)"
	err "${message}"
	exit 1
fi
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
## RubyGems
if ! gem --version > /dev/null 2>&1; then
	err "ERROR: Install 'RubyGems' before running this script."
	exit 1
fi

# Install Gems
## solargraph
echo 'Installing solargraph...'
if [[ "${SOLARGRAPH_VERSION}" == 'latest' ]]; then
	gem install solargraph
else
	gem install solargraph --version "${SOLARGRAPH_VERSION}"
fi
## solargraph-rails
if [[ "${INSTALL_SOLARGRAPH_RAILS}" == 'true' ]]; then
	echo 'Installing solargraph-rails...'
	if [[ "${SOLARGRAPH_RAILS_VERSION}" == 'latest' ]]; then
		gem install solargraph-rails
	else
		gem install solargraph-rails --version "${SOLARGRAPH_RAILS_VERSION}"
	fi
fi

# Set up solargraph
echo 'Setting up Solargraph...'
(
	HOME="${USER_HOME}"
	solargraph download-core
	touch "${HOME}/.gemrc"
	yard config --gem-install-yri
)
if [[ "${SKIP_YARD_GEMS}" == 'false' ]]; then
	retry yard gems --quiet
fi
if [[ ! -e "${SOLARGRAPH_CONFIG_FILE}" ]]; then
	solargraph config "${CONFIG_FILE_DIR}"
fi
if [[ "${INSTALL_SOLARGRAPH_RAILS}" == 'true' ]] \
	&& ! grep -q 'solargraph-rails' "${SOLARGRAPH_CONFIG_FILE}"; then
		sed -i \
			'/plugins:/s/\[]//; /plugins:/a - solargraph-rails' \
			"${SOLARGRAPH_CONFIG_FILE}"
fi

# Add the config file to gitignore
if [[ "${IGNORE_CONFIG_FILE}" == 'true' ]]; then
	git_global_config_dir="${CONFIG_HOME}/git"
	mkdir -p "${git_global_config_dir}"
	echo "${SOLARGRAPH_CONFIG_FILE}" >> "${git_global_config_dir}/ignore"
fi

# Change directory owner
if [[ "${USER_NAME}" != "root" ]]; then
	gem_dir="$(gem environment gemdir)"
	chown -R "${USER_NAME}" "${gem_dir}"
	solargraph_cache="${SOLARGRAPH_CACHE:-${USER_HOME}/.solargraph}"
	chown -R "${USER_NAME}" "${solargraph_cache}"
	chown "${USER_NAME}" "${SOLARGRAPH_CONFIG_FILE}"
	chown -R "${USER_NAME}" "${CONFIG_HOME}"
fi

echo "Done!!"
