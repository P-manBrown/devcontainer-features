
# rtk (rtk)

Install rtk, a CLI proxy that compresses bash command output to reduce LLM token consumption, with optional automatic hook setup for Claude Code and Codex.

## Example Usage

```json
"features": {
    "ghcr.io/P-manBrown/devcontainer-features/rtk:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Enter an rtk version (e.g. 'v0.44.1'), or use 'latest'. | string | latest |
| claudeCodeHook | On container start, run 'rtk init -g --auto-patch' to automatically set up a Claude Code PreToolUse hook and RTK.md. Requires the claude-code feature. | boolean | false |
| codexHook | On container start, run 'rtk init -g --codex' to automatically set up Codex AGENTS.md/RTK.md integration. Requires the codex feature. | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/P-manBrown/devcontainer-features/blob/main/src/rtk/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
