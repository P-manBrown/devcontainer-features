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

	node_index_line="$(curl -fsSL https://nodejs.org/dist/index.json | grep -m1 '"lts":"')"
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

	tar -xJf "${node_tmp_dir}/${node_asset}" -C /usr/local --strip-components=1
	rm -rf "${node_tmp_dir}"
fi

# Install
if [[ "${VERSION}" == "latest" ]]; then
	npm install -g @usebruno/cli
else
	npm install -g "@usebruno/cli@${VERSION}"
fi

echo "Installed: $(bru --version)"
