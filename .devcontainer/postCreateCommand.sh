#!/usr/bin/env bash
set -eu

echo 'Setting up GitHub CLI...'
# ~/.config/gh is a named volume; Docker creates its mount point owned by root.
sudo chown -R "$(whoami)" "${HOME}/.config/gh"
# Let git use the gh login for GitHub (what gh auth setup-git writes, without
# requiring a login first), so a new clone works without extra setup.
for host in github.com gist.github.com; do
	git config --global "credential.https://${host}.helper" ''
	git config --global --add "credential.https://${host}.helper" '!gh auth git-credential'
done
if ! gh auth status > /dev/null 2>&1; then
	echo 'GitHub CLI is not logged in. Log in with "gh auth login --with-token < <token file>".'
fi

echo 'Setting up Dev Container CLI...'
npm install -g @devcontainers/cli
