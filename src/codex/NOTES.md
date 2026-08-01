## Sandbox permissions

Codex's bubblewrap-based Linux sandbox needs to create a user namespace. This Feature therefore sets `securityOpt` to `seccomp=unconfined` and `apparmor=unconfined`, and adds the `SYS_ADMIN` capability, so bubblewrap can create that namespace inside the container.

These settings weaken the container's security boundary: disabling the seccomp and AppArmor profiles applies to every process in the container, and `SYS_ADMIN` is a powerful capability. Review this trade-off before using the Feature, especially with untrusted code.

For reference, see OpenAI's official [`.devcontainer/devcontainer.secure.json`](https://github.com/openai/codex/tree/main/.devcontainer), which uses the same `seccomp=unconfined` + `apparmor=unconfined` + `SYS_ADMIN` combination (plus additional capabilities for its debugging/firewall setup, which this Feature does not need).

## Known limitation: host-level `apparmor_restrict_unprivileged_userns`

Some Linux hosts (Ubuntu 24.04+ and derivatives) enforce a **host-wide** kernel sysctl, `kernel.apparmor_restrict_unprivileged_userns`, that blocks unprivileged (non-root) processes from creating user namespaces — independent of any per-container `securityOpt`/`capAdd` settings. If this sysctl is `1` on the Docker host, sandboxed exec still fails as a non-root container user even with everything this Feature sets, with errors like:

```
unshare: write failed /proc/self/uid_map: Operation not permitted
bwrap: setting up uid map: Permission denied
```

This is a **host kernel** setting, not a container setting — it cannot be worked around from inside the container, and this Feature cannot disable it. If you control the Docker host, disable it there:

```
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

On managed environments where you don't control the host (e.g. GitHub Codespaces), there is no workaround available to this Feature.
