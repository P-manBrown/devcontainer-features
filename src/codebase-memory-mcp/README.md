
# Codebase Memory MCP (codebase-memory-mcp)

Install the codebase-memory-mcp binary and configure it for detected coding agents.

## Example Usage

```json
"features": {
    "ghcr.io/P-manBrown/devcontainer-features/codebase-memory-mcp:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Enter a codebase-memory-mcp version (e.g. 'v0.9.0'), or use 'latest'. | string | latest |
| autoIndex | Enable the binary's own auto-indexing of new projects on first MCP session connection (codebase-memory-mcp config set auto_index). | boolean | false |
| ui | Install the UI variant, which adds an optional 3D graph-visualization web UI. | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/P-manBrown/devcontainer-features/blob/main/src/codebase-memory-mcp/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
