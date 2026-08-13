## Authentication

Initial git-spice authentication cannot be performed non-interactively. After the container starts, authenticate manually by following the authentication procedure in the official git-spice documentation.

The resulting `~/.config/git-spice/secrets.json` file is stored in a named Docker volume, so authentication persists when the container is recreated.
