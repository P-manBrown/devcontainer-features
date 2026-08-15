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
