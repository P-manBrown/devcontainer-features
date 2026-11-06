#!/usr/bin/env bash
set -eu

USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"

VERSION="${VERSION:-"latest"}"

# Codex's packages (the binaries) live here instead of in ~/.codex, so
# they stay in the image: ~/.codex itself becomes a link into the
# codex-config volume at container start (see codex-init.sh below).
CODEX_PACKAGE_HOME="${USER_HOME}/.local/share/codex"

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

# Install
if [[ "${USER_NAME}" == "root" ]]; then
	curl -fsSL https://chatgpt.com/codex/install.sh \
		| HOME="${USER_HOME}" CODEX_HOME="${CODEX_PACKAGE_HOME}" CODEX_NON_INTERACTIVE=true \
			sh -s -- --release "${VERSION}"
else
	curl -fsSL https://chatgpt.com/codex/install.sh \
		| su -s /bin/sh \
			-c "HOME=$(printf '%q' "${USER_HOME}") CODEX_HOME=$(printf '%q' "${CODEX_PACKAGE_HOME}") CODEX_NON_INTERACTIVE=true sh -s -- --release $(printf '%q' "${VERSION}")" \
			"${USER_NAME}"
fi

# Turn off Codex's own sandbox by default. It needs a user namespace,
# which a container only allows with SYS_ADMIN and relaxed seccomp and
# AppArmor profiles; this Feature does not add those and treats the
# container itself as the sandbox. /etc/codex/config.toml is the
# lowest-precedence config layer, so a sandbox_mode set in the user's
# ~/.codex/config.toml, a project's .codex/config.toml or on the command
# line still wins. An existing file is left unchanged.
if [[ ! -e /etc/codex/config.toml ]]; then
	mkdir -p /etc/codex
	printf 'sandbox_mode = "danger-full-access"\n' > /etc/codex/config.toml
	chmod 644 /etc/codex/config.toml
else
	err "WARNING: /etc/codex/config.toml already exists; leaving it unchanged. Set sandbox_mode = \"danger-full-access\" there yourself if Codex's sandbox fails to start."
fi

ln -sf "${USER_HOME}/.local/bin/codex" /usr/local/bin/codex

# Pre-create the mount point owned by the target user. The entrypoint may
# run as a non-root user (e.g. when the base image sets USER), so it can't
# chown the volume itself; Docker copies this ownership into the named
# volume on its first mount, which is what makes that work.
mkdir -p /usr/local/share/codex-config
chown "${USER_NAME}" /usr/local/share/codex-config

# Create entrypoint
cat <<-EOF > /usr/local/share/codex.env
	USER_NAME="${USER_NAME}"
	USER_HOME="${USER_HOME}"
EOF
cat <<-'EOF' > /usr/local/share/codex-init.sh
	#!/usr/bin/env bash
	set -eu

	source /usr/local/share/codex.env

	# ~/.codex is one symlink into the codex-config volume, so every file
	# Codex writes there persists, including auth.json, which Codex saves
	# by writing a new file and renaming it over the old one. The link
	# target is a subdirectory, not the mount point itself, so tools that
	# replace the link target with a copy can remove and recreate it.
	CONFIG_ROOT="/usr/local/share/codex-config"
	VOLUME_CODEX_DIR="${CONFIG_ROOT}/codex"
	HOME_CODEX_DIR="${USER_HOME}/.codex"
	# Codex's own state. When both the volume and a real ~/.codex hold
	# one of these, the volume's copy wins: it is what the user last used,
	# because every login and session made in a container is written
	# straight into the volume.
	USER_STATE_NAMES="auth.json config.toml history.jsonl session_index.jsonl sessions archived_sessions log"

	err() {
		printf '\e[31m%s\e[m\n' "$*" >&2
	}

	is_user_state() {
		local name="$1"
		local state_name
		for state_name in ${USER_STATE_NAMES}; do
			if [[ "${state_name}" == "${name}" ]]; then
				return 0
			fi
		done
		return 1
	}

	# Version 3.0.0 of this Feature kept each file at the top of the
	# volume. Move those entries into the codex subdirectory. An entry
	# whose name already exists there is kept where it is and reported,
	# so nothing is deleted.
	# codex.restore is the staging copy of codebase-memory-mcp's restore step;
	# it is cleaned up there, so it must not be moved into the volume.
	migrate_old_volume_layout() {
		local entry name
		while IFS= read -r -d '' entry; do
			name="${entry##*/}"
			if [[ -e "${VOLUME_CODEX_DIR}/${name}" ]] || [[ -L "${VOLUME_CODEX_DIR}/${name}" ]]; then
				err "WARNING: Left ${entry} in place because ${VOLUME_CODEX_DIR}/${name} already exists."
				continue
			fi
			mv "${entry}" "${VOLUME_CODEX_DIR}/${name}"
		done < <(find "${CONFIG_ROOT}" -mindepth 1 -maxdepth 1 ! -name codex ! -name codex.restore -print0)
	}

	# Succeeds when every path under the copied entry exists in the volume
	# with the same type and content. Files that exist only in the volume
	# are not a mismatch.
	verify_copy() {
		local name="$1"
		local src dst
		while IFS= read -r -d '' src; do
			dst="${VOLUME_CODEX_DIR}/${src#"${HOME_CODEX_DIR}/"}"
			if [[ ! -e "${dst}" ]] && [[ ! -L "${dst}" ]]; then
				return 1
			fi
			if [[ "$(stat -c %F "${src}")" != "$(stat -c %F "${dst}")" ]]; then
				return 1
			fi
			if [[ -L "${src}" ]]; then
				if [[ "$(readlink "${src}")" != "$(readlink "${dst}")" ]]; then
					return 1
				fi
			elif [[ -f "${src}" ]]; then
				if ! cmp -s "${src}" "${dst}"; then
					return 1
				fi
			fi
		done < <(find "${HOME_CODEX_DIR}/${name}" -print0)
	}

	# Merge a real ~/.codex (from the image, or left by a failed start)
	# into the volume, then remove it so the link can take its place.
	merge_home_codex_dir() {
		local entry name target
		local copied=()
		while IFS= read -r -d '' entry; do
			name="${entry##*/}"
			if [[ -L "${entry}" ]]; then
				# A 3.0.0 per-file link: its data is already in the volume.
				# Plain readlink, so a link left dangling by the layout
				# migration above is still recognized.
				target="$(readlink "${entry}")"
				if [[ "${target}" == "${CONFIG_ROOT}/"* ]]; then
					rm -f "${entry}"
					continue
				fi
			fi
			if is_user_state "${name}"; then
				if [[ -e "${VOLUME_CODEX_DIR}/${name}" ]] || [[ -L "${VOLUME_CODEX_DIR}/${name}" ]]; then
					if [[ "${name}" == "auth.json" ]]; then
						err "WARNING: Ignored ${entry}; keeping the login stored in ${VOLUME_CODEX_DIR}/auth.json."
					fi
					continue
				fi
			fi
			# Image content replaces older copies in the volume; files
			# that exist only in the volume stay.
			if ! cp -a -T "${entry}" "${VOLUME_CODEX_DIR}/${name}"; then
				err "ERROR: Failed to copy ${entry} into ${VOLUME_CODEX_DIR}; leaving ${HOME_CODEX_DIR} in place."
				exit 1
			fi
			copied+=("${name}")
		done < <(find "${HOME_CODEX_DIR}" -mindepth 1 -maxdepth 1 -print0)

		for name in "${copied[@]}"; do
			if ! verify_copy "${name}"; then
				err "ERROR: Failed to verify the copy of ${HOME_CODEX_DIR}/${name}; leaving ${HOME_CODEX_DIR} in place."
				exit 1
			fi
		done
		rm -rf "${HOME_CODEX_DIR}"
	}

	mkdir -p "${VOLUME_CODEX_DIR}"
	migrate_old_volume_layout

	link_home_codex_dir=true
	if [[ -L "${HOME_CODEX_DIR}" ]]; then
		if [[ "$(readlink "${HOME_CODEX_DIR}")" == "${VOLUME_CODEX_DIR}" ]]; then
			link_home_codex_dir=false
		else
			err "WARNING: ${HOME_CODEX_DIR} is a symlink to $(readlink "${HOME_CODEX_DIR}"); leaving it unchanged, so the codex-config volume does not keep what Codex writes there."
			link_home_codex_dir=false
		fi
	elif [[ -e "${HOME_CODEX_DIR}" ]] && [[ ! -d "${HOME_CODEX_DIR}" ]]; then
		err "ERROR: ${HOME_CODEX_DIR} exists but is not a directory; leaving it unchanged."
		exit 1
	elif [[ -d "${HOME_CODEX_DIR}" ]]; then
		merge_home_codex_dir
	fi

	if [[ "${link_home_codex_dir}" == true ]]; then
		ln -sfn "${VOLUME_CODEX_DIR}" "${HOME_CODEX_DIR}"
	fi
	chown -R "${USER_NAME}" "${CONFIG_ROOT}"
	chmod 700 "${CONFIG_ROOT}"
EOF
chmod +x /usr/local/share/codex-init.sh

echo "Done!"
