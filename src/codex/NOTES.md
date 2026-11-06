## Sandbox

Codex's own Linux sandbox (bubblewrap) needs to create a user namespace, which a container only allows with the `SYS_ADMIN` capability and with the seccomp and AppArmor profiles turned off. Those settings weaken the container's security boundary for every process in it, so this Feature does not add them. Instead it treats the container itself as the sandbox and writes the following to `/etc/codex/config.toml`:

```toml
sandbox_mode = "danger-full-access"
```

This is Codex's lowest-precedence config layer, so a `sandbox_mode` you set in `~/.codex/config.toml`, in a project's `.codex/config.toml`, or with `-c` on the command line still wins. Without the settings above, any sandboxed mode (such as `read-only` or `workspace-write`) fails with `bwrap: No permissions to create a new namespace`. If `/etc/codex/config.toml` already exists when the Feature is installed, it is left unchanged.

When upgrading from an earlier version of this Feature, check `~/.codex/config.toml` (kept in the `codex-config` volume) and any project `.codex/config.toml` for a `sandbox_mode` other than `danger-full-access`, and for scripts that pass `--full-auto` or `-s`/`--sandbox`: these still ask for the sandbox and now fail with the error above.

## Persistence

Codex keeps its state in `~/.codex`. This Feature mounts the `codex-config-${devcontainerId}` volume at `/usr/local/share/codex-config`, and every time the container starts it makes `~/.codex` a symlink to `/usr/local/share/codex-config/codex`. Everything Codex writes there, including the login in `auth.json`, `config.toml`, the history and the sessions, is stored in the volume and is still there after the container is rebuilt.

The Codex binaries are not in the volume. The Feature installs them in `~/.local/share/codex` inside the image, and `~/.local/bin/codex` points there, so rebuilding with a newer Feature or `version` updates Codex. If Codex updates itself inside the container, the new version is installed in the volume (under `~/.codex/packages`) and is used until the next rebuild, which points `~/.local/bin/codex` back to the copy in the image. The files left in the volume only take up disk space.

If `~/.codex` is a real directory when the container starts (for example because another Feature or a Dockerfile wrote files there while the image was built), its contents are merged into the volume before the symlink is created:

- `auth.json`, `config.toml`, `history.jsonl`, `session_index.jsonl`, `sessions`, `archived_sessions` and `log` are copied only when the volume does not have them yet. The volume's copy wins, because it holds the account and settings you used last. When the image's `auth.json` is ignored this way, a warning is printed.
- Everything else (for example `AGENTS.md`, `agents/` or `skills/`) is copied over the volume, so files from the image replace older copies in the volume. Files that exist only in the volume are kept.

If `~/.codex` is a symlink to some other place, it is left unchanged and a warning is printed; the volume then does not keep what Codex writes there.

### Upgrading from 3.0.0

Version 3.0.0 of this Feature linked a few files in `~/.codex` into the volume one by one. Codex saves `auth.json` by replacing the file, which broke that link, so a login made under 3.0.0 may exist only in the container and not in the volume. Before you rebuild the container with this version, run this in the old container to copy that login into the volume:

```sh
[ -L ~/.codex/auth.json ] || cp ~/.codex/auth.json /usr/local/share/codex-config/auth.json
```

On the first start with this version, the files at the top of the volume are moved into `/usr/local/share/codex-config/codex`. If a file with the same name is already there, the file at the top is left in place and a warning names it.
