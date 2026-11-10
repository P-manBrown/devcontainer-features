#!/usr/bin/env bash
set -euo pipefail
# Entrypoints have no specified workspace cwd. Never guess from /workspaces.
if [[ -z "${BMAD_WORKSPACE:-}" ]]; then
	echo 'BMAD: entrypoint skipped; set containerEnv.BMAD_WORKSPACE for editors without lifecycle support.' >&2
	exit 0
fi
/usr/local/bin/bmad-setup "$BMAD_WORKSPACE"
