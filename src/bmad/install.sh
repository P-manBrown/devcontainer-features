#!/usr/bin/env bash
set -euo pipefail

[[ $(id -u) == 0 ]] || { echo 'ERROR: Run as root.' >&2; exit 1; }
USER_NAME="${_REMOTE_USER}"
USER_HOME="${_REMOTE_USER_HOME}"
ROOT=/usr/local/share/bmad-feature
VERSION="${VERSION:-latest}"
MODULES="${MODULES:-bmm}"
TOOLS="${TOOLS:-codex}"
COMMUNICATIONLANGUAGE="${COMMUNICATIONLANGUAGE:-Japanese}"
DOCUMENTOUTPUTLANGUAGE="${DOCUMENTOUTPUTLANGUAGE:-Japanese}"
if [[ "$VERSION" != latest && ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo 'ERROR: version must be latest or an exact stable BMAD version (e.g. 6.12.4).' >&2
	exit 1
fi
case "$MODULES" in bmm|bmm,tea) ;; *) echo 'Invalid modules' >&2; exit 1 ;; esac
case "$TOOLS" in claude-code|codex|claude-code,codex) ;; *) echo 'Invalid tools' >&2; exit 1 ;; esac
for language in "$COMMUNICATIONLANGUAGE" "$DOCUMENTOUTPUTLANGUAGE"; do
	case "$language" in English|Japanese) ;; *) echo 'Invalid language' >&2; exit 1 ;; esac
done
mkdir -p "$ROOT/bin"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Like claude-mem/bruno-cli, own our dependencies rather than relying on
# Feature ordering. Keep fallbacks private so system tools are never replaced.
apt_ready=false
apt_install() {
	if [[ "$apt_ready" == false ]]; then apt-get update; apt_ready=true; fi
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}
command -v curl >/dev/null && command -v xz >/dev/null || apt_install curl ca-certificates xz-utils

# A dependency is reusable only if the remote user can execute it with the
# same PATH used by this Feature, and it meets the version floor.
feature_path="$ROOT/bin:$PATH"
user_run() {
	if [[ "$USER_NAME" == root ]]; then
		HOME="$USER_HOME" PATH="$feature_path" "$@"
	else
		su -s /bin/sh "$USER_NAME" -c "$(printf 'env HOME=%q PATH=%q ' "$USER_HOME" "$feature_path")$(printf '%q ' "$@")"
	fi
}
version_ok() {
	local output version
	output=$(user_run "$1" --version 2>/dev/null) || return 1
	version=$(printf '%s' "$output" | sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -1)
	[[ -n "$version" && "$(printf '%s\n%s\n' "$2" "$version" | sort -V | head -1)" == "$2" ]]
}
case "$(uname -m)" in
	x86_64) node_arch=x64; uv_arch=x86_64 ;;
	aarch64|arm64) node_arch=arm64; uv_arch=aarch64 ;;
	*) echo 'ERROR: Only Linux x86_64 and aarch64 are supported.' >&2; exit 1 ;;
esac
if ! version_ok node 20.12.0 || ! user_run node -e 'const m=Number(process.versions.node.split(".")[0]); process.exit(m === 20 || m >= 22 ? 0 : 1)' \
	|| ! user_run npm --version >/dev/null 2>&1; then
	asset="node-v22.16.0-linux-${node_arch}.tar.xz"
	curl -fsSL "https://nodejs.org/dist/v22.16.0/$asset" -o "$work/$asset"
	curl -fsSL https://nodejs.org/dist/v22.16.0/SHASUMS256.txt -o "$work/sums"
	(cd "$work" && grep " $asset\$" sums | sha256sum -c -)
	mkdir -p "$ROOT/node"
	tar -xJf "$work/$asset" -C "$ROOT/node" --strip-components=1 --no-same-owner
	for tool in node npm npx; do ln -sfn "$ROOT/node/bin/$tool" "$ROOT/bin/$tool"; done
fi
if ! version_ok git 2.25.0; then
	apt_install git
	version_ok git 2.25.0 || { echo 'ERROR: Git >=2.25 must be available to the remote user.' >&2; exit 1; }
fi
if ! version_ok uv 0.9.5; then
	asset="uv-${uv_arch}-unknown-linux-gnu.tar.gz"
	curl -fsSL "https://github.com/astral-sh/uv/releases/download/0.9.5/$asset" -o "$work/$asset"
	curl -fsSL "https://github.com/astral-sh/uv/releases/download/0.9.5/$asset.sha256" -o "$work/uv.sha256"
	printf '%s  %s\n' "$(awk '{print $1}' "$work/uv.sha256")" "$asset" > "$work/checksums"
	(cd "$work" && sha256sum -c checksums)
	tar -xzf "$work/$asset" -C "$work" --no-same-owner
	install -m 755 "$work/uv-${uv_arch}-unknown-linux-gnu/uv" "$ROOT/bin/uv"
fi
export PATH="$feature_path"
if ! version_ok python3 3.11.0; then
	UV_PYTHON_DOWNLOADS=automatic UV_PYTHON_INSTALL_DIR="$ROOT/python" uv python install 3.11.14 --no-bin
	python_path=$(UV_PYTHON_INSTALL_DIR="$ROOT/python" uv python find --managed-python 3.11.14)
	ln -sfn "$python_path" "$ROOT/bin/python3"
	ln -sfn "$python_path" "$ROOT/bin/python3.11"
fi
for spec in 'node 20.12.0' 'git 2.25.0' 'uv 0.9.5' 'python3 3.11.0'; do
	read -r tool minimum <<< "$spec"
	version_ok "$tool" "$minimum" || { echo "ERROR: $tool unavailable to $USER_NAME" >&2; exit 1; }
done

# Resolve latest once per image build, never during container startup.
# Explicit versions resolve the same official npm package.
resolved_version=$(npm view "bmad-method@$VERSION" version --json | node -e '
let data="";process.stdin.on("data",chunk=>data+=chunk);process.stdin.on("end",()=>{
 const version=JSON.parse(data);
 if(typeof version!=="string" || !/^[0-9]+\.[0-9]+\.[0-9]+$/.test(version)) process.exit(1);
 console.log(version);
});')
# Install the selected release, not a repository lock for one historical
# version. npm records the resolved dependency tree in the image itself.
mkdir -p "$ROOT/runtime"
npm install --prefix "$ROOT/runtime" --save-exact "bmad-method@$resolved_version" \
	--engine-strict --ignore-scripts --no-audit --no-fund
cp setup.py init.sh "$ROOT/"
chmod 755 "$ROOT/init.sh"
cat > /usr/local/bin/bmad-setup <<EOF2
#!/usr/bin/env bash
export PATH=$(printf '%q' "$feature_path")
export UV_PYTHON_DOWNLOADS=never
exec python3 '$ROOT/setup.py' "\$@"
EOF2
chmod 755 /usr/local/bin/bmad-setup
# bmad invokes the image-selected CLI, even when another npm prefix is configured.
cat > "$ROOT/bin/bmad" <<EOF2
#!/usr/bin/env bash
export PATH=$(printf '%q' "$feature_path")
exec '$ROOT/runtime/node_modules/.bin/bmad' "\$@"
EOF2
chmod 755 "$ROOT/bin/bmad"
# Check the interface we actually use, rather than requiring a listed version.
install_help=$(bmad install --help)
for flag in --directory --modules --tools --action --set --pin --no-shims --yes \
	--user-name --communication-language --document-output-language; do
	if ! grep -qF -- "$flag" <<< "$install_help"; then
		echo "ERROR: BMAD $resolved_version installer lacks required option $flag." >&2
		exit 1
	fi
done
# Record the official generated skill names for collision checks before any
# project files are touched. No user workspace is needed during the build.
HOME="$work/home" UV_PYTHON_DOWNLOADS=never bmad install --directory "$work/template" \
	--modules "$MODULES" --tools "$TOOLS" --user-name BMad --yes --no-shims
# Let the release's bundled official registry select module versions, then
# freeze the versions actually installed for this image's runtime setup.
node - "$ROOT" "$work/template" "$USER_NAME" "$USER_HOME" "$MODULES" "$TOOLS" "$COMMUNICATIONLANGUAGE" "$DOCUMENTOUTPUTLANGUAGE" "$resolved_version" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const [root, project, user, home, modules, tools, communication, document, bmad] = process.argv.slice(2);
const yaml = require(path.join(root, 'runtime/node_modules/yaml'));
const manifest = yaml.parse(fs.readFileSync(path.join(project, '_bmad/_config/manifest.yaml'), 'utf8'));
for (const file of ['config.toml', 'scripts/resolve_config.py']) {
 if (!fs.existsSync(path.join(project, '_bmad', file))) {
  throw new Error(`BMAD ${bmad} installer did not generate required project file ${file}`);
 }
}
for (const name of ['core', ...modules.split(',')]) {
 const installed = manifest.modules?.find(module => module.name === name);
 if (!installed || !/^v?[0-9]+\.[0-9]+\.[0-9]+$/.test(installed.version) ||
     (name !== 'tea' && installed.version.replace(/^v/, '') !== bmad)) {
  throw new Error(`Official installer did not report the expected stable ${name} version`);
 }
}
const tea = manifest.modules.find(module => module.name === 'tea')?.version || null;
fs.writeFileSync(path.join(root, 'options.json'), JSON.stringify({user, home, modules, tools, communication, document, bmad, tea}));
const skills = [];
for (const folder of ['.claude/skills', '.agents/skills']) {
 const target = path.join(project, folder);
 if (!fs.existsSync(target)) continue;
 for (const name of fs.readdirSync(target)) {
  if (fs.existsSync(path.join(target, name, 'SKILL.md'))) skills.push(`${folder}/${name}/SKILL.md`);
 }
}
if (skills.length === 0) throw new Error('Official installer did not generate any skills');
fs.writeFileSync(path.join(root, 'skills.json'), JSON.stringify(skills));
JS
# The source cache is disposable program data; it stays in the image, never
# in a persistent volume. Runtime installer caches are temporary copies.
if [[ -d "$work/home/.bmad" ]]; then cp -a "$work/home/.bmad" "$ROOT/installer-cache"; fi
printf 'BMAD dependencies verified for %s.\n' "$USER_NAME"
