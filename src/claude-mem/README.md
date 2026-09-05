
# Claude Mem (claude-mem)

Install claude-mem and configure it to capture Claude Code/Codex session memory.

## Example Usage

```json
"features": {
    "ghcr.io/P-manBrown/devcontainer-features/claude-mem:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Enter a claude-mem npm version (e.g. '13.24.0'), or use 'latest'. | string | latest |
| ide | Which IDE integration to register claude-mem hooks for. | string | claude-code |
| provider | Which memory provider claude-mem uses to compress sessions. 'claude' reuses your logged-in Claude Code CLI's OAuth credentials (requires the claude-code feature/binary to be present, regardless of the 'ide' setting). 'host' expects an OpenAI-compatible server already listening on 127.0.0.1 (claude-mem does not start one itself) — Codex CLI does not expose such a server out of the box, so this option is only practical if you run your own bridge. | string | claude |

## What this Feature installs

This Feature installs the `claude-mem` npm CLI. At container startup, its entrypoint runs `claude-mem install --provider <provider> --ide <ide>` non-interactively to register the selected hooks and plugin. Session memory is stored in `~/.claude-mem`, which is linked to a named volume so it persists across container rebuilds.

## Using the Claude provider

The `claude` provider requires the Claude Code CLI regardless of the selected `ide`. Claude Mem starts the `claude` binary as a subprocess and borrows its OAuth credentials. When using `ide=codex-cli` with `provider=claude`, add the `claude-code` Feature as well as the `codex` Feature.

Codex CLI does not provide an OpenAI-compatible HTTP server. As a result, `provider=host` is not practical in a Codex environment unless you run your own compatible bridge on `127.0.0.1`. To use Claude Mem compression with Codex without managing a separate API key, use `provider=claude` and install the `claude-code` Feature.

## Known limitation with the Codex integration

If `ide=codex-cli` is selected but the `codex` command is not on `PATH` when the entrypoint runs, `claude-mem install` can report a partial installation and exit non-zero. This Feature reports that failure as a warning without preventing the container from starting. Install the `codex` Feature alongside this Feature to make the command available.

## Using the web UI

By default, `CLAUDE_MEM_WORKER_HOST` is `127.0.0.1`, so the web UI only listens on the container's loopback interface. To reach it from your host browser, add the following to your `.devcontainer/devcontainer.json`:

```jsonc
"containerEnv": {
  "CLAUDE_MEM_WORKER_HOST": "0.0.0.0"
},
"forwardPorts": [37700]
```

By default, the port is `37700 + (container UID % 100)`, which varies per user. To pin it to a fixed value (e.g. for `compose.yml` `ports`), set `CLAUDE_MEM_WORKER_PORT` explicitly:

```jsonc
"containerEnv": {
  "CLAUDE_MEM_WORKER_HOST": "0.0.0.0",
  "CLAUDE_MEM_WORKER_PORT": "37700"
},
"forwardPorts": [37700]
```

If you don't set `CLAUDE_MEM_WORKER_PORT`, check the calculated port inside the container with:

```bash
echo $((37700 + $(id -u) % 100))
```

Update `forwardPorts` (or `compose.yml` `ports`) to match whichever port you end up using. This Feature does not install a `socat` or port-relay service.

## OAuth credentials on headless Linux

Headless Linux environments may not provide an OS keychain such as libsecret. In that case, Claude Mem's `readClaudeOAuthToken()` falls back to the `CLAUDE_CODE_OAUTH_TOKEN` environment variable. Whether the normal Claude Code login flow provides credentials correctly in a particular Dev Container environment should be verified there.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/P-manBrown/devcontainer-features/blob/main/src/claude-mem/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
