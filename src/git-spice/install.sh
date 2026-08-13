#!/usr/bin/env bash
set -eu

USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"

VERSION="${VERSION:-"latest"}"
INSTALL_GS_ALIAS="${INSTALLGSALIAS:-"true"}"

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

# Detect architecture
case "$(uname -m)" in
	x86_64)
		arch="x86_64"
		;;
	aarch64|arm64)
		arch="aarch64"
		;;
	*)
		err "ERROR: Unsupported architecture: $(uname -m)"
		exit 1
		;;
esac

# Resolve version
if [[ "${VERSION}" == "latest" ]]; then
	release_json="$(curl -fsSL "https://api.github.com/repos/abhinav/git-spice/releases/latest")"
	if ! VERSION="$(
		printf '%s' "${release_json}" \
			| grep -m 1 -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' \
			| sed -E 's/.*"v([^"]+)"/\1/'
	)" || [[ -z "${VERSION}" ]]; then
		err "ERROR: Failed to resolve the latest git-spice version."
		exit 1
	fi
else
	VERSION="${VERSION#v}"
fi

# Download and verify
asset="git-spice.Linux-${arch}.tar.gz"
download_url="https://github.com/abhinav/git-spice/releases/download/v${VERSION}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

curl -fsSL "${download_url}/${asset}" -o "${tmp_dir}/${asset}"
curl -fsSL "${download_url}/checksums.txt" -o "${tmp_dir}/checksums.txt"

if ! checksum_line="$(
	grep -E "^[[:xdigit:]]{64}  ${asset//./\\.}$" "${tmp_dir}/checksums.txt"
)"; then
	err "ERROR: Checksum not found for ${asset}."
	exit 1
fi
printf '%s\n' "${checksum_line}" | (cd "${tmp_dir}" && sha256sum -c -)

# Install
tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}"
install -m 0755 "${tmp_dir}/git-spice" /usr/local/bin/git-spice

if [[ "${INSTALL_GS_ALIAS}" == "true" ]]; then
	ln -sf /usr/local/bin/git-spice /usr/local/bin/gs
fi

# Pre-create the mount point owned by the target user. The entrypoint may
# run as a non-root user (e.g. when the base image sets USER), so it can't
# chown the volume itself; Docker copies this ownership into the named
# volume on its first mount, which is what makes that work.
mkdir -p /usr/local/share/git-spice-config
chown "${USER_NAME}" /usr/local/share/git-spice-config

# Create entrypoint
cat <<-EOF > /usr/local/share/git-spice.env
	USER_NAME="${USER_NAME}"
	USER_HOME="${USER_HOME}"
EOF
cat <<-'EOF' > /usr/local/share/git-spice-init.sh
	#!/usr/bin/env bash
	set -eu

	source /usr/local/share/git-spice.env

	CONFIG_ROOT="/usr/local/share/git-spice-config"
	HOME_GIT_SPICE_DIR="${USER_HOME}/.config/git-spice"
	PERSISTENT_FILE="secrets.json"

	err() {
		printf '\e[31m%s\e[m\n' "$*" >&2
	}

	migrate_config_file() {
		name="$1"
		home_path="${HOME_GIT_SPICE_DIR}/${name}"
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

	mkdir -p "${HOME_GIT_SPICE_DIR}"
	migrate_config_file "${PERSISTENT_FILE}"
	chown -R "${USER_NAME}" "${CONFIG_ROOT}"
	chmod 700 "${CONFIG_ROOT}"
EOF
chmod +x /usr/local/share/git-spice-init.sh

echo "Done!"
