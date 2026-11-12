## What this Feature installs

This Feature installs the `claude-mem` npm CLI and uv (including uvx) using the official uv standalone installer. uv and uvx are installed system-wide in `/usr/local/bin`, outside user configuration volumes. The installer selects the Linux architecture and fails if no compatible binary is available; both executables are checked during build and again as the target user at startup. At container startup, its entrypoint saves the selected provider and routing, then runs `claude-mem install --no-auto-start --ide <ide>` non-interactively for each selected integration. Claude and host providers also pass `--provider`; Codex uses the saved-provider path described below. After all registrations succeed, the Feature explicitly runs `claude-mem start` once. `ide=claude-code,codex-cli` runs registration once for Claude Code and once for Codex. The default remains `ide=claude-code`. Registration uses the target user and an explicit PATH containing `/usr/local/bin`, inherited by Workers started during installation. No additional `npx` or postCreateCommand registration is needed. Session memory is stored in `~/.claude-mem`, which is linked to a named volume so it persists across container rebuilds.

## Using the Claude provider

The `claude` provider requires the Claude Code CLI regardless of the selected `ide`. Claude Mem starts the `claude` binary as a subprocess and borrows its OAuth credentials. When using `ide=codex-cli` with `provider=claude`, add the `claude-code` Feature as well as the `codex` Feature.

`provider=host` expects your own compatible server on the container's loopback interface (`127.0.0.1`); it does not mean the Docker host. Installing Codex CLI does not provide this server.

## Codex and source-based providers

`provider=codex` uses Codex to process observations and summaries, regardless of which IDE produced the session. Install the Codex Feature and run `codex login` as the remote user. Claude Code CLI is required only when registering its IDE integration or using the Claude provider. Codex provider authentication requires a file-backed ChatGPT login; an API-key login is not accepted by the upstream Codex subscription provider. The Feature saves `CLAUDE_MEM_PROVIDER=codex` and omits `--provider` during registration so the upstream non-interactive installer retains the saved provider. Passing `--provider codex` explicitly in claude-mem 15.17.1 starts cmem.ai browser pairing even with `CI=true`; container startup must not use that path.

`provider=by-source` is a Feature preset, not a provider name passed to the upstream CLI. It saves the following routing in `~/.claude-mem/settings.json` and installs using `--provider claude` as the default:

```json
{
  "CLAUDE_MEM_PROVIDER_BY_SOURCE": "{\"claude\":\"claude\",\"codex\":\"codex\"}"
}
```

Claude Code sessions use Claude and Codex sessions use Codex. Other sources fall back to the default Claude provider. Both CLIs and their authentication are needed in this mode, even when registering just one IDE. See the [upstream provider configuration](https://github.com/thedotmack/claude-mem/blob/main/docs/public/configuration.mdx).

These modes require an upstream version with the corresponding Codex/source-routing support (confirmed in claude-mem 15.17.1). The build checks for that capability in the installed Worker bundle and rejects versions lacking it. The Feature does not automate interactive authentication or establish that credentials are usable.

The Feature reapplies its provider and routing keys on every startup while preserving other settings, including supported legacy settings nested under `env`. Selecting `claude`, `codex` or `host` clears source overrides, including mappings previously saved manually, so the selected single provider applies to all sessions. Invalid JSON or a non-object settings file causes initialization to fail without overwriting that file.

## Registering both IDEs

```jsonc
"features": {
  "ghcr.io/P-manBrown/devcontainer-features/claude-code:1": {},
  "ghcr.io/P-manBrown/devcontainer-features/codex:3": {},
  "ghcr.io/P-manBrown/devcontainer-features/claude-mem:1": {
    "ide": "claude-code,codex-cli",
    "provider": "by-source"
  }
}
```

The `ide` option is a comma-separated string, converted to an array internally. Whitespace around entries is trimmed and duplicates are registered once; empty or unknown entries fail. `both` is not accepted. Use `ide=codex-cli` for Codex alone, or omit `ide` for Claude Code alone. With `provider=claude`, all IDE choices require Claude Code CLI and valid Claude credentials. The Feature checks CLI availability, but does not authenticate or prove that credentials are valid. `provider=host` still requires your own compatible server.

## Startup, persistence and failures

Fresh non-interactive upstream installs skip Worker autostart, so the Feature starts the Worker explicitly after registering every selected integration. Every startup reapplies the requested registrations through the upstream installer, including when existing IDE configuration volumes are reused after rebuilding the image. The Feature does not replace IDE configuration files itself. uv/uvx are restored by the image build, independently of persisted configuration. Existing Workers must be restarted after rebuilding to inherit the new environment.

The entrypoint checks uv, uvx and the required IDE commands before updating provider routing or registering integrations. Missing prerequisites or a non-zero installer result make initialization exit non-zero. With `ide=claude-code,codex-cli`, both registrations are attempted, and either failure makes the overall result a failure. Already completed registrations are retained; fix the reported problem and rerun `/usr/local/share/claude-mem-init.sh` as the remote user (or restart the container). A failed initialization may prevent container startup, depending on the Dev Container implementation.

## Verification and limits

The scenario tests cover the default, Claude Code, Codex and both registrations, login-shell, child-process and running-Worker PATH uvx execution, plugin bundle references, and repeated initialization with existing data. Run them with `devcontainer features test -f claude-mem --skip-autogenerated .` on Linux amd64 and arm64. The isolated entrypoint tests run with `python3 test/claude-mem/entrypoint-test.py` and cover list parsing and validation, missing prerequisites, partial failures, Codex provider selection, source routing, mode changes, corrupt settings, and a recreated home with retained data/configuration.

For a real restart/rebuild check, retain the memory and IDE configuration volumes, restart and then rebuild the container, and check both registrations and a previously saved memory. Confirm uvx is present in the actual Worker's PATH (for example, `/proc/<worker-pid>/environ`). After authenticating Claude Code, inspect the Worker's health API and exercise memory ingestion, Chroma synchronization and semantic retrieval. CLI versions and registration success alone do not demonstrate vector search readiness: package downloads, network access, model availability and authentication can still fail. Missing uvx degrades vector search to FTS5; it does not by itself imply that recording or keyword search has stopped.

Authentication, semantic search/Chroma synchronization, actual container restart/recreation, and execution on architectures other than the test host require separate environment validation. The isolated tests simulate persistence and installer results; they do not validate upstream configuration merging or a running Worker.

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
