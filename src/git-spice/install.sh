#!/usr/bin/env bash
set -eu

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

echo "Done!"
