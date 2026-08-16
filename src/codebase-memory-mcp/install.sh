#!/usr/bin/env bash
set -eu

USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"

VERSION="${VERSION:-"latest"}"
AUTOINDEX="${AUTOINDEX:-false}"
PORTRELAY="${PORTRELAY:-false}"

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
if [[ "${PORTRELAY}" == "true" ]] && ! command -v socat > /dev/null 2>&1; then
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
# The graph-visualization UI is bundled into every build since v0.10.0, so
# there is no separate "-ui" asset to select between anymore.
asset="codebase-memory-mcp-linux-${arch}-portable.tar.gz"
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

	# CBM's install activation is stricter than this environment's normal,
	# correct state: it refuses to write under a group-writable directory
	# (Debian's pam_umask "usergroups" rule makes ~/.local group-writable
	# when the user's name matches their primary group, a common adduser
	# default), it requires owning the directory and file that hold its
	# own executable (to safely self-update), and it refuses to write
	# through a symlink (Claude Code and Codex persist their config
	# across container rebuilds by symlinking these paths into a named
	# volume; see their features' init scripts). Relax everything it
	# checks, run install, then restore every bit of it exactly,
	# regardless of whether install succeeds.
	local_dirs=()
	local_dirs_mode=()
	for d in "${USER_HOME}/.local" "${USER_HOME}/.local/bin" "${USER_HOME}/.local/share"; do
		if [[ -d "${d}" ]]; then
			local_dirs+=("${d}")
			local_dirs_mode+=("$(stat -c %a "${d}")")
		fi
	done

	usr_local_bin_owner="$(stat -c %U /usr/local/bin)"
	cbm_binary_owner=""
	if [[ -e /usr/local/bin/codebase-memory-mcp ]]; then
		cbm_binary_owner="$(stat -c %U /usr/local/bin/codebase-memory-mcp)"
	fi

	agent_paths=(
		"${USER_HOME}/.claude"
		"${USER_HOME}/.claude.json"
		"${USER_HOME}/.codex/config.toml"
	)
	materialized_paths=()
	materialized_targets=()

	restore_activation_environment() {
		for i in "${!materialized_paths[@]}"; do
			p="${materialized_paths[${i}]}"
			t="${materialized_targets[${i}]}"
			rm -rf "${t}"
			if [[ -e "${p}" ]]; then
				cp -a "${p}" "${t}"
			fi
			rm -rf "${p}"
			ln -sfn "${t}" "${p}"
		done
		chown "${usr_local_bin_owner}" /usr/local/bin
		if [[ -n "${cbm_binary_owner}" ]] && [[ -e /usr/local/bin/codebase-memory-mcp ]]; then
			chown "${cbm_binary_owner}" /usr/local/bin/codebase-memory-mcp
		fi
		for i in "${!local_dirs[@]}"; do
			chmod "${local_dirs_mode[${i}]}" "${local_dirs[${i}]}"
		done
	}
	trap restore_activation_environment EXIT

	for d in "${local_dirs[@]}"; do
		chmod go-w "${d}"
	done
	chown "${USER_NAME}" /usr/local/bin
	if [[ -e /usr/local/bin/codebase-memory-mcp ]]; then
		chown "${USER_NAME}" /usr/local/bin/codebase-memory-mcp
	fi
	for p in "${agent_paths[@]}"; do
		if [[ -L "${p}" ]]; then
			t="$(readlink -f "${p}")"
			rm -f "${p}"
			if [[ -e "${t}" ]]; then
				cp -a "${t}" "${p}"
			fi
			materialized_paths+=("${p}")
			materialized_targets+=("${t}")
		fi
	done

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
