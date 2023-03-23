#!/usr/bin/env bash
set -eu

USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"

GITIGNORE_LOCAL_CONFIG="${GITIGNORECONFIGFILE:-"true"}"
INSTALL_SOLARGRAPH_RAILS="${INSTALLSOLARGRAPHRAILS:-"true"}"
LOCAL_CONFIG_DIR="${LOCALCONFIGDIR:-"global"}"
SKIP_YARD_GEMS="${SKIPYARDGEMS:-"false"}"
SOLARGRAPH_VERSION="${SOLARGRAPHVERSION:-"latest"}"
SOLARGRAPH_RAILS_VERSION="${SOLARGRAPHRAILSVERSION:-"latest"}"

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
## Ruby
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
mkdir -p /tmp/solargraph
solargraph config /tmp/solargraph
if [[ "${INSTALL_SOLARGRAPH_RAILS}" == 'true' ]] \
	&& ! grep -q 'solargraph-rails' /tmp/solargraph/.solargraph.yml; then
		sed -i \
		'/plugins:/s/\[]//; /plugins:/a - solargraph-rails' \
		/tmp/solargraph/.solargraph.yml
fi

# Change directory owner
if [[ "${USER_NAME}" != "root" ]]; then
	gem_dir="$(gem environment gemdir)"
	chown -R "${USER_NAME}" "${gem_dir}"
	chown -R "${USER_NAME}" "${USER_HOME}/.solargraph"
	chown "${USER_NAME}" "${USER_HOME}/.gemrc"
	chown -R "${USER_NAME}" /tmp/solargraph
fi

# Create entrypoint
cat <<-EOF > /usr/local/share/solargrah.env
	USER_NAME="${USER_NAME}"
	USER_HOME="${USER_HOME}"
	GITIGNORE_LOCAL_CONFIG="${GITIGNORE_LOCAL_CONFIG}"
	LOCAL_CONFIG_DIR="${LOCAL_CONFIG_DIR}"
EOF
cat <<-'EOF' > /usr/local/share/solargraph-init.sh
	#!/usr/bin/env bash
	set -eu

	source /usr/local/share/solargrah.env

	mkdir_and_chown() {
	  dir_name="$1"
	  if [[ ! -e "${dir_name}" ]]; then
	    mkdir -pv "${dir_name}" \
	      | grep -m 1 -Eo "'.+'" \
	      | tr -d "'" \
	      | xargs chown -R "${USER_NAME}"
	  fi
	}

	# Move cached files
	set +u
	if [[ -n "${SOLARGRAPH_CACHE}" ]]; then
	  mkdir_and_chown "${SOLARGRAPH_CACHE}"
	  cp -n "${USER_HOME}/.solargraph/cache"/* "${SOLARGRAPH_CACHE}"
	  rm -fr "${USER_HOME}/.solargraph"
	fi
	set -u

	# Move config file
	if [[ "${LOCAL_CONFIG_DIR}" == 'global' ]]; then
	  global_config_default="${USER_HOME}/.config/solargraph/config.yml"
	  global_config="${SOLARGRAPH_GLOBAL_CONFIG:-${global_config_default}}"
	  mkdir_and_chown "${global_config%/*.yml}"
	  cp -n "/tmp/solargraph/.solargraph.yml" "${global_config}"
	else
	  mkdir_and_chown "${LOCAL_CONFIG_DIR}"
	  cp -n "/tmp/solargraph/.solargraph.yml" "${LOCAL_CONFIG_DIR}"
	  cd "${LOCAL_CONFIG_DIR}"
	  git_exclude="$(git rev-parse --git-path info/exclude)"
	  if [[ "${GITIGNORE_LOCAL_CONFIG}" == 'true' ]] \
	    && ! grep -q '.solargraph.yml' "${git_exclude}"; then
	      echo '.solargraph.yml' >> "${git_exclude}"
	  fi
	fi
EOF
chmod +x /usr/local/share/solargraph-init.sh

echo "Done!!"
