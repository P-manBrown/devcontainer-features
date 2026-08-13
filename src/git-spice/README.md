
# git-spice (git-spice)

Install git-spice, a tool for stacking Git branches. Requires Git 2.38 or later.

## Example Usage

```json
"features": {
    "ghcr.io/P-manBrown/devcontainer-features/git-spice:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Enter a git-spice version. | string | latest |
| installGsAlias | Create a 'gs' symlink for git-spice, as recommended by the official docs? | boolean | true |

## Authentication

Initial git-spice authentication cannot be performed non-interactively. After the container starts, authenticate manually by following the authentication procedure in the official git-spice documentation.

The resulting `~/.config/git-spice/secrets.json` file is stored in a named Docker volume, so authentication persists when the container is recreated.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/P-manBrown/devcontainer-features/blob/main/src/git-spice/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
