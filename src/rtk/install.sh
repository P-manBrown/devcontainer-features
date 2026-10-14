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
# NOTE: aarch64 has no prebuilt musl (libc-independent) binary upstream, and the
# prebuilt gnu binary is linked against a newer GLIBC than common base images
# (e.g. Debian bookworm) provide, so it is built from source instead.
case "$(uname -m)" in
	x86_64)
		target="x86_64-unknown-linux-musl"
		;;
	aarch64|arm64)
		target=""
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

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

if [[ -n "${target}" ]]; then
	# Download and verify prebuilt binary
	asset="rtk-${target}.tar.gz"
	download_url="https://github.com/rtk-ai/rtk/releases/download/v${VERSION}"

	curl -fsSL "${download_url}/${asset}" -o "${tmp_dir}/${asset}"
	curl -fsSL "${download_url}/checksums.txt" -o "${tmp_dir}/checksums.txt"

	if ! checksum_line="$(
		grep -E "^[[:xdigit:]]{64}[[:space:]]+\\*?${asset//./\\.}$" "${tmp_dir}/checksums.txt"
	)"; then
		err "ERROR: Checksum not found for ${asset}."
		exit 1
	fi
	printf '%s\n' "${checksum_line}" | (cd "${tmp_dir}" && sha256sum -c -)

	tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}"
	rtk_bin="/usr/local/bin/rtk"
	install -m 0755 "${tmp_dir}/rtk" "${rtk_bin}"
else
	# Build from source
	if ! command -v cc > /dev/null 2>&1 || ! command -v git > /dev/null 2>&1; then
		apt-get update -qq
		apt-get install -y -qq --no-install-recommends \
			build-essential pkg-config libssl-dev git ca-certificates
	fi

	export CARGO_HOME="${tmp_dir}/cargo"
	export RUSTUP_HOME="${tmp_dir}/rustup"
	curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
		| sh -s -- -y -q --profile minimal --default-toolchain stable --no-modify-path

	# shellcheck disable=SC1091
	source "${CARGO_HOME}/env"
	root="/usr/local"
	cargo install --git https://github.com/rtk-ai/rtk --tag "v${VERSION}" --root "${root}" rtk
	rtk_bin="${root}/bin/rtk"
fi

if [[ ! -x "${rtk_bin}" ]]; then
	err "ERROR: Installed rtk binary is not executable: ${rtk_bin}"
	exit 1
fi

installed_version="$("${rtk_bin}" --version)"
echo "Installed: ${installed_version}"

# Create Claude Code hook scripts
if [[ "${CLAUDECODEHOOK}" == "true" ]]; then
	if ! command -v jq > /dev/null 2>&1; then
		apt-get update -qq
		apt-get install -y -qq --no-install-recommends jq
	fi

	mkdir -p /usr/local/share/rtk-claude-hook
	{
		printf '#!/usr/bin/env bash\nrtk_bin=%q\n' "${rtk_bin}"
		cat <<-'EOF'
			input="$(cat)"
			output="$("${rtk_bin}" "$@" <<< "${input}")"
			status=$?

			if [[ "${status}" -eq 0 && -n "${output}" ]]; then
				cwd="$(jq -r '.cwd // empty' <<< "${input}" 2>/dev/null)" || cwd=""
				command="$(jq -r '.hookSpecificOutput.updatedInput.command // empty' <<< "${output}" 2>/dev/null)" || command=""
				# Inspect the rewrite the guard sees, conservatively including git-spice,
				# .git, /usr/bin/git and grep git, but not .gitignore or gitleaks.
				if [[ "${cwd}" == */.claude/worktrees/* && "${command}" =~ (^|[^[:alnum:]_])git($|[^[:alnum:]_]) ]]; then
					exit 0
				fi
			fi

			if [[ -n "${output}" ]]; then
				printf '%s\n' "${output}"
			fi
			exit "${status}"
		EOF
	} > /usr/local/share/rtk-claude-hook/rtk
	cat <<-'EOF' > /usr/local/share/rtk-claude-hook/patch-settings.sh
		#!/usr/bin/env bash
		set -eu

		settings="${HOME}/.claude/settings.json"
		if [[ ! -f "${settings}" ]]; then
			exit 0
		fi

		tmp="$(mktemp)"
		trap 'rm -f "${tmp}"' EXIT
		jq --arg wrapper '/usr/local/share/rtk-claude-hook/rtk hook claude' '
			if (.hooks.PreToolUse | type) == "array" then
				.hooks.PreToolUse |= (
					reduce .[] as $group ({seen: false, groups: []};
						if ($group | type) == "object" and ($group.hooks | type) == "array" then
							reduce $group.hooks[] as $hook (. + {kept: []};
								if ($hook | type) == "object" and ($hook.command | type) == "string" then
									if ($hook.command | test("^(\\S*/)?rtk hook claude$")) then
										if .seen then . else .seen = true | .kept += [$hook | .command = $wrapper] end
									else .kept += [$hook] end
								else .kept += [$hook] end
							)
							| if (.kept | length) > 0 or ($group.hooks | length) == 0 then
								.kept as $kept | .groups += [$group | .hooks = $kept]
							else . end
							| del(.kept)
						else .groups += [$group] end
					) | .groups
				)
			else . end
		' "${settings}" > "${tmp}"
		if [[ "$(cat "${tmp}")" != "$(jq . "${settings}")" ]]; then
			cat "${tmp}" > "${settings}"
		fi
	EOF
	chmod 0755 /usr/local/share/rtk-claude-hook/rtk /usr/local/share/rtk-claude-hook/patch-settings.sh
fi

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

	err() {
		printf '\e[31m%s\e[m\n' "$*" >&2
	}

	if [[ "${CLAUDE_CODE_HOOK}" == "true" ]]; then
		if [[ "${USER_NAME}" == "root" ]]; then
			HOME="${USER_HOME}" rtk init -g --auto-patch
			HOME="${USER_HOME}" /usr/local/share/rtk-claude-hook/patch-settings.sh \
				|| err "WARNING: Failed to normalize the Claude Code rtk hook."
		else
			su -s /bin/bash \
				-c "HOME=$(printf '%q' "${USER_HOME}") rtk init -g --auto-patch" \
				"${USER_NAME}"
			su -s /bin/bash \
				-c "HOME=$(printf '%q' "${USER_HOME}") /usr/local/share/rtk-claude-hook/patch-settings.sh" \
				"${USER_NAME}" \
				|| err "WARNING: Failed to normalize the Claude Code rtk hook."
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
