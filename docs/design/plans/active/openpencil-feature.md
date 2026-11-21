# `openpencil` Feature Implementation Plan

Spec: docs/design/specs/openpencil-feature.md

> **For agentic workers:** this plan is executed through Gas City implementation beads (one bead per `### Task N`), using the Superpowers executing-plans / test-driven-development methodology inside each bead. Do not dispatch provider-native subagents. Steps use checkbox (`- [ ]`) syntax for tracking. Run the tasks in order: Task 2 depends on Task 1, Task 3 depends on Task 2. All three tasks commit to the same feature branch.

**Goal:** Add a dev container Feature `openpencil` that installs the ZSeven-W/openpencil `op` CLI and the headless `openpencil-desktop` binary from the pinned v0.8.5 GitHub Release, verified with SHA256, plus a CI scenario that proves a headless round trip.

**Architecture:** A new Feature directory `src/openpencil/` (metadata JSON, `install.sh`, `NOTES.md`) and its test directory `test/openpencil/` (one scenario). `install.sh` follows the repository's existing GitHub-Release pattern (`git-spice`, `rtk`): fail-fast guards, download into a `mktemp -d` cleaned by `trap`, `grep` the asset's line from the Release checksum file, `sha256sum -c`, `install -m 0755`, `echo "Done!"`. The binaries live in `/usr/local/share/openpencil/`, `/usr/local/bin/op` is a symlink, and `containerEnv` presets `OPENPENCIL_DESKTOP_BIN`.

**Tech Stack:** Bash (`set -eu`, tab indentation), dev container Feature spec (`devcontainer-feature.json`), `devcontainer features test` with `dev-container-features-test-lib` (CI only), `jq`, `sha256sum`, `getconf`, `ldd`, git-spice.

- Plan written: 2026-11-20 by plan step df-oe63h (workflow root df-d38if), iteration 1, attempt 1.
- Inputs: requirements `/workspaces/devcontainer-features/.gc-artifacts/openpencil-feature/requirements.md` (approved), design `/workspaces/devcontainer-features/.gc-artifacts/openpencil-feature/brainstorming/design.md` (approved).
- Plan mirror: none. The planning lane runs in the main checkout, which belongs to the human, so no copy was written under `docs/superpowers/plans/`. This file is the only copy.

## Context/Purpose

Five new files, one branch, one PR (`feat(openpencil)`), no change to any existing file:

| File | Responsibility | Task |
|------|----------------|------|
| `test/openpencil/scenarios.json` | One CI scenario `openpencil-test` on `mcr.microsoft.com/devcontainers/base:ubuntu` (Ubuntu 24.04, glibc 2.39), `remoteUser: vscode` | Task 1 |
| `test/openpencil/openpencil-test.sh` (mode 0755) | Checks version, env var, shared libraries, font notices and the headless start/status/tools/stop round trip | Task 1 |
| `src/openpencil/devcontainer-feature.json` | Feature id/version/name/description, pinned `version` option, `containerEnv`, `installsAfter` | Task 2 |
| `src/openpencil/install.sh` (mode 0755) | Guards, apt runtime libraries, download, SHA256 check, install layout, build-time self-check | Task 2 |
| `src/openpencil/NOTES.md` | Which OpenPencil, requirements, version policy, headless use, conflicts, licences (merged into the generated README by `release.yaml`) | Task 3 |

Sequencing: the scenario test is written first (Task 1) so the Feature is built against a fixed acceptance target. Task 2 builds the Feature itself and proves every pre-download guard locally (red before the script exists, green after). Task 3 adds the user documentation and checks the final change set. The CI scenario (`test-scenarios` matrix entry `openpencil`) and `all-tests` are the end-to-end acceptance evidence; they run after the PR is opened by the workflow's publish lifecycle, not inside these tasks.

Lifecycle note (not tasks): prepare, requirements, plan, plan-review, decompose, implement, summarize-implementation, review, finalize and publish are run by the `superpowers-build` formula itself. Opening the PR is part of that lifecycle (workflow var `open_pr=false`, `push=true`); the tasks below end at local commits on the feature branch.

### Traceability

| Requirement | Implemented in | Verified by |
|-------------|----------------|-------------|
| REQ-001 Feature metadata | Task 2 (JSON) | Task 2 Step 2/8 (`jq` assertions), CI `validate.yml` |
| REQ-002 Pinned version option | Task 2 (JSON option, `install.sh` version guard) | Task 2 Step 6 (local `latest`/`0.8`/empty/`v0.8.5` runs), CI scenario check 1 |
| REQ-003 Download source | Task 2 (`install.sh` download block) | Task 2 Step 9 (grep for URLs), Task 2 Step 10 (manual download) |
| REQ-004 SHA256 before unpacking | Task 2 (`install.sh` verify loop precedes extraction) | Task 2 Step 9 (code order check), Task 2 Step 10 (`sha256sum -c` of four assets) |
| REQ-005 Preconditions | Task 2 (`install.sh` root/curl/arch) | Task 2 Step 6 (non-root run) |
| REQ-006 glibc guard | Task 2 (`install.sh` glibc block) | Task 2 Step 6 (sudo run on glibc 2.36, recorded) |
| REQ-007 Runtime libraries | Task 2 (`install.sh` apt block) | CI scenario check 3 (`ldd`) |
| REQ-008 Install layout and environment | Task 2 (`install.sh` install block, `containerEnv`) | CI scenario checks 2 and 4 |
| REQ-009 Existing `op` guard | Task 2 (`install.sh` guard before apt and download) | Task 2 Step 9 (code review of guard position) |
| REQ-010 Build-time self-check | Task 2 (`install.sh` ldd + version block) | CI build log (`Installed: {"version":"0.8.5"}`, `Done!`) |
| REQ-011 Notes, generated README | Task 3 (`NOTES.md`, no README) | Task 3 Step 3 (grep assertions), Step 5 (no README) |
| REQ-012 Test scenario | Task 1 | Task 1 Steps 3-5 locally, CI `test-scenarios (openpencil)` |
| REQ-013 Delivery and verification | Tasks 1-3 (commits), Task 3 Step 5 (change-set check) | Task 2 Steps 6/10, Task 3 Step 5; PR and CI in the publish lifecycle |

### Coverage

| ID | Status |
|----|--------|
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-012 | covered |
| REQ-013 | covered |

## Current System

Repository facts the implementer needs (checked 2026-11-20 on `main` at e71922b):

- Features live in `src/<id>/` with `devcontainer-feature.json`, an executable `install.sh` (git mode 100755) and an optional `NOTES.md` that uses `##` headings. Tests live in `test/<id>/`: `scenarios.json` plus one executable `<scenario>.sh` per scenario (also 100755). Examples to read: `src/git-spice/install.sh`, `src/rtk/install.sh`, `src/rtk/devcontainer-feature.json`, `test/rtk/scenarios.json`, `test/rtk/rtk-test.sh`.
- `.editorconfig`: `*.sh` uses tabs; everything else 2-space indentation; LF; final newline.
- Shell conventions: `#!/usr/bin/env bash`, `set -eu`, an `err()` helper printing red to stderr, the root-check message block, `curl --version` presence check, `uname -m` → `x86_64` / `aarch64` (`arm64` → `aarch64`), errors prefixed `ERROR: `, last line `echo "Done!"`.
- CI (`.github/workflows/test.yaml`): the `plan` job lists every `src/*/devcontainer-feature.json`, so a new Feature is picked up automatically. `test-scenarios` runs `devcontainer features test -f <id> --skip-autogenerated .` (scenarios only). `all-tests` is the required check. `validate.yml` validates every `devcontainer-feature.json` on PRs.
- `src/<id>/README.md` is generated by `release.yaml` (manual `workflow_dispatch`). New Features (for example `bmad`) do not commit one.
- The repository root `README.md` is the template's and does not list Features, so it needs no change.
- This dev container: Debian 12, `aarch64`, glibc 2.36, no Docker, `sudo` available without a password, `jq`/`curl`/`sha256sum`/`getconf` present, `shellcheck` not installed. Scenario tests cannot run here.

Upstream facts (ZSeven-W/openpencil v0.8.5, re-checked by this plan step on 2026-11-20):

- Release base URL: `https://github.com/ZSeven-W/openpencil/releases/download/v0.8.5/`. Every release v0.8.0..v0.8.5 is a prerelease.
- `SHA256SUMS.txt` lines are `<64 hex>  <name>`; the Linux tarball lines are:
  - `47b6a85ae7508bc67c4508636fdb113679836d0be8d06ccea07c90217bffed29  op-cli-linux-aarch64.tar.gz`
  - `5bce59ac406048c08a4fd7f04a5f8761d0a29cfe0d3873743e916e642b4df5e4  op-cli-linux-x86_64.tar.gz`
  - `3ed57eab1239147ed861cd3f18b4df9fbe0544ae412fc763c41d4a1577c1be58  openpencil-desktop-linux-aarch64.tar.gz`
  - `0e554f611e6406d9819e35e204a640586cf656cb5b4ad051b0a31c2783046b24  openpencil-desktop-linux-x86_64.tar.gz`
- Archive layout (from `tar -tzvf` of the aarch64 assets): `op-cli-linux-<arch>.tar.gz` holds `op` at the archive root. `openpencil-desktop-linux-<arch>.tar.gz` holds `openpencil-desktop`, `font-notices/NOTICE.txt`, `font-notices/OFL-Inter.txt`, `font-notices/OFL-NotoSansSC.txt`, `font-notices/OFL-PlusJakartaSans.txt` at the archive root. Entries are owned by `runner/runner`, so extract with `--no-same-owner`.
- `op` usage text (from the binary): `op [--port N] <command> [options]` (global `--port`, default 3100, placed before the command), `op start --headless [--file path.op]` ("run the windowless file-backed MCP server (CI / display-less agents)"), `op stop`, `op status` ("check whether MCP HTTP is reachable"), `op [--port N] tools`. `op --version` prints `{"version":"0.8.5"}`. `op status` exits 0 whether or not a server runs and prints `{"running":true,...}` / `{"running":false}`.
- Earlier container investigation (tascon-frontend bead tf-uwqi5.1) ran `op start --headless --file X.op --port 7391`, called tools, and stopped the server with `op stop`, which confirms the start command returns and the sequence works on glibc 2.39.

## Proposed Implementation

Work in the implementation worktree assigned by the workflow. All commits go to one feature branch. Use the repository Skill `git-spice-workflow` for every branch and commit operation (commit messages in English, with a body; `git-spice commit create --no-restack` while other changes remain in the tree).

### Task 1: Test scenario for the `openpencil` Feature

Write the CI scenario first. It is the acceptance target for Task 2 (REQ-012).

**Files:**
- Create: `test/openpencil/scenarios.json`
- Create: `test/openpencil/openpencil-test.sh` (mode 0755)

**Acceptance criteria:**
- `scenarios.json` has exactly one scenario, `openpencil-test`, matching REQ-012 byte-for-byte in content (`image` `mcr.microsoft.com/devcontainers/base:ubuntu`, `remoteUser` `vscode`, `features` `{ "openpencil": {} }`).
- `openpencil-test.sh` sources `dev-container-features-test-lib`, makes one `check` call per REQ-012 item (1-4 and 5a-5d, eight calls), sets an EXIT `trap` that runs `op stop` ignoring its result, and ends with `reportResults`.
- `bash -n` passes; git mode is 100755.

- [ ] **Step 0: Confirm the branch**

Run: `git -C <worktree> status -sb` and `git-spice ls --all`.
Expected: the worktree is on a feature branch for this work. If it is on `main` or a detached HEAD, create the branch with the `git-spice-workflow` Skill rules (stack on the topmost unmerged branch shown by `git-spice ls --all`, `--no-commit`), for example:

```bash
git-spice branch create feat/openpencil --no-commit
```

- [ ] **Step 1: Write `test/openpencil/scenarios.json`**

```json
{
  "openpencil-test": {
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "remoteUser": "vscode",
    "features": {
      "openpencil": {}
    }
  }
}
```

- [ ] **Step 2: Write `test/openpencil/openpencil-test.sh`**

Indent with tabs. The scenario runs as `vscode` (the scenario's `remoteUser`), so the round trip runs as that user without `sudo`. `timeout 120` on `op start` turns an unexpected foreground server into a failed check instead of a hung CI job. The status check retries for up to 30 seconds because the server may answer a moment after `op start` returns; it accepts optional whitespace around the colon, which still requires the REQ-012 value `"running":true`.

```bash
#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

install_dir="/usr/local/share/openpencil"
port=7391
work_dir="$(mktemp -d)"
trap 'op stop > /dev/null 2>&1 || true; rm -rf "${work_dir}"' EXIT

op_version() {
	op --version | grep -qF '0.8.5'
}
desktop_bin_env() {
	[[ "${OPENPENCIL_DESKTOP_BIN:-}" == "${install_dir}/openpencil-desktop" ]] \
		&& [[ -x "${OPENPENCIL_DESKTOP_BIN}" ]]
}
no_missing_libraries() {
	local bin output
	for bin in "${install_dir}/op" "${install_dir}/openpencil-desktop"; do
		output="$(ldd "${bin}")" || return
		if grep -q 'not found' <<< "${output}"; then
			printf '%s\n' "${output}" >&2
			return 1
		fi
	done
}
headless_start() {
	timeout 120 op --port "${port}" start --headless --file "${work_dir}/t.op"
}
headless_status() {
	local attempt
	for attempt in $(seq 1 30); do
		if op --port "${port}" status | grep -qE '"running"[[:space:]]*:[[:space:]]*true'; then
			return 0
		fi
		sleep 1
	done
	op --port "${port}" status >&2 || true
	return 1
}
headless_tools() {
	local output
	output="$(op --port "${port}" tools)" || return
	grep -qF '"name"' <<< "${output}"
}

# Definition specific tests
check "op_version" op_version
check "desktop_bin_env" desktop_bin_env
check "no_missing_libraries" no_missing_libraries
check "font_notices" test -f "${install_dir}/font-notices/NOTICE.txt"
check "headless_start" headless_start
check "headless_status_running" headless_status
check "headless_tools" headless_tools
check "headless_stop" op stop

# Report result
reportResults
```

- [ ] **Step 3: Make the script executable and check syntax**

```bash
chmod 0755 test/openpencil/openpencil-test.sh
bash -n test/openpencil/openpencil-test.sh && echo SYNTAX_OK
jq -e '(keys == ["openpencil-test"]) and (.["openpencil-test"].image == "mcr.microsoft.com/devcontainers/base:ubuntu") and (.["openpencil-test"].remoteUser == "vscode") and (.["openpencil-test"].features == {"openpencil": {}})' test/openpencil/scenarios.json
```

Expected: `SYNTAX_OK`, then `true`.

- [ ] **Step 4: Confirm the test is red (no Feature yet)**

Run: `test -f src/openpencil/devcontainer-feature.json && echo FEATURE_EXISTS || echo FEATURE_MISSING`
Expected: `FEATURE_MISSING`. The scenario cannot pass until Task 2 adds the Feature. (The scenario itself only runs in CI; there is no Docker in this dev container.)

- [ ] **Step 5: Optional lint**

If `shellcheck` is on PATH, run `shellcheck -S warning test/openpencil/openpencil-test.sh` and expect no output. If it is not installed (the case in this dev container), either install it into a throwaway venv in the system temp directory:

```bash
t="$(mktemp -d)" && python3 -m venv "$t" && "$t/bin/pip" install -q shellcheck-py && "$t/bin/shellcheck" -S warning test/openpencil/openpencil-test.sh; rm -rf "$t"
```

or record "shellcheck not installed" in the bead notes (REQ-013 requires it only when installed).

- [ ] **Step 6: Commit**

```bash
git add test/openpencil/scenarios.json test/openpencil/openpencil-test.sh
git ls-files -s test/openpencil/openpencil-test.sh   # expect mode 100755
git-spice commit create --no-restack -m "test(openpencil): add a headless round-trip scenario" -m "Check the op version, the OPENPENCIL_DESKTOP_BIN path, shared libraries, font notices, and a headless start/status/tools/stop round trip on base:ubuntu (glibc 2.39)."
```

(If the installed git-spice rejects a second `-m`, pass one message whose subject and body are separated by a blank line.)

### Task 2: Feature metadata and `install.sh`

Build the Feature: metadata (REQ-001, REQ-002) and the install script (REQ-002 to REQ-010). Prove each pre-download guard locally.

**Files:**
- Create: `src/openpencil/devcontainer-feature.json`
- Create: `src/openpencil/install.sh` (mode 0755)
- Test: `test/openpencil/openpencil-test.sh` (from Task 1, runs in CI), plus the local guard runs in Step 6

**Acceptance criteria:**
- The JSON passes the Step 2 `jq` assertion.
- `install.sh` order: version guard → root → `curl` → arch → glibc → existing-`op` guard → apt → download → both checksum checks → extract → install → `ldd` and version self-check → `Done!`. Nothing is downloaded, installed or deleted before the glibc and existing-`op` guards pass.
- The only URL in the script is `https://github.com/ZSeven-W/openpencil/releases/download/v${VERSION}`.
- Local runs in Step 6 print the expected messages and exit 1; the recorded output is pasted into the bead notes.
- `sha256sum -c` of the four Linux assets prints four `OK` lines (Step 10).

Decision recorded for review: the existing-`op` guard (REQ-009) runs before the apt step. REQ-009 only requires "before any download"; design step 6 listed it after apt. Running it first means a conflicting `/usr/local/bin/op` fails the build with no package changes.

- [ ] **Step 1: Write the failing local guard check**

Save this as `$(mktemp -d)/guard-check.sh` (system temp directory, not committed). It runs only paths that exit before any download or file change.

```bash
#!/usr/bin/env bash
# usage: guard-check.sh <repo-or-worktree-root>
set -u
script="$1/src/openpencil/install.sh"
fail=0
expect() { # expect <label> <expected substring> <command...>
	local label="$1" want="$2"; shift 2
	local out code
	out="$("$@" 2>&1)"; code=$?
	if [[ ${code} -ne 0 && "${out}" == *"${want}"* ]]; then
		echo "PASS ${label}"
	else
		echo "FAIL ${label} (exit ${code}): ${out}"; fail=1
	fi
}
expect latest   "'latest' is not supported" env VERSION=latest bash "${script}"
expect short    "'latest' is not supported" env VERSION=0.8 bash "${script}"
expect empty    "'latest' is not supported" env VERSION= bash "${script}"
expect nonroot  "Script must be run as root" env VERSION=0.8.5 bash "${script}"
expect glibc    "OpenPencil 0.8.5 requires glibc 2.39 or later (found: glibc 2.36). Use a base image such as Ubuntu 24.04 or Debian 13." sudo env VERSION=0.8.5 bash "${script}"
expect vprefix  "OpenPencil 0.8.5 requires glibc 2.39" sudo env VERSION=v0.8.5 bash "${script}"
if [[ -e /usr/local/share/openpencil || -e /usr/local/bin/op ]]; then
	echo "FAIL side-effects: /usr/local/share/openpencil or /usr/local/bin/op exists"; fail=1
else
	echo "PASS no-side-effects"
fi
exit "${fail}"
```

- [ ] **Step 2: Write `src/openpencil/devcontainer-feature.json`**

```json
{
  "id": "openpencil",
  "version": "1.0.0",
  "name": "OpenPencil (ZSeven-W)",
  "documentationURL": "https://github.com/P-manBrown/devcontainer-features/tree/main/src/openpencil",
  "licenseURL": "https://github.com/P-manBrown/devcontainer-features/blob/main/LICENSE",
  "description": "Install the ZSeven-W/openpencil 'op' CLI and the headless 'openpencil-desktop' binary from GitHub Releases. Requires glibc 2.39 or later. This is not openpencil.dev.",
  "options": {
    "version": {
      "type": "string",
      "proposals": ["0.8.5"],
      "default": "0.8.5",
      "description": "Exact ZSeven-W/openpencil release version (e.g. '0.8.5'). 'latest' is not supported: upstream publishes only prereleases."
    }
  },
  "containerEnv": {
    "OPENPENCIL_DESKTOP_BIN": "/usr/local/share/openpencil/openpencil-desktop"
  },
  "installsAfter": [
    "ghcr.io/devcontainers/features/common-utils"
  ]
}
```

Check it:

```bash
jq -e '.id == "openpencil" and .version == "1.0.0" and .name == "OpenPencil (ZSeven-W)"
  and .options.version.type == "string" and .options.version.default == "0.8.5"
  and .options.version.proposals == ["0.8.5"]
  and .containerEnv == {"OPENPENCIL_DESKTOP_BIN": "/usr/local/share/openpencil/openpencil-desktop"}
  and .installsAfter == ["ghcr.io/devcontainers/features/common-utils"]
  and ([keys[] | select(. == "entrypoint" or . == "mounts" or test("Command$"))] | length == 0)
  and (.description | test("ZSeven-W/openpencil") and test("glibc 2.39") and test("openpencil.dev"))' \
  src/openpencil/devcontainer-feature.json
```

Expected: `true`.

- [ ] **Step 3: Run the guard check to verify it fails**

Run: `bash <tmp>/guard-check.sh <worktree root>`
Expected: every guard line prints `FAIL` (bash reports `No such file or directory` for `install.sh`), exit 1. `PASS no-side-effects` still prints.

- [ ] **Step 4: Write `src/openpencil/install.sh`**

Indent with tabs (the heredoc `<<-EOF` strips leading tabs only). Do not reference `_REMOTE_USER` (it is unset in the local guard runs and the script does not need it).

```bash
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
```

Notes for the implementer:
- `VERSION="${VERSION-0.8.5}"` (no colon) keeps an explicitly empty value empty, so REQ-002's "empty" case is rejected instead of silently defaulting.
- The version error text contains `'latest' is not supported`, which the guard check matches for all three invalid inputs.
- The REQ-006 message is printed without the `ERROR: ` prefix so it is exactly the REQ-006 sentence.
- The checksum pipeline has no `pipefail`, and `sha256sum` is the last command, so a mismatch exits the script through `set -e`. Both archives are checked before the first `tar`.

- [ ] **Step 5: Make it executable and check syntax**

```bash
chmod 0755 src/openpencil/install.sh
bash -n src/openpencil/install.sh && echo SYNTAX_OK
```

Expected: `SYNTAX_OK`.

- [ ] **Step 6: Run the guard check to verify it passes**

Run: `bash <tmp>/guard-check.sh <worktree root>`
Expected (exit 0):

```
PASS latest
PASS short
PASS empty
PASS nonroot
PASS glibc
PASS vprefix
PASS no-side-effects
```

Also run the REQ-013 manual check directly and paste its output into the bead notes:

```bash
sudo env VERSION=0.8.5 bash src/openpencil/install.sh; echo "exit=$?"
```

Expected: the red line `OpenPencil 0.8.5 requires glibc 2.39 or later (found: glibc 2.36). Use a base image such as Ubuntu 24.04 or Debian 13.` and `exit=1`, with no `apt-get` or `curl` output before it.

- [ ] **Step 7: Optional lint**

Same as Task 1 Step 5, on `src/openpencil/install.sh`. Expect no warnings, or record "shellcheck not installed".

- [ ] **Step 8: Re-run the JSON check**

Run the `jq -e` command from Step 2. Expected: `true`.

- [ ] **Step 9: Review source and order**

```bash
grep -nE 'https?://' src/openpencil/install.sh
grep -nE '^# |sha256sum -c|tar -xzf|apt-get update|readlink|getconf' src/openpencil/install.sh
```

Expected: the only URL is `https://github.com/ZSeven-W/openpencil/releases/download/v${VERSION}`. Line numbers increase in this order: `getconf` → `readlink` (existing-`op` guard) → `apt-get update` → `sha256sum -c` → the two `tar -xzf` lines. No `api.github.com`, `openpencil.dev`, `brew` or `install-op.sh`.

- [ ] **Step 10: Manually verify the Release assets (REQ-013)**

```bash
d="$(mktemp -d)" && cd "$d"
base=https://github.com/ZSeven-W/openpencil/releases/download/v0.8.5
for f in SHA256SUMS.txt op-cli-linux-x86_64.tar.gz op-cli-linux-aarch64.tar.gz openpencil-desktop-linux-x86_64.tar.gz openpencil-desktop-linux-aarch64.tar.gz; do
	curl -fsSL "$base/$f" -o "$f"
done
grep -E '  (op-cli|openpencil-desktop)-linux-(x86_64|aarch64)\.tar\.gz$' SHA256SUMS.txt | sha256sum -c -
tar -tzf op-cli-linux-aarch64.tar.gz; tar -tzf openpencil-desktop-linux-aarch64.tar.gz
cd - > /dev/null; rm -rf "$d"
```

Expected: four `: OK` lines; the listings show `op`, then `openpencil-desktop` and `font-notices/` entries at the archive root. Paste the `sha256sum -c` output into the bead notes. (About 165 MB of downloads.)

- [ ] **Step 11: Commit**

```bash
git add src/openpencil/devcontainer-feature.json src/openpencil/install.sh
git ls-files -s src/openpencil/install.sh   # expect mode 100755
git-spice commit create --no-restack -m "feat(openpencil): install op and openpencil-desktop from a pinned release" -m "Download op-cli and openpencil-desktop for the pinned ZSeven-W/openpencil version, verify both archives against the release SHA256SUMS.txt before unpacking, and install them under /usr/local/share/openpencil with an op symlink. Reject latest, glibc older than 2.39, and an existing non-OpenPencil op before any download."
```

### Task 3: `NOTES.md` and the final change-set check

Write the user notes that `release.yaml` merges into the generated README (REQ-011), then confirm the branch contains exactly the five REQ-013 files.

**Files:**
- Create: `src/openpencil/NOTES.md`

**Acceptance criteria:**
- `NOTES.md` has the six REQ-011 sections as `##` headings, in this order: Which OpenPencil, Requirements, Version, Headless use, Conflicts, Licenses.
- No `src/openpencil/README.md` is committed.
- The branch diff against `main` lists exactly the five files and no other path; this repository's `.devcontainer.json` is unchanged.

- [ ] **Step 1: Write the failing content check**

```bash
check_notes() {
	local f=src/openpencil/NOTES.md
	test -f "$f" || { echo "FAIL missing $f"; return 1; }
	local h
	h="$(grep -E '^## ' "$f" | tr '\n' '|')"
	[[ "$h" == "## Which OpenPencil|## Requirements|## Version|## Headless use|## Conflicts|## Licenses|" ]] || { echo "FAIL headings: $h"; return 1; }
	for s in 'https://github.com/ZSeven-W/openpencil' 'openpencil.dev' 'Danila Poyarkov' 'Homebrew' 'glibc 2.39' 'Ubuntu 24.04' 'Debian 13' 'node:22-bookworm' '0.8.5' 'latest' 'SHA256SUMS.txt' 'op start --headless --file design.op' 'op status' 'op tools' 'op stop' 'OPENPENCIL_DESKTOP_BIN' '1Password' '/usr/local/share/openpencil/font-notices/'; do
		grep -qF -- "$s" "$f" || { echo "FAIL missing text: $s"; return 1; }
	done
	echo PASS
}
check_notes
```

Run it now. Expected: `FAIL missing src/openpencil/NOTES.md`.

- [ ] **Step 2: Write `src/openpencil/NOTES.md`**

````markdown
## Which OpenPencil

This Feature installs [ZSeven-W/openpencil](https://github.com/ZSeven-W/openpencil): the `op` CLI and the windowless `openpencil-desktop` binary from its GitHub Releases. It is not openpencil.dev (Danila Poyarkov) or the Homebrew core `openpencil` cask, which are different projects with the same name.

## Requirements

- glibc 2.39 or later, for example Ubuntu 24.04 or Debian 13 base images.
- x86_64 or aarch64 Linux.

Debian 12-based images (for example `node:22-bookworm`, glibc 2.36) fail at build time with a message that names the glibc found.

## Version

The `version` option is pinned to `0.8.5` because upstream publishes only prereleases. `latest` is not accepted; set an exact version. Each downloaded archive is checked against the Release's `SHA256SUMS.txt` before it is unpacked.

## Headless use

```bash
op start --headless --file design.op
op status
op tools
op <tool> key=value
op stop
```

`OPENPENCIL_DESKTOP_BIN` is preset to `/usr/local/share/openpencil/openpencil-desktop`, so `op start --headless` finds the desktop binary without extra setup.

## Conflicts

The install fails if another `/usr/local/bin/op` (for example the 1Password CLI) is present. The existing file is left unchanged.

## Licenses

The font notices shipped with `openpencil-desktop` are kept in `/usr/local/share/openpencil/font-notices/`.
````

- [ ] **Step 3: Run the content check to verify it passes**

Run `check_notes` again. Expected: `PASS`.

- [ ] **Step 4: Commit**

```bash
git add src/openpencil/NOTES.md
git-spice commit create --no-restack -m "docs(openpencil): add notes on identity, requirements and headless use" -m "Explain which OpenPencil this is, the glibc 2.39 requirement, the pinned prerelease version, headless commands, the op name conflict, and where the font notices are kept. release.yaml merges these notes into the generated README."
```

- [ ] **Step 5: Check the final change set (REQ-013)**

```bash
git diff --name-status main...HEAD
git ls-files -s src/openpencil/install.sh test/openpencil/openpencil-test.sh
test ! -e src/openpencil/README.md && echo NO_README
git diff --quiet main...HEAD -- .devcontainer.json .devcontainer && echo DEVCONTAINER_UNCHANGED
jq . src/openpencil/devcontainer-feature.json test/openpencil/scenarios.json > /dev/null && echo JSON_OK
bash -n src/openpencil/install.sh && bash -n test/openpencil/openpencil-test.sh && echo SYNTAX_OK
git status --porcelain
```

Expected:

```
A	src/openpencil/NOTES.md
A	src/openpencil/devcontainer-feature.json
A	src/openpencil/install.sh
A	test/openpencil/openpencil-test.sh
A	test/openpencil/scenarios.json
100755 ... src/openpencil/install.sh
100755 ... test/openpencil/openpencil-test.sh
NO_README
DEVCONTAINER_UNCHANGED
JSON_OK
SYNTAX_OK
```

and an empty `git status --porcelain`. If the branch is stacked on another unmerged branch, compare against that parent branch instead of `main` and expect the same five lines. Record the outputs of Task 2 Steps 6 and 10 and of this step in the bead notes so the summarize and review stages can cite them.

## Non-Goals

- Publishing the Feature to GHCR (`release.yaml` is manual and run by a human).
- Opening or merging the PR inside these tasks; the workflow's publish/finalize lifecycle does that.
- Any change to tascon-frontend (request items 2 and 3).
- Registering OpenPencil as an MCP server or skill (`op install`), and any `entrypoint` or lifecycle command.
- Support for glibc older than 2.39 (no shim, no source build), non-glibc bases, or architectures other than x86_64/aarch64.
- The GUI or live editor, `op start --web`, the `.deb`/AppImage packages, the VS Code extension and the AI features.
- An option to skip `openpencil-desktop`.
- Hard-coded expected SHA256 values in `install.sh` (design Approach B; requirements Q1 answered "no").
- Adding the Feature to this repository's `.devcontainer.json`, or committing `src/openpencil/README.md`.
- A scenario for the glibc-too-old path (the test library has no expected-failure scenario; Task 2 Step 6 covers it by hand).

## Validation and Acceptance

Local (in the implementation worktree, recorded in bead notes):

| Check | Where | Expected |
|-------|-------|----------|
| `bash -n` on both scripts | Task 1 Step 3, Task 2 Step 5, Task 3 Step 5 | `SYNTAX_OK` |
| `shellcheck -S warning` on both scripts, when available | Task 1 Step 5, Task 2 Step 7 | no warnings, or "not installed" recorded |
| `jq` on both JSON files, with content assertions | Task 1 Step 3, Task 2 Steps 2/8, Task 3 Step 5 | `true` / `JSON_OK` |
| Pre-download guards (`latest`, `0.8`, empty, non-root, glibc 2.36, `v0.8.5`) and no side effects | Task 2 Step 6 | seven `PASS` lines |
| Manual glibc-guard run as root (REQ-013) | Task 2 Step 6 | REQ-006 message, `exit=1`, no apt/curl output |
| Download source and step order | Task 2 Step 9 | single ZSeven-W URL; guard → apt → verify → extract order |
| Manual `sha256sum -c` of the four Linux assets | Task 2 Step 10 | four `OK` lines |
| `NOTES.md` sections and content | Task 3 Step 3 | `PASS` |
| Change set is exactly the five files, modes 100755, no README, `.devcontainer.json` unchanged | Task 3 Step 5 | listed output, clean tree |

CI (after the publish lifecycle opens the PR; acceptance evidence for REQ-012 and AC-5/AC-8):

- `test-scenarios (openpencil)`: the build log shows `Installed: {"version":"0.8.5"}` and `Done!`, and all eight `check` calls pass (`op_version`, `desktop_bin_env`, `no_missing_libraries`, `font_notices`, `headless_start`, `headless_status_running`, `headless_tools`, `headless_stop`).
- `validate.yml` accepts `src/openpencil/devcontainer-feature.json`.
- `all-tests` passes; the PR title is `feat(openpencil): ...` (semantic PR title check) with English title and body (PR language check).

Risks and fallbacks (unresolved ambiguity recorded here, per headless mode):

- `op start --headless` might not create a missing `--file` target. The earlier investigation wrote to a `.op` file but did not record whether it existed first. If `headless_start` fails in CI with a missing-file error, change the test so the file is created by OpenPencil itself (for example run `op start --headless` without `--file`, matching NOTES usage otherwise) and record the change; REQ-012 step a is the only line affected.
- `op stop` without `--port` might not find a server started on a non-default port. If `headless_stop` fails, use `op --port "${port}" stop` in both the check and the trap, and record it as a deviation from REQ-012 step d's literal command.
- Port 7391 might be taken in the CI container (requirements Q2). REQ-012 allows another fixed port; change only `port=` in the test.
- `op start --headless` might run in the foreground. `timeout 120` turns that into a failed `headless_start` check rather than a hung job; the fix would then be to start it in the background (`op ... start --headless ... &`) and keep the status retry loop.
- The CI runner is x86_64, so CI exercises only the x86_64 assets. The aarch64 path is covered by the manual checksum and archive listing in Task 2 Step 10 and by the shared code path.

## Decision Log

- 2026-11-21: plan-review で計画を承認。正式な plan/spec を保存する方針を採用。保存しない旨の旧記述はこの決定で変更。出典: /workspaces/devcontainer-features/.gc-artifacts/openpencil-feature/requirements.md, /workspaces/devcontainer-features/.gc-artifacts/openpencil-feature/brainstorming/design.md, /workspaces/devcontainer-features/.gc-artifacts/openpencil-feature/implementation-plan.md。
