## Sandbox permissions

Codex's bubblewrap-based Linux sandbox needs to create a user namespace. This Feature therefore sets `securityOpt` to `seccomp=unconfined` and adds the `SYS_ADMIN` capability so bubblewrap can create that namespace inside the container.

These settings weaken the container's security boundary: disabling the seccomp profile applies to every process in the container, and `SYS_ADMIN` is a powerful capability. Review this trade-off before using the Feature, especially with untrusted code.

Ubuntu 24.04-based images may also be restricted by AppArmor. If `bwrap: No permissions to create new namespace` still occurs after installing this Feature, AppArmor may be the cause. Add the following to the consuming `devcontainer.json` and rebuild the container:

```json
"securityOpt": ["apparmor=unconfined"]
```

(Docker-specific setups may instead use `"runArgs": ["--security-opt", "apparmor=unconfined"]`, which has the same effect but bypasses the cross-orchestrator `securityOpt` property.)

For reference, see OpenAI's official [`.devcontainer/devcontainer.secure.json`](https://github.com/openai/codex/tree/main/.devcontainer).
