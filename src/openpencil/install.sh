#!/usr/bin/env bash
set -eu

VERSION="${VERSION-0.8.5}"

err() {
	printf '\e[31m%s\e[m\n' "$*" >&2
}

# Check
## Version
VERSION="${VERSION#v}"
version_re='^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$'
if [[ "${VERSION}" == "latest" ]] || [[ ! "${VERSION}" =~ ${version_re} ]]; then
	err "ERROR: Invalid version '${VERSION}'. 'latest' is not supported: ZSeven-W/openpencil publishes only prereleases. Set an exact version such as '0.8.5'."
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

# Check glibc
glibc_required="2.39"
glibc_found="$(getconf GNU_LIBC_VERSION 2> /dev/null)" || glibc_found=""
glibc_version=""
if [[ "${glibc_found}" == "glibc "* ]]; then
	glibc_version="${glibc_found#glibc }"
fi
if [[ -z "${glibc_version}" ]] \
	|| [[ "$(printf '%s\n' "${glibc_required}" "${glibc_version}" | sort -V | head -n 1)" != "${glibc_required}" ]]; then
	err "OpenPencil ${VERSION} requires glibc ${glibc_required} or later (found: ${glibc_found:-unknown}). Use a base image such as Ubuntu 24.04 or Debian 13."
	exit 1
fi

# Check for another op
install_dir="/usr/local/share/openpencil"
op_link="/usr/local/bin/op"
if [[ -e "${op_link}" || -L "${op_link}" ]]; then
	if [[ ! -L "${op_link}" || "$(readlink "${op_link}")" != "${install_dir}/op" ]]; then
		err "ERROR: Another 'op' (for example the 1Password CLI) is installed at ${op_link}. It was not changed. Remove it before installing OpenPencil."
		exit 1
	fi
fi

# Install runtime libraries
if command -v apt-get > /dev/null 2>&1; then
	apt-get update
	apt-get install -y --no-install-recommends \
		libfontconfig1 libfreetype6 zlib1g libstdc++6 ca-certificates
	rm -rf /var/lib/apt/lists/*
fi

# Download and verify
cli_asset="op-cli-linux-${arch}.tar.gz"
desktop_asset="openpencil-desktop-linux-${arch}.tar.gz"
download_url="https://github.com/ZSeven-W/openpencil/releases/download/v${VERSION}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

for file in "${cli_asset}" "${desktop_asset}" SHA256SUMS.txt; do
	curl -fsSL "${download_url}/${file}" -o "${tmp_dir}/${file}"
done

for asset in "${cli_asset}" "${desktop_asset}"; do
	if ! checksum_line="$(
		grep -E "^[[:xdigit:]]{64}[[:space:]]+\\*?${asset//./\\.}$" "${tmp_dir}/SHA256SUMS.txt"
	)"; then
		err "ERROR: Checksum not found for ${asset}."
		exit 1
	fi
	printf '%s\n' "${checksum_line}" | (cd "${tmp_dir}" && sha256sum -c -)
done

# Install
extract_dir="${tmp_dir}/extract"
mkdir -p "${extract_dir}"
tar -xzf "${tmp_dir}/${cli_asset}" --no-same-owner -C "${extract_dir}"
tar -xzf "${tmp_dir}/${desktop_asset}" --no-same-owner -C "${extract_dir}"
for file in op openpencil-desktop; do
	if [[ ! -f "${extract_dir}/${file}" ]]; then
		err "ERROR: ${file} was not found in the downloaded archives."
		exit 1
	fi
done

rm -rf "${install_dir}"
mkdir -p "${install_dir}"
install -m 0755 "${extract_dir}/op" "${install_dir}/op"
install -m 0755 "${extract_dir}/openpencil-desktop" "${install_dir}/openpencil-desktop"
cp -R "${extract_dir}/font-notices" "${install_dir}/font-notices"
ln -sfn "${install_dir}/op" "${op_link}"

# Self-check
for bin in "${install_dir}/openpencil-desktop" "${install_dir}/op"; do
	if missing="$(ldd "${bin}" | grep 'not found')"; then
		err "ERROR: Missing shared libraries for ${bin}:"
		err "${missing}"
		exit 1
	fi
done

installed_version="$("${op_link}" --version)"
echo "Installed: ${installed_version}"
if [[ "${installed_version}" != *"${VERSION}"* ]]; then
	err "ERROR: Version mismatch: expected ${VERSION}, got ${installed_version}."
	exit 1
fi

echo "Done!"
