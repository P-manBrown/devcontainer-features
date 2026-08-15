
# Codebase Memory MCP (codebase-memory-mcp)

Install the codebase-memory-mcp binary and configure it for detected coding agents.

## Example Usage

```json
"features": {
    "ghcr.io/P-manBrown/devcontainer-features/codebase-memory-mcp:2": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Enter a codebase-memory-mcp version (e.g. 'v0.9.0'), or use 'latest'. | string | latest |
| autoIndex | Enable the binary's own auto-indexing of new projects on first MCP session connection (codebase-memory-mcp config set auto_index). | boolean | false |
| portRelay | Install socat to relay the UI's port 9749 through appPort-only publishing, for editors without forwardPorts support (e.g. Zed). Not needed if your editor supports forwardPorts. | boolean | false |

## Using the UI

Reaching the UI from your host browser is something you need to configure in your own `.devcontainer/devcontainer.json`, and it determines which command you run inside the container.

- If your editor supports `forwardPorts`, forward port 9749:

  ```jsonc
  // .devcontainer/devcontainer.json
  "forwardPorts": [9749]
  ```

  Then run:

  ```bash
  codebase-memory-mcp --ui=true --port=9749
  ```

- If your editor only supports `appPort`, publish port 9749 and set the
  `portRelay` option to install `socat`:

  ```jsonc
  // .devcontainer/devcontainer.json
  "appPort": ["127.0.0.1:9749:9749"],
  "features": {
    "ghcr.io/P-manBrown/devcontainer-features/codebase-memory-mcp:2": {
      "portRelay": true
    }
  }
  ```

  Run:

  ```bash
  codebase-memory-mcp --ui=true --port=9749
  ```

  Then, once it's up, relay it:

  ```bash
  socat TCP-LISTEN:9749,bind=$(hostname -I | awk '{print $1}'),fork,reuseaddr TCP:127.0.0.1:9749
  ```


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/P-manBrown/devcontainer-features/blob/main/src/codebase-memory-mcp/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
