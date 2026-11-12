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

# Feature options are strings; accept a validated comma-separated IDE list.
validate_ides() {
	local selected
	local -a requested
	[[ -n "${IDE}" && "${IDE}" != *, && "${IDE}" != *$'\n'* && "${IDE}" != *$'\r'* ]] || { err "ERROR: Empty IDE entry."; return 1; }
	IFS=',' read -r -a requested <<< "${IDE}"
	for selected in "${requested[@]}"; do
		selected="${selected#"${selected%%[![:space:]]*}"}"
		selected="${selected%"${selected##*[![:space:]]}"}"
		case "${selected}" in
			claude-code|codex-cli) ;;
			*) err "ERROR: Unsupported IDE: ${selected}"; return 1 ;;
		esac
	done
}
validate_ides
case "${PROVIDER}" in
	claude|codex|host|by-source) ;;
	*) err "ERROR: Unsupported provider: ${PROVIDER}"; exit 1 ;;
esac

# A system-wide, unmanaged installation is independent of root's home and
# persists in the image when user configuration volumes are reused.
uv_installer="$(mktemp)"
curl -fsSL https://astral.sh/uv/install.sh -o "${uv_installer}"
UV_UNMANAGED_INSTALL=/usr/local/bin sh "${uv_installer}"
rm -f "${uv_installer}"
/usr/local/bin/uv --version
/usr/local/bin/uvx --version

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
if [[ "${PROVIDER}" == "by-source" || "${PROVIDER}" == "codex" ]]; then
	worker_script="$(npm root -g)/claude-mem/plugin/scripts/worker-service.cjs"
	capability=CLAUDE_MEM_CODEX_MODEL
	[[ "${PROVIDER}" != "by-source" ]] || capability=CLAUDE_MEM_PROVIDER_BY_SOURCE
	if ! grep -q "${capability}" "${worker_script}"; then
		err "ERROR: Installed claude-mem does not support ${PROVIDER}; use a newer version."
		exit 1
	fi
fi


# Pre-create the mount point owned by the target user. The entrypoint may
# run as a non-root user (e.g. when the base image sets USER), so it can't
# chown the volume itself; Docker copies this ownership into the named
# volume on its first mount, which is what makes that work.
mkdir -p /usr/local/share/claude-mem-cache
chown "${USER_NAME}" /usr/local/share/claude-mem-cache

# Create entrypoint
{
	printf 'USER_NAME=%q\n' "${USER_NAME}"
	printf 'USER_HOME=%q\n' "${USER_HOME}"
	printf 'IDE=%q\n' "${IDE}"
	printf 'PROVIDER=%q\n' "${PROVIDER}"
} > /usr/local/share/claude-mem.env
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
	if [[ "$(id -u)" -eq 0 ]]; then
		chown -R "${USER_NAME}" "${CACHE_ROOT}"
	fi
	ln -sfn "${CACHE_ROOT}" "${HOME_CACHE_DIR}"

	# Use the same non-login user environment for prerequisites and installation.
	# Workers spawned by the installer inherit this PATH, including system uvx.
	run_as_user() {
		local command
		printf -v command '%q ' "$@"
		if [[ "$(id -un)" == "${USER_NAME}" ]]; then
			HOME="${USER_HOME}" PATH="/usr/local/bin:${PATH}" CI=true "$@"
		elif [[ "$(id -u)" -eq 0 ]]; then
			su -s /bin/bash -c "export HOME=$(printf '%q' "${USER_HOME}") PATH=$(printf '%q' "/usr/local/bin:${PATH}") CI=true; ${command}" "${USER_NAME}"
		else
			err "ERROR: Run initialization as root or ${USER_NAME}."
			return 1
		fi
	}

	ides=()
	[[ -n "${IDE}" && "${IDE}" != *, && "${IDE}" != *$'\n'* && "${IDE}" != *$'\r'* ]] || { err "ERROR: Empty IDE entry."; exit 1; }
	IFS=',' read -r -a requested_ides <<< "${IDE}"
	needs_claude=false
	needs_codex=false
	for selected_ide in "${requested_ides[@]}"; do
		selected_ide="${selected_ide#"${selected_ide%%[![:space:]]*}"}"
		selected_ide="${selected_ide%"${selected_ide##*[![:space:]]}"}"
		case "${selected_ide}" in
			claude-code) needs_claude=true ;;
			codex-cli) needs_codex=true ;;
			*) err "ERROR: Unsupported IDE: ${selected_ide}"; exit 1 ;;
		esac
		# Register duplicate entries only once, preserving the requested order.
		if [[ " ${ides[*]-} " != *" ${selected_ide} "* ]]; then
			ides+=("${selected_ide}")
		fi
	done
	install_provider="${PROVIDER}"
	case "${PROVIDER}" in
		claude) needs_claude=true ;;
		codex) needs_codex=true ;;
		host) ;;
		by-source) needs_claude=true; needs_codex=true; install_provider=claude ;;
		*) err "ERROR: Unsupported provider: ${PROVIDER}"; exit 1 ;;
	esac
	# Check all prerequisites before modifying either integration or settings.
	run_as_user uv --version
	run_as_user uvx --version
	if "${needs_claude}"; then
		run_as_user bash -c 'command -v claude >/dev/null || { echo "ERROR: Claude Code CLI is required by the selected IDE/provider." >&2; exit 1; }'
	fi
	if "${needs_codex}"; then
		run_as_user bash -c 'command -v codex >/dev/null || { echo "ERROR: Codex CLI is required by the selected IDE/provider." >&2; exit 1; }'
	fi

	# Persist routing before the installer starts a Worker. Refuse malformed
	# settings; update the provider/routing keys and preserve other settings.
	# Explicit single-provider selection clears any previous source overrides.
	run_as_user node - "${HOME_CACHE_DIR}/settings.json" "${PROVIDER}" <<'JS'
	const fs = require('fs');
	const [file, provider] = process.argv.slice(2);
	let settings = {};
	if (fs.existsSync(file)) settings = JSON.parse(fs.readFileSync(file, 'utf8'));
	if (!settings || typeof settings !== 'object' || Array.isArray(settings)) {
	    throw new Error('claude-mem settings.json must contain an object');
	}
	// Upstream supports both flat settings and legacy settings nested in env.
	const nested = settings.env && typeof settings.env === 'object' &&
	    !Array.isArray(settings.env) && Object.keys(settings.env).some(key => key.startsWith('CLAUDE_MEM_'));
	const target = nested ? settings.env : settings;
	target.CLAUDE_MEM_PROVIDER = provider === 'by-source' ? 'claude' : provider;
	target.CLAUDE_MEM_PROVIDER_BY_SOURCE = provider === 'by-source'
	    ? JSON.stringify({claude: 'claude', codex: 'codex'}) : '';
	const temporary = `${file}.feature-${process.pid}.tmp`;
	try {
	    fs.writeFileSync(temporary, JSON.stringify(settings, null, 2) + '\n', {mode: 0o600});
	    fs.renameSync(temporary, file);
	} finally {
	    if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
	}
	JS
	# An explicit --provider codex triggers browser pairing even in CI. The
	# upstream non-interactive installer can retain a saved Codex provider
	# without pairing; persist it above and use that supported path instead.
	provider_args=(--provider "${install_provider}")
	[[ "${PROVIDER}" != codex ]] || provider_args=()
	failed=0
	for selected_ide in "${ides[@]}"; do
		if ! run_as_user claude-mem install "${provider_args[@]}" --no-auto-start --ide "${selected_ide}"; then
			err "ERROR: claude-mem registration failed for ${selected_ide}; initialization is incomplete."
			failed=1
		fi
	done
	# Fresh non-interactive upstream installs intentionally skip autostart.
	# Start once after every selected integration has completed successfully.
	if [[ "${failed}" -eq 0 ]]; then
		if ! run_as_user claude-mem start; then
			err "ERROR: claude-mem Worker startup failed; initialization is incomplete."
			failed=1
		fi
	fi
	exit "${failed}"
EOF
chmod +x /usr/local/share/claude-mem-init.sh

echo "Done!"
