## Sandbox permissions

Codex's bubblewrap-based Linux sandbox needs to create a user namespace. This Feature therefore sets `securityOpt` to `seccomp=unconfined` and `apparmor=unconfined`, and adds the `SYS_ADMIN` capability, so bubblewrap can create that namespace inside the container. Both `seccomp` and `AppArmor` need to be relaxed on real Linux Docker hosts (e.g. GitHub Actions runners) — `seccomp=unconfined` alone is not enough there, even though it may appear sufficient on Docker Desktop (macOS/Windows), whose Linux VM does not enforce AppArmor.

These settings weaken the container's security boundary: disabling the seccomp and AppArmor profiles applies to every process in the container, and `SYS_ADMIN` is a powerful capability. Review this trade-off before using the Feature, especially with untrusted code.

For reference, see OpenAI's official [`.devcontainer/devcontainer.secure.json`](https://github.com/openai/codex/tree/main/.devcontainer), which uses the same `seccomp=unconfined` + `apparmor=unconfined` + `SYS_ADMIN` combination (plus additional capabilities for its firewall/debugging setup, which this Feature does not need).
