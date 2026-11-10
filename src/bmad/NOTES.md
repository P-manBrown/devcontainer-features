## Versions and dependencies

`version` accepts an exact stable BMAD version or `latest` (default). `latest` resolves the official npm stable tag once at image build time. There is no Feature-specific allowlist of BMAD versions. An uncached rebuild can obtain a newer stable release without a Feature update; restarts and project setup reuse the release already installed in the image.

The selected release's official installer and bundled module registry select TEA, including any compatibility pin published by BMAD. For example, the 6.12.3 and 6.12.4 registries select TEA 1.27.2. During the image build, the Feature performs a template installation and records the actual stable Core/BMM and TEA versions. Runtime project setup uses those exact versions and explicitly pins the recorded TEA release, so TEA cannot independently float to a newer release at container startup.

Specify `version: "6.12.4"` to reproduce that BMAD release and its official module selection. npm records the dependency tree in the image's runtime lockfile; transitive npm dependency resolution can differ between fresh image builds. No repository lockfile forces another BMAD version over the requested one.

This integration uses the official `bmad install` interface, project Skills, and `_bmad` configuration format. A release with an incompatible installer API, output format, or dependency engine requirement can still fail with an actual installation error. In particular, v7 preview uses a different installation model and is not selected as a preview by `latest`; a future stable migration may require adapting this integration. New versions are not rejected simply because they are absent from a Feature-maintained table.

`modules` accepts `bmm` (default) or `bmm,tea`. `tools` accepts `claude-code`, `codex` (default), or `claude-code,codex`. Each language option accepts `English` or `Japanese` (default).

The AI CLIs themselves are separate: add this repository's `claude-code` and/or `codex` Feature as needed. `tools` selects BMAD integration only. Both integrations share one project `_bmad` configuration. The official installer creates project skills in `.claude/skills` (Claude Code) and `.agents/skills` (Codex).

Following the existing `claude-mem`/`bruno-cli` approach, this Feature owns dependency checks instead of relying on Feature ordering or `dependsOn` (older Zed implementations have ignored dependency ordering). It checks versions **as the remote user** with the runtime PATH:

| Tool | Reuse requirement | Missing/older version |
| --- | --- | --- |
| Node.js / npm | Node 20.x >=20.12.0 or >=22, and working npm | Private Node 22.16.0 distribution, with SHA-256 verification |
| Python | Python >=3.11 | Private CPython 3.11.14, installed by uv during the image build |
| uv | >=0.9.5 | Private uv 0.9.5 distribution, with SHA-256 verification |
| Git | >=2.25 | Install the distribution's `git` package; fail if the remote user's selected Git is still too old/inaccessible |

The base must be a glibc Debian/Ubuntu Linux image, x86_64 or aarch64, with Bash and standard GNU tools. Fallbacks live in `/usr/local/share/bmad-feature`, ahead of the existing PATH; existing system/user tool files are not replaced. Compatible existing tools are reused, so their versions remain the base image's responsibility. Keep that image pinned when exact dependency reproduction is required. Distribution Git installation follows the base image's apt repositories.

`UV_PYTHON_DOWNLOADS=never` prevents deferred interpreter downloads. uv can still obtain script-specific Python packages declared by upstream scripts (for example ruamel.yaml); this Feature does not install a project test framework, browser, MCP server, or CI configuration. TEA settings use the selected release’s official defaults. This Feature does not override Playwright/Pact utility integration, Pact MCP, or browser automation settings. These settings govern TEA workflow behavior; enabling them does not install project dependencies during Feature setup. Change them afterwards through BMAD’s official customization mechanism.

## Workspace setup and Zed

Tools are installed at image build time, without accessing a user repository. Project setup normally runs through the Feature’s `postStartCommand`, from the workspace and as the configured remote user. No workspace environment variable is required when the editor runs Feature lifecycle hooks:

```jsonc
"features": {
  "ghcr.io/P-manBrown/devcontainer-features/bmad:1": {
    "modules": "bmm,tea",
    "tools": "claude-code,codex",
    "communicationLanguage": "Japanese",
    "documentOutputLanguage": "Japanese"
  }
}
```

For editors relying on the entrypoint instead of lifecycle hooks, add this to the consuming `devcontainer.json`:

```jsonc
"containerEnv": {
  "BMAD_WORKSPACE": "${containerWorkspaceFolder}"
}
```

This fallback needs an explicit absolute mounted project path because an entrypoint has no guaranteed workspace working directory. Feature `containerEnv` is applied at image build time, so placing `${containerWorkspaceFolder}` there does not provide a portable runtime workspace value. Use an absolute mounted project path for `BMAD_WORKSPACE`. The entrypoint deliberately skips setup if it is unset, rather than guessing among `/workspaces` directories. A `postStartCommand` also runs setup from the workspace for implementations supporting Feature lifecycle hooks. Concurrent invocations are serialized per workspace/user. The image provides `bmad-setup [absolute-project-path]` for explicit invocation; it does not place helper scripts or documentation in the project.

Zed's current source implements both lifecycle scripts and Feature entrypoints, but older versions have reported lifecycle/ordering problems. Its Feature entrypoints run only with `overrideCommand: true`; set that explicitly where necessary. Compose/`overrideCommand: false` configurations need working lifecycle support or an explicit `bmad-setup` invocation. Neither Zed GUI behavior nor Docker lifecycle execution is guaranteed by source inspection; test the configuration on your editor/version. This Feature does not depend on `postCreateCommand`.

An inaccessible, missing, or unwritable workspace fails setup without changing ownership of the repository. Correct the workspace mount's permissions instead. A setup failure is reported and retried at the next setup invocation; no success marker is written until the installer and checks succeed.

## Persistence and customization

All durable BMAD data is **in the mounted workspace**, independently for each project:

- `_bmad/config.toml` and `_bmad/config.user.toml`: official install answers (regenerated by the installer).
- `_bmad/custom/config.toml`: durable team overrides; may be committed.
- `_bmad/custom/config.user.toml`: durable personal overrides, ignored by the official generated `_bmad/custom/.gitignore`.
- Other files under `_bmad/custom/`: official skill/agent/workflow customizations.
- `_bmad-output/` (or the configured output path): generated project artifacts.

No additional named volume is declared: overlaying these paths would hide existing project data. The existing workspace bind mount or workspace named volume must itself survive container deletion/rebuild. This applies equally to new and reused workspace volumes; deleting the underlying workspace is outside this Feature's persistence guarantee. No home-directory BMAD customization is created. External module source caches are disposable image/temporary program data, not user settings. Temporary installer homes are discarded after setup, and no persistent volume can leave an old CLI in front of the rebuilt image.

Initial language options apply only to a new BMAD installation. Changing Feature language options afterwards does **not** override existing answers. For durable changes, use the official four-layer configuration; later layers win:

1. `_bmad/config.toml`
2. `_bmad/config.user.toml`
3. `_bmad/custom/config.toml`
4. `_bmad/custom/config.user.toml`

For example, put this in the appropriate custom file:

```toml
[core]
communication_language = "Japanese"
document_output_language = "English"
```

No personal name is a shared Feature option. The initial neutral name is `BMad`; set `core.user_name` in your personal override if desired.

Normal restarts, recreations, and rebuilds skip installation when the recorded version/module/tool selection and generated skills are present. Language/customization edits remain untouched. A changed module/tool selection or resolved version uses the official update flow, preserving `_bmad/custom` and prior language/name answers. Keep customizations in the official custom layer; installer-managed files can change during updates. The Feature records skill ownership/hashes in `_bmad/.devcontainer-feature.json`. Updates refuse to overwrite modified generated skills or unrelated skills with the same name. For an existing BMAD installation created outside this Feature, resolve reported generated-skill collisions explicitly before adopting it; nothing is silently replaced. Deselection removes only unmodified, previously Feature-owned skills.

The v6.12.4 installer can write `--set ...=false` as a string. This Feature does not pass boolean `--set` overrides or patch generated configuration values. Official defaults are generated by the installer, and user customization files are not rewritten. Existing settings, including values from an earlier setup, are preserved rather than reset to defaults.

Generated Skills need not be committed: a new checkout can regenerate them from the Feature. This Feature does not edit the project's root `.gitignore`, Git index, or CI. Choose your own ignore/commit policy; retain the workspace files to retain personal data. To share selected customization files when Skills are ignored, allow `_bmad/custom` explicitly in your own Git policy.

## Verification

After setup, launch the selected AI tool from the project and invoke `bmad-help`, as the v6 installer recommends. For a non-AI configuration check:

```bash
uv run _bmad/scripts/resolve_config.py --project-root "$PWD"
```

Repository tests: `devcontainer features test -f bmad --skip-autogenerated .`. They exercise the real installer for BMM / BMM+TEA, all three tool selections, all four language combinations, resolved boolean types, unrelated skill preservation, repeat runs, image-file replacement, customization preservation during official updates, and ownership. `with-node` also asserts the compatible image Node was reused. Image-file replacement is a rebuild simulation, not an actual Docker volume lifecycle test.

For Docker-free verification after installing the Feature, run `python3 test/bmad/verify.py` with the Feature's bin directory on PATH. Live AI invocation, Zed GUI behavior, actual new/reused Docker volumes, and container deletion/rebuild cycles require an environment with those services and credentials.

## Official references

- [BMAD install documentation (contains v7 preview instructions)](https://docs.bmad-method.org/start/install-bmad/)
- [Example installer source (v6.12.4)](https://github.com/bmad-code-org/BMAD-METHOD/tree/v6.12.4/tools/installer)
- [TEA v1.27.2](https://github.com/bmad-code-org/bmad-method-test-architecture-enterprise/tree/v1.27.2)
- [Dev Container Feature specification](https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainer-features.md)
- [Zed container/lifecycle implementation](https://github.com/zed-industries/zed/blob/main/crates/dev_container/src/devcontainer_manifest.rs)
- [Zed Feature ordering issue](https://github.com/zed-industries/zed/issues/61691)
