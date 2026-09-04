#!/usr/bin/env bash
set -eu

USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"

VERSION="${VERSION:-"latest"}"
IDE="${IDE:-"claude-code"}"
PROVIDER="${PROVIDER:-"claude"}"

err() {
	printf '\e[31m%s\e[m\n' "$*" >&2
}

## User
if [[ "$(id -u)" -ne 0 ]]; then
	err "ERROR: Script must be run as root. Use sudo, su, or add \"USER root\" to your Dockerfile."
	exit 1
fi

## Node.js / npm — fall back to installing Node.js LTS ourselves if missing,
## mirroring src/bruno-cli/install.sh (some editors ignore installsAfter/dependsOn
## ordering, so this feature can't rely on a Node.js feature having already run).
if ! npm --version > /dev/null 2>&1; then
	# Some devcontainer implementations (e.g. Zed's dev container support)
	# ignore installsAfter/dependsOn/overrideFeatureInstallOrder and always
	# install features in lexicographic order instead of honoring declared
	# dependencies, so this feature cannot rely on the node feature having
	# run first. See: https://github.com/zed-industries/zed/issues/61691
	# Fall back to installing a minimal Node.js toolchain here.
	case "$(uname -m)" in
		x86_64)
			node_arch="x64"
			;;
		aarch64|arm64)
			node_arch="arm64"
			;;
		*)
			err "ERROR: Unsupported architecture for the Node.js fallback: $(uname -m)"
			exit 1
			;;
	esac

	node_index_json="$(curl -fsSL https://nodejs.org/dist/index.json)"
	node_index_line="$(printf '%s\n' "${node_index_json}" | grep -m1 '"lts":"')"
	if [[ -z "${node_index_line}" ]]; then
		err "ERROR: Could not resolve the latest Node.js LTS version."
		exit 1
	fi
	node_version="$(printf '%s' "${node_index_line}" | grep -oE '"version":"v[^"]+"' | sed -E 's/.*"v([^"]+)".*/\1/')"

	node_shasums="$(curl -fsSL "https://nodejs.org/dist/v${node_version}/SHASUMS256.txt")"
	if ! node_line="$(
		printf '%s\n' "${node_shasums}" | grep -E "linux-${node_arch}\.tar\.xz\$"
	)"; then
		err "ERROR: Could not find a Node.js v${node_version} build for linux-${node_arch}."
		exit 1
	fi
	node_checksum="$(printf '%s\n' "${node_line}" | awk '{print $1}')"
	node_asset="$(printf '%s\n' "${node_line}" | awk '{print $2}')"

	node_tmp_dir="$(mktemp -d)"
	trap 'rm -rf "${node_tmp_dir}"' EXIT

	curl -fsSL "https://nodejs.org/dist/v${node_version}/${node_asset}" -o "${node_tmp_dir}/${node_asset}"
	printf '%s  %s\n' "${node_checksum}" "${node_asset}" | (cd "${node_tmp_dir}" && sha256sum -c -)

	tar -xJf "${node_tmp_dir}/${node_asset}" -C /usr/local --strip-components=1 --no-same-owner
	rm -rf "${node_tmp_dir}"
fi

# Install
if [[ "${VERSION}" == "latest" ]]; then
	npm install -g claude-mem
else
	npm install -g "claude-mem@${VERSION}"
fi

echo "Installed: $(claude-mem --version)"

# Pre-create the mount point owned by the target user. The entrypoint may
# run as a non-root user (e.g. when the base image sets USER), so it can't
# chown the volume itself; Docker copies this ownership into the named
# volume on its first mount, which is what makes that work.
mkdir -p /usr/local/share/claude-mem-cache
chown "${USER_NAME}" /usr/local/share/claude-mem-cache

# Create entrypoint
cat <<-EOF > /usr/local/share/claude-mem.env
	USER_NAME="${USER_NAME}"
	USER_HOME="${USER_HOME}"
	IDE="${IDE}"
	PROVIDER="${PROVIDER}"
EOF
cat <<-'EOF' > /usr/local/share/claude-mem-init.sh
	#!/usr/bin/env bash
	set -eu

	source /usr/local/share/claude-mem.env

	CACHE_ROOT="/usr/local/share/claude-mem-cache"
	HOME_CACHE_DIR="${USER_HOME}/.claude-mem"

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
	chown -R "${USER_NAME}" "${CACHE_ROOT}"
	ln -sfn "${CACHE_ROOT}" "${HOME_CACHE_DIR}"

	# `claude-mem install` does not verify OAuth/API credentials at install
	# time (it only flips config, see plan §6 note); it CAN exit non-zero
	# though (e.g. `--ide codex-cli` when the `codex` binary isn't on PATH
	# yet — "partial installation"). Don't let that abort the entrypoint;
	# just surface it.
	install_claude_mem() {
		CI=true claude-mem install --provider "${PROVIDER}" --ide "${IDE}"
	}
	if [[ "${USER_NAME}" == "root" ]]; then
		HOME="${USER_HOME}" install_claude_mem || err "WARNING: claude-mem install exited non-zero; see output above."
	else
		su -s /bin/bash \
			-c "HOME=$(printf '%q' "${USER_HOME}") CI=true claude-mem install --provider $(printf '%q' "${PROVIDER}") --ide $(printf '%q' "${IDE}")" \
			"${USER_NAME}" || err "WARNING: claude-mem install exited non-zero; see output above."
	fi
EOF
chmod +x /usr/local/share/claude-mem-init.sh

echo "Done!"
