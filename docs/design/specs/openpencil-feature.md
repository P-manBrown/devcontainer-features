# openpencil-feature specification

## Approved requirements

## Requirements: `openpencil` dev container Feature

- Workflow root: df-d38if (`superpowers-build`). Request: gc-gsid part 1 (bead df-mu87x).
- Source design (approved, autonomous, lane df-m9j7e): `/workspaces/devcontainer-features/.gc-artifacts/openpencil-feature/brainstorming/design.md`
- Design approval summary: `/workspaces/devcontainer-features/.gc-artifacts/openpencil-feature/brainstorming/design-approval.md`
- Spec mirror: none. This lane runs in the main checkout without its own worktree, and the main checkout belongs to the human, so no copy was written under `docs/superpowers/specs/`. This file is the only copy.
- Written: 2026-11-20, write-requirements-spec lane df-x2kl2, iteration 1, attempt 1.

### Problem Statement

The human decided to adopt OpenPencil from ZSeven-W/openpencil (https://github.com/ZSeven-W/openpencil). openpencil.dev (Danila Poyarkov) is a different project with the same name and must not be used. Request item 1:

> devcontainer-features に、ZSeven-W/openpencil の op CLI と、ヘッドレスで動かすための openpencil-desktop（Linux 版）を入れる Feature を作る。配布物は ZSeven-W/openpencil の GitHub Releases から取り、SHA256 で確かめる。最新は v0.8.5 で prerelease なので、版を固定する。

This repository has no Feature for it. Without one, every dev container that wants headless OpenPencil has to download, verify and place two binaries by hand. tascon-frontend (request item 2, bead tf-n64tm) waits on this Feature.

Facts that shape the solution (checked against the live v0.8.5 Release and source on 2026-11-20):

- Every upstream release from v0.8.0 to v0.8.5 is a prerelease, so `GET /releases/latest` returns no release.
- Linux assets: `op-cli-linux-{x86_64,aarch64}.tar.gz` (contains `op`) and `openpencil-desktop-linux-{x86_64,aarch64}.tar.gz` (contains `openpencil-desktop` and `font-notices/`). `SHA256SUMS.txt` lists every asset as `<64 hex>  <name>`.
- Both binaries need GLIBC_2.39. `openpencil-desktop` also links libz, libstdc++, libfontconfig and libfreetype.
- `op` finds the desktop binary through `OPENPENCIL_DESKTOP_BIN` first, then next to its own executable.
- `op --version` prints `{"version":"0.8.5"}`. `op start --headless [--file X.op]`, `op status`, `op tools` and `op stop` exist. `--port N` is a global flag (default 3100). When `--port` is given, `op status` and `op tools` use that port directly instead of discovery.
- `op status` exits 0 whether or not a server is running. It prints `{"running":true,...}` when the OpenPencil server answers and `{"running":false}` otherwise.
- The 1Password CLI also installs a binary named `op`.

### W6H

| Question | Answer |
|----------|--------|
| Who | Developers and AI agents in dev containers that need headless OpenPencil, first tascon-frontend. The maintainer of this repository reviews and merges. |
| What | A new Feature `openpencil` (`src/openpencil/`) and its test scenario (`test/openpencil/`). It installs `op` and `openpencil-desktop` from the ZSeven-W/openpencil v0.8.5 Release. |
| When | During dev container image build. The scenario test runs in CI on the PR. |
| Where | Container paths `/usr/local/share/openpencil/` and `/usr/local/bin/op`. Downloads only from `https://github.com/ZSeven-W/openpencil/releases/download/v<version>/`. |
| Why | The request asks for a Feature with SHA256 checking and a pinned version, so that `op start --headless` works in a container without manual steps. |
| Which | ZSeven-W/openpencil only. Linux x86_64 and aarch64 only. Bases with glibc 2.39 or later only (for example Ubuntu 24.04, Debian 13). |
| How | Approach A from the design: a `version` option with default `0.8.5`, each archive checked with `sha256sum -c` against the same Release's `SHA256SUMS.txt`, following the install pattern of `git-spice`, `rtk` and `codebase-memory-mcp`. |

### User Stories

- US-1: As a developer, I add `"ghcr.io/P-manBrown/devcontainer-features/openpencil": {}` to a glibc 2.39+ dev container, and after the build `op start --headless --file design.op` starts a headless MCP server with no further setup.
- US-2: As a developer on an older base (for example Debian 12, glibc 2.36), the build fails early with a message that names the glibc I have and the version I need, instead of failing later with a missing-symbol error.
- US-3: As a security-minded maintainer, I know every installed binary came from the ZSeven-W/openpencil Release and matched that Release's SHA256 list before it was unpacked.
- US-4: As a user who already has the 1Password CLI `op`, the Feature does not silently replace it.
- US-5: As a maintainer, moving to a newer upstream release means changing the option default and bumping the Feature version, nothing more.

### Technical Stories

- TS-1: `src/openpencil/devcontainer-feature.json` declares id, version, option and `containerEnv` (REQ-001, REQ-002).
- TS-2: `src/openpencil/install.sh` validates input and the environment before any download (REQ-002, REQ-005, REQ-006, REQ-009).
- TS-3: `install.sh` installs runtime libraries, downloads, verifies, unpacks and places the files, then checks itself (REQ-003, REQ-004, REQ-007, REQ-008, REQ-010).
- TS-4: `src/openpencil/NOTES.md` documents identity, requirements, version policy, headless use, conflicts and licences (REQ-011).
- TS-5: `test/openpencil/scenarios.json` and `test/openpencil/openpencil-test.sh` prove the install and a headless round trip in CI (REQ-012).
- TS-6: The change ships as one PR against `main` through the `git-spice-workflow` Skill (REQ-013).

### Behavior Requirements

Requirement IDs come from the approved design. Each one is a rule the implementation must satisfy.

#### REQ-001 Feature metadata

`src/openpencil/devcontainer-feature.json` contains:
- `id: "openpencil"`, `version: "1.0.0"`, `name: "OpenPencil (ZSeven-W)"`.
- `description` stating that it installs the ZSeven-W/openpencil `op` CLI and the headless `openpencil-desktop` binary from GitHub Releases, that glibc 2.39+ is required, and that it is not openpencil.dev.
- `documentationURL` `https://github.com/P-manBrown/devcontainer-features/tree/main/src/openpencil` and `licenseURL` `https://github.com/P-manBrown/devcontainer-features/blob/main/LICENSE`, in the same form as the other Features.
- `containerEnv`: `{"OPENPENCIL_DESKTOP_BIN": "/usr/local/share/openpencil/openpencil-desktop"}`.
- `installsAfter`: `["ghcr.io/devcontainers/features/common-utils"]`.
- No `entrypoint`, `mounts`, `postCreateCommand`, `postStartCommand` or other lifecycle command.

#### REQ-002 Pinned version option

- `options.version`: `type: "string"`, `default: "0.8.5"`, `proposals: ["0.8.5"]`, description `Exact ZSeven-W/openpencil release version (e.g. '0.8.5'). 'latest' is not supported: upstream publishes only prereleases.`
- `install.sh` reads `VERSION` (default `0.8.5` when unset) and removes one leading `v`.
- If the result is `latest`, empty, or does not match the extended regex `^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$`, the script exits non-zero before any download. The message says that upstream ships only prereleases and an exact version such as `0.8.5` is required.

#### REQ-003 Download source

- The only download base URL is `https://github.com/ZSeven-W/openpencil/releases/download/v${VERSION}/`.
- The script downloads exactly three files from it: `op-cli-linux-${arch}.tar.gz`, `openpencil-desktop-linux-${arch}.tar.gz` and `SHA256SUMS.txt`, with `curl -fsSL` (so an HTTP error such as 404 fails the build).
- Files go into `tmp_dir="$(mktemp -d)"`, removed by `trap 'rm -rf "${tmp_dir}"' EXIT`.
- No request goes to openpencil.dev, the Homebrew `openpencil` cask, upstream `install-op.sh`, or the GitHub API.

#### REQ-004 SHA256 verification before unpacking

- For each of the two archives, the script takes its line from `SHA256SUMS.txt` with `grep -E "^[[:xdigit:]]{64}[[:space:]]+\*?${asset//./\\.}$"`.
- If no line matches, it exits non-zero with `Checksum not found for <asset>`.
- Otherwise it pipes that line to `(cd "${tmp_dir}" && sha256sum -c -)`. A mismatch exits non-zero.
- Neither archive is unpacked until both checks have passed.

#### REQ-005 Preconditions

In this order, before any download:
- The script runs as root. Otherwise it exits with the same message block the other Features use.
- `curl` is on PATH. Otherwise it exits with an error naming `curl`.
- `uname -m` maps `x86_64` to `x86_64`, and `aarch64` or `arm64` to `aarch64`. Any other value exits with an error naming the value.

#### REQ-006 glibc guard

- Before any download (and before the apt step), the script runs `getconf GNU_LIBC_VERSION`.
- If the command fails, or its output does not start with `glibc ` (for example musl/Alpine), or the version is lower than `2.39` (compared with `sort -V`), the script exits non-zero with: `OpenPencil <version> requires glibc 2.39 or later (found: <found value or "unknown">). Use a base image such as Ubuntu 24.04 or Debian 13.`

#### REQ-007 Runtime libraries

- If `apt-get` is on PATH, the script runs `apt-get update`, then `apt-get install -y --no-install-recommends libfontconfig1 libfreetype6 zlib1g libstdc++6 ca-certificates`, then `rm -rf /var/lib/apt/lists/*`.
- If `apt-get` is not on PATH, the script skips this step. REQ-010 then catches any missing library.

#### REQ-008 Install layout and environment

- The script unpacks both archives into `${tmp_dir}/extract`. If `op` or `openpencil-desktop` is not found where the archive puts it, the script exits non-zero naming the missing file.
- It removes `/usr/local/share/openpencil/` if present, then creates it again, so a rebuild with another version leaves no old files.
- It installs `op` and `openpencil-desktop` there with `install -m 0755`, copies the archive's `font-notices/` directory there unchanged, and runs `ln -sfn /usr/local/share/openpencil/op /usr/local/bin/op`.
- Resulting layout:

```
/usr/local/bin/op -> /usr/local/share/openpencil/op
/usr/local/share/openpencil/op
/usr/local/share/openpencil/openpencil-desktop
/usr/local/share/openpencil/font-notices/   (NOTICE.txt and the OFL texts from the archive)
OPENPENCIL_DESKTOP_BIN=/usr/local/share/openpencil/openpencil-desktop   (containerEnv, REQ-001)
```

#### REQ-009 Existing `op` guard

- Before any download, if `/usr/local/bin/op` exists (as a file or symlink) and is not a symlink whose target is `/usr/local/share/openpencil/op`, the script exits non-zero. The message says another `op` (for example the 1Password CLI) is installed at `/usr/local/bin/op` and that it was not changed.
- A symlink that already points to `/usr/local/share/openpencil/op` (a rebuild) is allowed and replaced.

#### REQ-010 Build-time self-check

- `ldd /usr/local/share/openpencil/openpencil-desktop` and `ldd /usr/local/share/openpencil/op` must print no line containing `not found`. Otherwise the script exits non-zero and prints those lines.
- The script runs `/usr/local/bin/op --version`, prints `Installed: <output>`, and exits non-zero with a version mismatch error if the output does not contain `${VERSION}`.
- The last line the script prints on success is `Done!`.

#### REQ-011 Notes and generated README

`src/openpencil/NOTES.md` has these short sections:
- **Which OpenPencil**: ZSeven-W/openpencil with its URL. It is not openpencil.dev (Danila Poyarkov) or the Homebrew core `openpencil` cask.
- **Requirements**: glibc 2.39+ (for example Ubuntu 24.04, Debian 13), x86_64 or aarch64. Debian 12-based images (for example `node:22-bookworm`) fail at build time with a clear message.
- **Version**: pinned to 0.8.5 because upstream publishes only prereleases. `latest` is rejected. Each archive is checked against the Release's `SHA256SUMS.txt`.
- **Headless use**: `op start --headless --file design.op`, then `op status`, `op tools`, `op <tool> key=value`, `op stop`. `OPENPENCIL_DESKTOP_BIN` is preset.
- **Conflicts**: the install fails if another `/usr/local/bin/op` (for example the 1Password CLI) is present.
- **Licenses**: the font notices shipped with `openpencil-desktop` are kept in `/usr/local/share/openpencil/font-notices/`.

`src/openpencil/README.md` is not committed. `release.yaml` generates it.

#### REQ-012 Test scenario

`test/openpencil/scenarios.json` has exactly one scenario:

```json
{
  "openpencil-test": {
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "remoteUser": "vscode",
    "features": { "openpencil": {} }
  }
}
```

`test/openpencil/openpencil-test.sh` (`#!/bin/bash`, `set -e`, `source dev-container-features-test-lib`, `check` calls, `reportResults`) checks, each as one `check` call:
1. `op --version` output contains `0.8.5`.
2. `OPENPENCIL_DESKTOP_BIN` equals `/usr/local/share/openpencil/openpencil-desktop` and that file is executable.
3. `ldd` prints no `not found` line for either binary.
4. `/usr/local/share/openpencil/font-notices/NOTICE.txt` exists.
5. Headless round trip, run as the scenario's `vscode` user in a directory made with `mktemp -d`, with the fixed port `7391` (the implementer may choose another fixed port if 7391 is taken in CI, and uses the same port for steps a-c):
   - a. `op --port 7391 start --headless --file "$dir/t.op"` exits 0.
   - b. `op --port 7391 status` output contains `"running":true`. The exit code alone is not enough, because `op status` exits 0 when no server runs.
   - c. `op --port 7391 tools` exits 0 and its output contains `"name"`.
   - d. `op stop` exits 0.
   The script sets a `trap` that runs `op stop` (ignoring its result) on exit, so a failed check does not leave the server running.

The glibc-too-old path has no scenario: the test library has no expected-failure scenario. It is checked by hand (REQ-013).

#### REQ-013 Delivery and verification

- Changed files are exactly: `src/openpencil/devcontainer-feature.json`, `src/openpencil/install.sh` (mode 0755), `src/openpencil/NOTES.md`, `test/openpencil/scenarios.json`, `test/openpencil/openpencil-test.sh`. No other Feature's files change, and this repository's own `.devcontainer.json` does not get the Feature (its glibc is 2.36).
- One branch and one PR against `main` through the repository's `git-spice-workflow` Skill, with Conventional Commit type and scope `feat(openpencil)`.
- Before the PR, the implementer runs and records: `bash -n` on both scripts; `shellcheck` on both scripts when it is installed; `jq .` on both JSON files; a manual download of the four Linux assets plus `SHA256SUMS.txt` from the v0.8.5 Release and `sha256sum -c` on them; and the manual glibc-guard check: run `install.sh` as root with `VERSION=0.8.5` in this dev container (Debian 12, glibc 2.36) and confirm it exits non-zero with the REQ-006 message before any download.
- The scenario test runs only in CI (no Docker in this dev container). The CI `test-scenarios` entry for `openpencil` and the `all-tests` check are the acceptance evidence for REQ-012.

#### Coverage

| ID | Requirement | Status |
|----|-------------|--------|
| REQ-001 | Feature metadata | covered |
| REQ-002 | Pinned version option | covered |
| REQ-003 | Download source | covered |
| REQ-004 | SHA256 verification before unpacking | covered |
| REQ-005 | Preconditions | covered |
| REQ-006 | glibc guard | covered |
| REQ-007 | Runtime libraries | covered |
| REQ-008 | Install layout and environment | covered |
| REQ-009 | Existing `op` guard | covered |
| REQ-010 | Build-time self-check | covered |
| REQ-011 | Notes and generated README | covered |
| REQ-012 | Test scenario | covered |
| REQ-013 | Delivery and verification | covered |

### Example Mapping

| Rule | Example | Expected result |
|------|---------|-----------------|
| REQ-002 default version | No options set | Installs 0.8.5; `op --version` prints `{"version":"0.8.5"}` |
| REQ-002 leading `v` | `version: "v0.8.5"` | Treated as `0.8.5` |
| REQ-002 `latest` rejected | `version: "latest"` | Build fails before download; message asks for an exact version |
| REQ-002 malformed | `version: "0.8"` | Build fails before download |
| REQ-003 unknown tag | `version: "9.9.9"` | `curl -f` gets 404; build fails |
| REQ-004 checksum mismatch | Archive bytes differ from `SHA256SUMS.txt` | `sha256sum -c` fails; nothing unpacked; build fails |
| REQ-004 missing line | Asset not listed in `SHA256SUMS.txt` | `Checksum not found for <asset>`; build fails |
| REQ-005 arch | `uname -m` = `arm64` | Downloads the `aarch64` assets |
| REQ-005 arch | `uname -m` = `riscv64` | Build fails naming `riscv64` |
| REQ-006 old glibc | Debian 12 (glibc 2.36) | Build fails before download with the REQ-006 message showing `glibc 2.36` |
| REQ-006 non-glibc | Alpine (musl, `getconf GNU_LIBC_VERSION` fails) | Build fails with `found: unknown` |
| REQ-006 OK | `base:ubuntu` (Ubuntu 24.04, glibc 2.39) | Guard passes |
| REQ-009 1Password `op` present | `/usr/local/bin/op` is a regular file | Build fails; the file is unchanged |
| REQ-009 rebuild | `/usr/local/bin/op` -> `/usr/local/share/openpencil/op` | Allowed; link recreated |
| REQ-008 version change | Rebuild with another valid version | `/usr/local/share/openpencil/` replaced as a whole |
| REQ-010 missing library | Base without apt and without libfontconfig | `ldd` shows `not found`; build fails listing it |
| REQ-012 status check | Server not running | `op --port 7391 status` prints `{"running":false}` with exit 0; the check fails because `"running":true` is absent |

### Acceptance Criteria

| AC | Criterion | Evidence | Requirements |
|----|-----------|----------|--------------|
| AC-1 | `src/openpencil/` contains `devcontainer-feature.json` (id `openpencil`, version `1.0.0`, `version` default `0.8.5`, `containerEnv.OPENPENCIL_DESKTOP_BIN`), an executable `install.sh` and `NOTES.md`, and no `README.md`. | PR diff, `jq .`, `git ls-files -s` mode 100755 | REQ-001, REQ-002, REQ-011 |
| AC-2 | `install.sh` downloads only from `github.com/ZSeven-W/openpencil/releases/download/v<version>/` and checks both archives with `sha256sum -c` against that Release's `SHA256SUMS.txt` before unpacking either. | Code review of `install.sh`; manual `sha256sum -c` of the four assets | REQ-003, REQ-004 |
| AC-3 | `version` = `latest`, empty or malformed fails the build with the REQ-002 message. The default installs 0.8.5. | Code review; CI scenario (`op --version`) | REQ-002 |
| AC-4 | On glibc < 2.39 the build fails before any download with the REQ-006 message. | Recorded output of the manual run in this dev container | REQ-005, REQ-006 |
| AC-5 | On `mcr.microsoft.com/devcontainers/base:ubuntu` the `openpencil-test` scenario passes in CI, including the headless round trip with `"running":true` from `op status`. | CI `test-scenarios` (openpencil) result | REQ-007, REQ-008, REQ-010, REQ-012 |
| AC-6 | An existing non-OpenPencil `/usr/local/bin/op` is never overwritten. | Code review of the REQ-009 guard (runs before download) | REQ-009 |
| AC-7 | `NOTES.md` names ZSeven-W, warns about openpencil.dev and the Homebrew core cask, and states the glibc 2.39 requirement and the pinned version. | PR diff | REQ-011 |
| AC-8 | CI `all-tests` passes, the PR changes only the five listed files, and the PR is created through `git-spice-workflow` with type `feat(openpencil)`. | PR checks and file list | REQ-013 |

### Out Of Scope

- Publishing the Feature to GHCR. `release.yaml` is `workflow_dispatch` only and a human runs it.
- Changing tascon-frontend (base image, Feature use, docs). Those are request items 2 and 3.
- Registering OpenPencil as an MCP server or skill for Claude Code or Codex (`op install`), and any entrypoint or lifecycle hook.
- Support for glibc older than 2.39: no shim, no build from source.
- The GUI or live editor (`op start` without `--headless`, `op start --web`), the `.deb` and AppImage packages, the VS Code extension and the AI features.
- An option to skip `openpencil-desktop`.
- Adding the Feature to this repository's own `.devcontainer.json`.
- Committing `src/openpencil/README.md`.
- Expected SHA256 values written into `install.sh` (design Approach B). See Open Questions.

### Open Questions

None block planning or implementation. Each has a recorded answer that reviewers can override:

- Q1: Should `install.sh` also hold the four expected SHA256 values (design Approach B) to detect upstream replacing a Release asset together with its `SHA256SUMS.txt` line? Answer for this build: no. The request asks only for SHA256 checking, and Approach A matches the repository's existing pattern. Adopting B later does not change the Feature's interface.
- Q2: Is port 7391 free in the CI scenario container? Assumed yes (a fresh container with no other services). If it is taken, the implementer picks another fixed port and uses it in steps a-c of REQ-012.

## Adopted design

## Design candidate: `openpencil` dev container Feature

- Root bead: df-d38if (superpowers-build). Lane bead: df-jol04. Request: gc-gsid part 1 (df-mu87x).
- Iteration: 1 (attempt 1). Approval mode: autonomous.
- Approval status: **approved (autonomous, design-approval lane df-m9j7e, 2026-11-20). See `design-approval.md` next to this file.**

### Checklist state (Superpowers brainstorming items 1-5)

| # | Item | State |
|---|------|-------|
| 1 | Project context inspected | Done. See "Project context". |
| 2 | Visual companion decision | Not offered: no visual questions (CLI install Feature, no UI). |
| 3 | Clarifying questions | None needed a human. The request and upstream facts settle every decision; assumptions are listed under "Decisions taken autonomously". |
| 4 | Approaches with tradeoffs | Done. Three approaches, recommendation A. |
| 5 | Design in sections | Done. Sections 1-6 below. |

### Requested outcome

Request text (human mail gc-wisp-c62lv4, quoted in df-mu87x):

> OpenPencil を導入する（人の決定）。使うのは ZSeven-W/openpencil（作者 ZSeven-W、https://github.com/ZSeven-W/openpencil）。openpencil.dev（作者 Danila Poyarkov）は同じ名前の別物で、使わない。
> 1. devcontainer-features に、ZSeven-W/openpencil の op CLI と、ヘッドレスで動かすための openpencil-desktop（Linux 版）を入れる Feature を作る。配布物は ZSeven-W/openpencil の GitHub Releases から取り、SHA256 で確かめる。最新は v0.8.5 で prerelease なので、版を固定する。

The part is done when the Feature's PR is merged into `main`. The tascon-frontend part (request item 2, bead tf-n64tm) then uses the Feature on a glibc 2.39+ base.

In short: add `src/openpencil` and `test/openpencil`. The Feature installs the `op` CLI and the `openpencil-desktop` Linux binary from the ZSeven-W/openpencil v0.8.5 GitHub Release, checks each archive against SHA256, and makes `op start --headless` work without extra setup.

### Project context (checked 2026-11-20)

Repository:
- Features live in `src/<id>/` (`devcontainer-feature.json`, `install.sh`, optional `NOTES.md`). Tests live in `test/<id>/` (`scenarios.json` plus one `<scenario>.sh` per scenario). CI runs `devcontainer features test -f <id> --skip-autogenerated .`, so only scenarios run. New Features are picked up automatically (the `plan` job lists `src/*/devcontainer-feature.json`).
- The `README.md` files under `src/<id>/` are generated by `release.yaml` (workflow_dispatch only, run by a human) from the JSON plus `NOTES.md`. Newly added Features (for example `bmad`) do not commit a README.
- Pattern for binaries from GitHub Releases (`git-spice`, `rtk`, `codebase-memory-mcp`): root check, `curl` presence check, `uname -m` → asset arch (`x86_64`/`aarch64`), download the asset and the release's checksum file into a `mktemp -d` cleaned by `trap`, `grep` the exact line for the asset, run `sha256sum -c`, install with `install -m 0755`, and finish with `echo "Done!"`. Scripts use `set -eu`, tab indentation, and an `err()` helper that prints in red.
- Test scenarios use `mcr.microsoft.com/devcontainers/base:ubuntu` with `remoteUser: vscode`. That image is Ubuntu 24.04 (glibc 2.39).
- No Docker in this dev container (Debian 12, glibc 2.36). Scenario tests can only run in CI. The repository's own `.devcontainer.json` must not get this Feature, because its glibc is too old.

Upstream ZSeven-W/openpencil v0.8.5 (checked against the live Release):
- Every release v0.8.0 to v0.8.5 is marked prerelease. `GET /releases/latest` therefore has no stable release to return, so the repo's usual `latest` resolution cannot work.
- Linux assets: `op-cli-linux-{x86_64,aarch64}.tar.gz` (the `op` binary only, about 3.5 MB) and `openpencil-desktop-linux-{x86_64,aarch64}.tar.gz` (the `openpencil-desktop` binary, 162-173 MB unpacked, plus `font-notices/` with OFL texts and NOTICE.txt).
- `SHA256SUMS.txt` lists every asset in `<64 hex>  <name>` format. All four Linux tarballs verified OK with `sha256sum -c` on 2026-11-20:
  - `op-cli-linux-aarch64.tar.gz` 47b6a85ae7508bc67c4508636fdb113679836d0be8d06ccea07c90217bffed29
  - `op-cli-linux-x86_64.tar.gz` 5bce59ac406048c08a4fd7f04a5f8761d0a29cfe0d3873743e916e642b4df5e4
  - `openpencil-desktop-linux-aarch64.tar.gz` 3ed57eab1239147ed861cd3f18b4df9fbe0544ae412fc763c41d4a1577c1be58
  - `openpencil-desktop-linux-x86_64.tar.gz` 0e554f611e6406d9819e35e204a640586cf656cb5b4ad051b0a31c2783046b24
- ELF requirements (from `readelf`, both arches): `op` needs libc, libm, libgcc_s and GLIBC_2.39. `openpencil-desktop` additionally needs libz, libstdc++, libfontconfig and libfreetype, and also GLIBC_2.39.
- `op` finds the desktop binary like this (`crates/op-cli/src/app_control_cli.rs`, `find_desktop_binary`): it uses `OPENPENCIL_DESKTOP_BIN` if set (and errors if that file is missing); otherwise it looks for `openpencil-desktop` or `OpenPencil` next to `current_exe()`, then `./target/{debug,release}/`.
- `op --version` exists and prints `{"version":"0.8.5"}` (`version_json()` in `command_helpers.rs`, using `CARGO_PKG_VERSION`; the string is also in the binary). `op start --headless [--file X.op] [--port N]`, `op status` and `op stop` exist (usage.txt).
- Earlier investigation (tascon-frontend tf-uwqi5.1, tf-uwqi5.2) confirmed `op start --headless` serves MCP over HTTP with 179 tools, writes `.op` files, and can export PNG with `--item`, once glibc 2.39 is available.
- Name collision: the 1Password CLI also installs a binary named `op`.

### Constraints

- Download only from `https://github.com/ZSeven-W/openpencil/releases/download/v<version>/`. Never from openpencil.dev, the Homebrew `openpencil` cask, or the `install-op.sh` curl|bash route.
- Check every downloaded archive with SHA256 before unpacking it.
- Pin the version: the default is `0.8.5`, and `latest` is not supported.
- glibc ≥ 2.39 on the target image, on x86_64 or aarch64 Linux only.
- Follow the existing Feature script conventions listed above.

### Non-goals

- Publishing to GHCR. `release.yaml` is manual and a human runs it.
- Changing tascon-frontend (its base image, Feature use, docs). That is request items 2 and 3.
- Registering OpenPencil as an MCP server or skill for Claude Code or Codex (`op install`), and any entrypoint or postStart hook.
- Support for older glibc: no glibc shim and no build from source.
- The GUI or live editor (`op start` without `--headless`, `op start --web`), the `.deb`/AppImage packages, the VS Code extension, and the AI features.
- An option to skip the desktop binary. The request asks for both.
- Adding the Feature to this repository's own `.devcontainer.json`.
- Committing `src/openpencil/README.md`. It is generated on release.

### Approaches

**A. Version option pinned to 0.8.5 and checked against the release's `SHA256SUMS.txt` (recommended).**
`install.sh` downloads both tarballs and `SHA256SUMS.txt` from the pinned tag, `grep`s the exact line for each asset, and runs `sha256sum -c`. The `version` option defaults to `0.8.5`. A user can still name another tag, and that tag is checked against its own `SHA256SUMS.txt`.
- Pros: the same mechanism as git-spice, rtk and codebase-memory-mcp, so reviewers and maintainers already know it. Moving to a new upstream release means changing one default and bumping the Feature version. It meets "SHA256 で確かめる" and "版を固定する".
- Cons: the checksums come from the same Release as the archives. If the upstream maintainer replaced an asset together with its `SHA256SUMS.txt` line, the check would not catch it. The check guards against corruption and tampering in transit, not against changes to the Release itself.

**B. Expected SHA256 values written into `install.sh`, with the version fixed by an enum.**
`install.sh` holds a table of the four hashes for 0.8.5 (`version` is `enum: ["0.8.5"]`) and checks against it. This is what upstream's own `install-op.sh` does for `op`.
- Pros: strongest pinning. A later change to the Release assets fails the build.
- Cons: every upgrade means copying four hashes by hand. Users cannot pick another version without a new Feature release. It departs from the repo's existing pattern, and a hand-copied hash table is a new kind of thing to review.

**C. Install upstream's `.deb` (GUI package) plus `install-op.sh`.**
- Pros: uses upstream's packaging.
- Cons: the `.deb` is the desktop GUI app with a dependency closure we do not need, and it is a different artifact from the `openpencil-desktop` headless binary that `op start --headless` was verified with. `install-op.sh` is curl|bash, and it only pins `op`, not the desktop binary. Rejected.

**Recommendation: A.** It satisfies every stated requirement, matches the repository's established pattern, and keeps upgrades to a one-line change. The extra protection of B covers a threat (the upstream maintainer replacing assets) that the request does not mention. Because B can be adopted later without changing the Feature's interface, it is recorded as an option rather than a requirement (see "Unresolved questions").

### Design

#### 1. Feature metadata — `src/openpencil/devcontainer-feature.json`

- `id: "openpencil"`, `version: "1.0.0"`, `name: "OpenPencil (ZSeven-W)"`.
- `description`: installs the ZSeven-W/openpencil `op` CLI and the headless `openpencil-desktop` binary from GitHub Releases. It states that glibc 2.39+ is required and that this is not openpencil.dev.
- `documentationURL`, `licenseURL` follow the other Features (`.../tree/main/src/openpencil`, `.../blob/main/LICENSE`).
- `options.version`: `type: string`, `default: "0.8.5"`, `proposals: ["0.8.5"]`, description "Exact ZSeven-W/openpencil release version (e.g. '0.8.5'). 'latest' is not supported: upstream publishes only prereleases."
- `containerEnv`: `OPENPENCIL_DESKTOP_BIN=/usr/local/share/openpencil/openpencil-desktop`, so `op start --headless` finds the binary without depending on how `current_exe()` resolves symlinks.
- `installsAfter`: `ghcr.io/devcontainers/features/common-utils`.
- No `entrypoint`, `mounts` or lifecycle commands.

#### 2. Install script — `src/openpencil/install.sh`

These steps run in order. Any failure exits non-zero through `err()` with a message that names the problem.

1. Read `VERSION` (default `0.8.5`) and remove one leading `v`. If the value is `latest`, empty, or not of the form `[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?`, exit with an error that says upstream ships only prereleases and an exact version is needed.
2. Check that the script runs as root (the same message block as the other Features) and that `curl` is present.
3. Map `uname -m`: `x86_64` → `x86_64`, `aarch64|arm64` → `aarch64`. Anything else is an error.
4. Check glibc. Read `getconf GNU_LIBC_VERSION` (expected `glibc X.Y`). If the command fails or the output does not start with `glibc` (musl/Alpine), or `X.Y` is older than 2.39 (compared with `sort -V`), exit with: "OpenPencil <ver> requires glibc 2.39 or later (found: …). Use a base image such as Ubuntu 24.04 or Debian 13." This runs before any download.
5. Runtime libraries. If `apt-get` exists, run `apt-get update` and `apt-get install -y --no-install-recommends libfontconfig1 libfreetype6 zlib1g libstdc++6 ca-certificates`, then `rm -rf /var/lib/apt/lists/*`. If `apt-get` is missing, skip the install and rely on step 9 to catch missing libraries.
6. Name collision check. If `/usr/local/bin/op` exists and is not a symlink to `/usr/local/share/openpencil/op`, exit with an error that says another `op` (for example the 1Password CLI) is installed. Do not overwrite it.
7. Download into `tmp_dir="$(mktemp -d)"` (`trap 'rm -rf "${tmp_dir}"' EXIT`) from `https://github.com/ZSeven-W/openpencil/releases/download/v${VERSION}/`:
   `op-cli-linux-${arch}.tar.gz`, `openpencil-desktop-linux-${arch}.tar.gz`, `SHA256SUMS.txt`.
   For each archive, take the line with `grep -E "^[[:xdigit:]]{64}[[:space:]]+\\*?${asset//./\\.}$"`. Exit with "Checksum not found for <asset>" if there is none, then pipe it to `(cd "${tmp_dir}" && sha256sum -c -)`. No archive is unpacked before both checks pass.
8. Install. Unpack both archives into `${tmp_dir}/extract`. Replace `/usr/local/share/openpencil/` as a whole (`rm -rf`, then `mkdir -p`) so a rebuild with another version leaves no stale files. Install `op` and `openpencil-desktop` there with `install -m 0755`, copy `font-notices/` there unchanged to keep the OFL notices, and `ln -sfn /usr/local/share/openpencil/op /usr/local/bin/op`. If either expected file is missing from its archive, exit with an error.
9. Self-check at build time:
   - `ldd /usr/local/share/openpencil/openpencil-desktop` and `ldd …/op` must contain no `not found` line. Otherwise exit, listing the missing libraries.
   - Run `/usr/local/bin/op --version` and print `Installed: <output>`. The output must contain `${VERSION}`; otherwise exit with a version mismatch error.
10. `echo "Done!"`.

Layout after install:
```
/usr/local/bin/op -> /usr/local/share/openpencil/op
/usr/local/share/openpencil/op
/usr/local/share/openpencil/openpencil-desktop
/usr/local/share/openpencil/font-notices/{NOTICE.txt,OFL-*.txt}
ENV OPENPENCIL_DESKTOP_BIN=/usr/local/share/openpencil/openpencil-desktop
```

#### 3. Notes — `src/openpencil/NOTES.md`

These are short sections. The generated README includes them.
- **Which OpenPencil**: this is ZSeven-W/openpencil (https://github.com/ZSeven-W/openpencil). It is not openpencil.dev (Danila Poyarkov) or the Homebrew core `openpencil` cask, which are different projects with the same name.
- **Requirements**: glibc 2.39+ (for example Ubuntu 24.04, Debian 13), x86_64 or aarch64. Debian 12-based images (for example `node:22-bookworm`) fail at build time with a clear message.
- **Version**: pinned to 0.8.5 because upstream publishes only prereleases. `latest` is not accepted. Each archive is checked against the Release's `SHA256SUMS.txt`.
- **Headless use**: `op start --headless --file design.op` then `op status`, `op tools`, `op <tool> key=value`, `op stop`. `OPENPENCIL_DESKTOP_BIN` is preset.
- **Conflicts**: the install fails if another `/usr/local/bin/op` (for example the 1Password CLI) is present.
- **Licenses**: the font notices shipped with `openpencil-desktop` are kept in `/usr/local/share/openpencil/font-notices/`.

#### 4. Tests — `test/openpencil/`

`scenarios.json`:
```json
{
  "openpencil-test": {
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "remoteUser": "vscode",
    "features": { "openpencil": {} }
  }
}
```
`openpencil-test.sh` (`source dev-container-features-test-lib`, then `check` calls, then `reportResults`):
- `op` is on PATH and `op --version` contains `0.8.5`.
- `OPENPENCIL_DESKTOP_BIN` is set to `/usr/local/share/openpencil/openpencil-desktop`, and that file is executable.
- `ldd` shows no `not found` for either binary.
- `font-notices/NOTICE.txt` exists.
- Headless round trip, as the `vscode` user, in a `mktemp -d` directory with a fixed unused port (for example 7391):
  1. `op start --headless --file "$dir/t.op" --port 7391` succeeds.
  2. `op status` reports reachable.
  3. `op tools` lists at least one tool.
  4. `op stop` succeeds.
  The script stops the server in a `trap` so a failing check does not leave it running. Each step is one `check` call.

No scenario covers the glibc-too-old failure. The test library has no expected-failure scenario, and the guard is simple. The implementer checks the guard by hand in this dev container (glibc 2.36): run `install.sh` with `VERSION=0.8.5` as root in a throwaway shell, expect the exit message from step 4, and record the output.

#### 5. Error handling summary

| Condition | Result |
|-----------|--------|
| `version` = `latest`, empty, or malformed | Build fails before download; message explains exact versions are required. |
| Not root, or no `curl` | Build fails (same messages as other Features). |
| Unsupported arch | Build fails naming `uname -m`. |
| glibc < 2.39 or non-glibc | Build fails before download, naming the found version. |
| Another `/usr/local/bin/op` | Build fails, nothing overwritten. |
| Download 404 (wrong version) | `curl -f` fails the build. |
| Missing checksum line, or mismatch | Build fails; nothing unpacked. |
| Missing shared library | Build fails listing the `not found` lines. |
| `op --version` does not match | Build fails. |

#### 6. Delivery

- Files: `src/openpencil/devcontainer-feature.json`, `src/openpencil/install.sh` (executable), `src/openpencil/NOTES.md`, `test/openpencil/scenarios.json`, `test/openpencil/openpencil-test.sh`.
- One branch and PR against `main` through the repository's `git-spice-workflow` Skill. Conventional Commit type `feat(openpencil)`.
- Verification before the PR: `bash -n` and `shellcheck` (if available) on both scripts, `jq .` on the JSON files, the manual glibc-guard check above, and a manual download plus `sha256sum -c` of the four assets. The scenario test runs in CI (`test-scenarios` matrix entry `openpencil`). The CI result is the acceptance evidence for the headless round trip.

### Acceptance criteria

1. `src/openpencil/` contains `devcontainer-feature.json` (id `openpencil`, version `1.0.0`, `version` option default `0.8.5`, `containerEnv.OPENPENCIL_DESKTOP_BIN`), an executable `install.sh`, and `NOTES.md`. There is no committed `README.md`.
2. `install.sh` downloads only from `github.com/ZSeven-W/openpencil/releases/download/v<version>/`, and checks both archives against that Release's `SHA256SUMS.txt` with `sha256sum -c` before unpacking either.
3. `version` = `latest` (or empty or malformed) fails the build with a clear message. The default installs 0.8.5.
4. On glibc < 2.39 the build fails before any download, with the message from design step 4. This is shown by the manual run on this dev container.
5. On `mcr.microsoft.com/devcontainers/base:ubuntu`, the `openpencil-test` scenario passes in CI: `op --version` shows 0.8.5, `OPENPENCIL_DESKTOP_BIN` points to an executable `openpencil-desktop`, no missing shared libraries, and `op start --headless` → `op status` → `op tools` → `op stop` all succeed.
6. An existing non-OpenPencil `/usr/local/bin/op` is never overwritten.
7. `NOTES.md` names ZSeven-W as the author, warns about openpencil.dev and the Homebrew core cask, and states the glibc 2.39 requirement and the pinned version.
8. The CI `all-tests` check passes, and no other Feature's files change.

### Decisions taken autonomously (assumptions)

- The checksum source is the Release's `SHA256SUMS.txt` (Approach A). The request asks for SHA256 checking without naming a source. Approach A matches the repository's pattern.
- The `version` option is kept with a pinned default, and `latest` is rejected, rather than removing the option. This is the smallest departure from the other Features while still pinning.
- No option to skip `openpencil-desktop`, because the request asks for both binaries.
- Runtime libraries are installed through apt when `apt-get` exists. Bases without apt rely on the `ldd` check.
- Install location `/usr/local/share/openpencil/` with a `/usr/local/bin/op` symlink and `containerEnv` for the desktop path.
- The existing-`op` guard fails the build rather than overwriting the other binary.

### Autonomous approval basis

The request names the source repository, the two artifacts, the version, the checksum requirement and the target repository. Upstream facts (asset names, `SHA256SUMS.txt` format, glibc 2.39, how `op` finds `openpencil-desktop`) were checked against the live v0.8.5 Release and source on 2026-11-20. The repository's Feature conventions settle the remaining structure. No decision left needs a human preference that the request and context do not already settle. The items above are recorded as assumptions that reviewers can override.

### Unresolved questions

None block the work. One is open for review, with no human answer needed to proceed:
- Should the build also pin the four expected SHA256 values in `install.sh` (Approach B), to detect upstream replacing a Release asset? The current answer is no (Approach A). Adopting B later does not change the Feature's interface.

