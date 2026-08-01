#!/usr/bin/env bash
set -eu

USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"

VERSION="${VERSION:-"latest"}"
CLAUDECODEHOOK="${CLAUDECODEHOOK:-false}"
CODEXHOOK="${CODEXHOOK:-false}"

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
		target="x86_64-unknown-linux-musl"
		;;
	aarch64|arm64)
		target="aarch64-unknown-linux-gnu"
		;;
	*)
		err "ERROR: Unsupported architecture: $(uname -m)"
		exit 1
		;;
esac

# Resolve version
if [[ "${VERSION}" == "latest" ]]; then
	release_json="$(curl -fsSL "https://api.github.com/repos/rtk-ai/rtk/releases/latest")"
	if ! VERSION="$(
		printf '%s' "${release_json}" \
			| grep -m 1 -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' \
			| sed -E 's/.*"v([^"]+)"/\1/'
	)" || [[ -z "${VERSION}" ]]; then
		err "ERROR: Failed to resolve the latest rtk version."
		exit 1
	fi
else
	VERSION="${VERSION#v}"
fi

# Download and verify
asset="rtk-${target}.tar.gz"
download_url="https://github.com/rtk-ai/rtk/releases/download/v${VERSION}"
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
install -m 0755 "${tmp_dir}/rtk" /usr/local/bin/rtk

installed_version="$(rtk --version)"
echo "Installed: ${installed_version}"

# Create entrypoint
cat <<-EOF > /usr/local/share/rtk.env
	USER_NAME="${USER_NAME}"
	USER_HOME="${USER_HOME}"
	CLAUDE_CODE_HOOK="${CLAUDECODEHOOK}"
	CODEX_HOOK="${CODEXHOOK}"
EOF
cat <<-'EOF' > /usr/local/share/rtk-init.sh
	#!/usr/bin/env bash
	set -eu

	source /usr/local/share/rtk.env

	if [[ "${CLAUDE_CODE_HOOK}" == "true" ]]; then
		if [[ "${USER_NAME}" == "root" ]]; then
			HOME="${USER_HOME}" rtk init -g --auto-patch
		else
			su -s /bin/bash \
				-c "HOME=$(printf '%q' "${USER_HOME}") rtk init -g --auto-patch" \
				"${USER_NAME}"
		fi
	fi

	if [[ "${CODEX_HOOK}" == "true" ]]; then
		if [[ "${USER_NAME}" == "root" ]]; then
			HOME="${USER_HOME}" rtk init -g --codex
		else
			su -s /bin/bash \
				-c "HOME=$(printf '%q' "${USER_HOME}") rtk init -g --codex" \
				"${USER_NAME}"
		fi
	fi
EOF
chmod +x /usr/local/share/rtk-init.sh

echo "Done!"
