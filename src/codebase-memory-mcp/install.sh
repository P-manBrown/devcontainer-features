#!/usr/bin/env bash
set -eu

USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"

VERSION="${VERSION:-"latest"}"
AUTOINDEX="${AUTOINDEX:-false}"
UI="${UI:-false}"

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

# Install socat so the UI's 127.0.0.1-bound web server can be relayed to
# a listener reachable from the host (see NOTES.md). Skip if it's already
# present (e.g. via common-utils) to avoid a redundant apt-get update.
# /etc/os-release is sourced in a subshell: it defines its own VERSION
# field, which would otherwise clobber this script's VERSION (the
# requested codebase-memory-mcp release).
if [[ "${UI}" == "true" ]] && ! command -v socat > /dev/null 2>&1; then
	if [[ -f /etc/os-release ]]; then
		os_id_info="$(. /etc/os-release && printf '%s:%s' "${ID:-}" "${ID_LIKE:-}")"
		case "${os_id_info}" in
			*debian* | *ubuntu*)
				apt-get update -y
				apt-get -y install --no-install-recommends socat
				rm -rf /var/lib/apt/lists/*
				;;
			*)
				err "WARNING: socat could not be auto-installed on this distro (${os_id_info%%:*}); the UI will only be reachable from inside the container."
				;;
		esac
	else
		err "WARNING: /etc/os-release not found; skipping socat install. The UI will only be reachable from inside the container."
	fi
fi

# Detect architecture
case "$(uname -m)" in
	x86_64)
		arch="amd64"
		;;
	aarch64|arm64)
		arch="arm64"
		;;
	*)
		err "ERROR: Unsupported architecture: $(uname -m)"
		exit 1
		;;
esac

# Download and verify
variant="codebase-memory-mcp"
if [[ "${UI}" == "true" ]]; then
	variant="codebase-memory-mcp-ui"
fi
asset="${variant}-linux-${arch}-portable.tar.gz"
if [[ "${VERSION}" == "latest" ]]; then
	download_url="https://github.com/DeusData/codebase-memory-mcp/releases/latest/download"
else
	download_url="https://github.com/DeusData/codebase-memory-mcp/releases/download/${VERSION}"
fi
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

curl -fsSL "${download_url}/${asset}" -o "${tmp_dir}/${asset}"
curl -fsSL "${download_url}/checksums.txt" -o "${tmp_dir}/checksums.txt"

if ! checksum_line="$(
	grep -E "^[[:xdigit:]]{64}[[:space:]]+\\*?${asset//./\\.}$" "${tmp_dir}/checksums.txt"
)"; then
	err "ERROR: Checksum not found for ${asset}."
	exit 1
fi
printf '%s\n' "${checksum_line}" | (cd "${tmp_dir}" && sha256sum -c -)

# Install
tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}"
install -m 0755 "${tmp_dir}/codebase-memory-mcp" /usr/local/bin/codebase-memory-mcp

installed_version="$(codebase-memory-mcp --version)"
echo "Installed: ${installed_version}"

# Pre-create the mount point owned by the target user. The entrypoint may
# run as a non-root user (e.g. when the base image sets USER), so it can't
# chown the volume itself; Docker copies this ownership into the named
# volume on its first mount, which is what makes that work.
mkdir -p /usr/local/share/codebase-memory-mcp-cache
chown "${USER_NAME}" /usr/local/share/codebase-memory-mcp-cache

# Create entrypoint
cat <<-EOF > /usr/local/share/codebase-memory-mcp.env
	USER_NAME="${USER_NAME}"
	USER_HOME="${USER_HOME}"
	AUTOINDEX="${AUTOINDEX}"
	UI="${UI}"
EOF
cat <<-'EOF' > /usr/local/share/codebase-memory-mcp-init.sh
	#!/usr/bin/env bash
	set -eu

	source /usr/local/share/codebase-memory-mcp.env

	CACHE_ROOT="/usr/local/share/codebase-memory-mcp-cache"
	HOME_CACHE_DIR="${USER_HOME}/.cache/codebase-memory-mcp"

	err() {
		printf '\e[31m%s\e[m\n' "$*" >&2
	}

	migrate_cache_dir() {
		if [[ -L "${HOME_CACHE_DIR}" ]]; then
			return
		fi
		if [[ -e "${HOME_CACHE_DIR}" ]] && [[ ! -d "${HOME_CACHE_DIR}" ]]; then
			err "ERROR: ${HOME_CACHE_DIR} exists but is not a directory; leaving it unchanged."
			return 1
		fi
		if [[ ! -d "${HOME_CACHE_DIR}" ]]; then
			return
		fi
		if [[ -n "$(find "${CACHE_ROOT}" -mindepth 1 -print -quit)" ]]; then
			# The volume already holds data from a previous container;
			# the fresh install-time directory is disposable, so drop it
			# and let the volume win.
			rm -rf "${HOME_CACHE_DIR}"
			return
		fi

		cp -a "${HOME_CACHE_DIR}/." "${CACHE_ROOT}/"
		if ! diff -qr "${HOME_CACHE_DIR}" "${CACHE_ROOT}" > /dev/null; then
			err "ERROR: Failed to verify the copy of ${HOME_CACHE_DIR}; leaving the source unchanged."
			return 1
		fi
		rm -rf "${HOME_CACHE_DIR}"
	}

	mkdir -p "${CACHE_ROOT}"
	migrate_cache_dir
	mkdir -p "$(dirname "${HOME_CACHE_DIR}")"
	chown -R "${USER_NAME}" "${CACHE_ROOT}"

	ln -sfn "${CACHE_ROOT}" "${HOME_CACHE_DIR}"

	if [[ "${USER_NAME}" == "root" ]]; then
		HOME="${USER_HOME}" codebase-memory-mcp config set auto_index "${AUTOINDEX}"
	else
		su -s /bin/bash \
			-c "HOME=$(printf '%q' "${USER_HOME}") codebase-memory-mcp config set auto_index $(printf '%q' "${AUTOINDEX}")" \
			"${USER_NAME}"
	fi

	if [[ "${USER_NAME}" == "root" ]]; then
		HOME="${USER_HOME}" codebase-memory-mcp install --yes
	else
		su -s /bin/bash \
			-c "HOME=$(printf '%q' "${USER_HOME}") codebase-memory-mcp install --yes" \
			"${USER_NAME}"
	fi
EOF
chmod +x /usr/local/share/codebase-memory-mcp-init.sh

echo "Done!"
