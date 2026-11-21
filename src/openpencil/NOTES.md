## Which OpenPencil

This Feature installs [ZSeven-W/openpencil](https://github.com/ZSeven-W/openpencil): the `op` CLI and the windowless `openpencil-desktop` binary from its GitHub Releases. It is not openpencil.dev (Danila Poyarkov) or the Homebrew core `openpencil` cask, which are different projects with the same name.

## Requirements

- glibc 2.39 or later, for example Ubuntu 24.04 or Debian 13 base images.
- x86_64 or aarch64 Linux.

Debian 12-based images (for example `node:22-bookworm`, glibc 2.36) fail at build time with a message that names the glibc found.

## Version

The `version` option is pinned to `0.8.5` because upstream publishes only prereleases. `latest` is not accepted; set an exact version. Each downloaded archive is checked against the Release's `SHA256SUMS.txt` before it is unpacked.

## Headless use

```bash
op start --headless --file design.op
op status
op tools
op <tool> key=value
op stop
```

`OPENPENCIL_DESKTOP_BIN` is preset to `/usr/local/share/openpencil/openpencil-desktop`, so `op start --headless` finds the desktop binary without extra setup.

## Conflicts

The install fails if another `/usr/local/bin/op` (for example the 1Password CLI) is present. The existing file is left unchanged.

## Licenses

The font notices shipped with `openpencil-desktop` are kept in `/usr/local/share/openpencil/font-notices/`.
