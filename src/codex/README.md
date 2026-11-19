
# Codex (codex)

Install the official Codex CLI. Codex's own sandbox is turned off by default; the container is the sandbox.

## Example Usage

```json
"features": {
    "ghcr.io/P-manBrown/devcontainer-features/codex:3": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Enter a Codex version, or use 'latest'. | string | latest |

## Customizations

### VS Code Extensions

- `openai.chatgpt`

## Sandbox

Codex's own Linux sandbox (bubblewrap) needs to create a user namespace, which a container only allows with the `SYS_ADMIN` capability and with the seccomp and AppArmor profiles turned off. Those settings weaken the container's security boundary for every process in it, so this Feature does not add them. Instead it treats the container itself as the sandbox and writes the following to `/etc/codex/config.toml`:

```toml
sandbox_mode = "danger-full-access"
```

This is Codex's lowest-precedence config layer, so a `sandbox_mode` you set in `~/.codex/config.toml`, in a project's `.codex/config.toml`, or with `-c` on the command line still wins. Without the settings above, any sandboxed mode (such as `read-only` or `workspace-write`) fails with `bwrap: No permissions to create a new namespace`. If `/etc/codex/config.toml` already exists when the Feature is installed, it is left unchanged.

When upgrading from an earlier version of this Feature, check `~/.codex/config.toml` (kept in the `codex-config` volume) and any project `.codex/config.toml` for a `sandbox_mode` other than `danger-full-access`, and for scripts that pass `--full-auto` or `-s`/`--sandbox`: these still ask for the sandbox and now fail with the error above.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/P-manBrown/devcontainer-features/blob/main/src/codex/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
