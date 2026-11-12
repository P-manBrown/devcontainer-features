#!/usr/bin/env python3
"""Isolated entrypoint contract tests; no npm, authentication or Docker required."""
import os
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


class EntrypointTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.cache = self.root / 'cache'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.bin / 'node').symlink_to(shutil.which('node'))
        self.log = self.root / 'calls'
        source = (Path(__file__).resolve().parents[2] / 'src/claude-mem/install.sh').read_text()
        self.source = source
        script = source.split("cat <<-'EOF' > /usr/local/share/claude-mem-init.sh\n", 1)[1].split('\nEOF', 1)[0]
        script = '\n'.join(line.removeprefix('\t') for line in script.splitlines())
        script = script.replace('/usr/local/share/claude-mem.env', str(self.root / 'env'))
        script = script.replace('/usr/local/share/claude-mem-cache', str(self.cache))
        # Make system uv installation explicit without depending on host packages.
        script = script.replace('/usr/local/bin:', str(self.bin) + ':')
        self.script = self.root / 'init.sh'
        self.script.write_text(script)
        for name in ('uv', 'uvx', 'claude', 'codex'):
            self.tool(name, 'exit 0')
        self.tool('claude-mem', '''echo "$*" >> "$CALLS"
node -e 'require("child_process").execFileSync("uvx", ["--version"])' || exit 1
ide="${@: -1}"
[[ "$ide" != "${FAIL_IDE:-}" ]] || exit 7
node - "$3" <<'JS'
const fs = require('fs');
const file = process.env.HOME + '/.claude-mem/settings.json';
const settings = JSON.parse(fs.readFileSync(file, 'utf8'));
settings.CLAUDE_MEM_PROVIDER = process.argv[2];
fs.writeFileSync(file, JSON.stringify(settings));
JS
mkdir -p "$HOME/.config-test"
printf 'registered\\n' > "$HOME/.config-test/$ide"
''')
        self.env = dict(os.environ, PATH=f'{self.bin}:/usr/bin:/bin', CALLS=str(self.log))

    def tool(self, name, body):
        p = self.bin / name
        p.write_text('#!/bin/bash\nset -eu\n' + body + '\n')
        p.chmod(0o755)

    def run_init(self, ide='claude-code', provider='claude', success=True):
        values = dict(USER_NAME=subprocess.check_output(['id', '-un'], text=True).strip(),
                      USER_HOME=str(self.home), IDE=ide, PROVIDER=provider)
        (self.root / 'env').write_text(''.join(f'{k}={shlex.quote(v)}\n' for k, v in values.items()))
        result = subprocess.run(['bash', str(self.script)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_each_ide_and_both(self):
        for ide, expected in [('claude-code', ['claude-code']), ('codex-cli', ['codex-cli']),
                              ('claude-code,codex-cli', ['claude-code', 'codex-cli']),
                              (' codex-cli , claude-code,codex-cli ', ['codex-cli', 'claude-code'])]:
            with self.subTest(ide=ide):
                self.log.unlink(missing_ok=True)
                self.run_init(ide)
                self.assertEqual(self.log.read_text().splitlines(),
                                 [f'install --provider claude --ide {item}' for item in expected])

    def test_restart_and_recreated_home_with_existing_volumes(self):
        self.run_init('claude-code,codex-cli')
        (self.cache / 'memory').write_text('preserved')
        (self.home / '.config-test/unrelated').write_text('preserved')
        self.run_init('claude-code,codex-cli')
        self.assertEqual((self.cache / 'memory').read_text(), 'preserved')
        self.assertEqual((self.home / '.config-test/unrelated').read_text(), 'preserved')
        # Fresh home with persisted memory and IDE configuration volumes.
        old_home = self.home
        self.home = self.root / 'recreated-home'
        self.home.mkdir()
        (self.home / '.config-test').symlink_to(old_home / '.config-test')
        self.run_init('claude-code,codex-cli')
        self.assertEqual((self.home / '.claude-mem/memory').read_text(), 'preserved')
        for ide in ('claude-code', 'codex-cli'):
            self.assertTrue((self.home / '.config-test' / ide).is_file())

    def test_missing_claude_also_fails_for_codex(self):
        (self.bin / 'claude').unlink()
        self.run_init('codex-cli', success=False)
        self.assertFalse(self.log.exists())

    def test_missing_codex_checked_before_registering_either(self):
        (self.bin / 'codex').unlink()
        self.run_init('claude-code,codex-cli', success=False)
        self.assertFalse(self.log.exists())

    def test_host_codex_does_not_require_claude(self):
        (self.bin / 'claude').unlink()
        self.run_init('codex-cli', provider='host')

    def settings(self):
        return json.loads((self.cache / 'settings.json').read_text())

    def test_codex_provider_without_claude(self):
        (self.bin / 'claude').unlink()
        self.run_init('codex-cli', provider='codex')
        self.assertEqual(self.settings()['CLAUDE_MEM_PROVIDER'], 'codex')
        self.assertEqual(self.log.read_text().strip(), 'install --provider codex --ide codex-cli')

    def test_codex_provider_requires_codex_even_for_claude_ide(self):
        (self.bin / 'codex').unlink()
        self.run_init(provider='codex', success=False)
        self.assertFalse(self.log.exists())

    def test_by_source_preserved_across_restart_and_mode_change(self):
        self.cache.mkdir()
        (self.cache / 'settings.json').write_text(json.dumps({'unrelated': {'keep': True}}))
        for _ in range(2):
            self.run_init('claude-code,codex-cli', provider='by-source')
            settings = self.settings()
            self.assertEqual(settings['unrelated'], {'keep': True})
            self.assertEqual(settings['CLAUDE_MEM_PROVIDER'], 'claude')
            self.assertEqual(json.loads(settings['CLAUDE_MEM_PROVIDER_BY_SOURCE']),
                             {'claude': 'claude', 'codex': 'codex'})
        self.run_init('codex-cli', provider='codex')
        self.assertEqual(self.settings()['CLAUDE_MEM_PROVIDER_BY_SOURCE'], '')
        self.assertEqual(self.settings()['unrelated'], {'keep': True})

    def test_by_source_requires_both_provider_clis(self):
        for missing in ('claude', 'codex'):
            with self.subTest(missing=missing):
                tool = self.bin / missing
                tool.unlink()
                self.run_init('codex-cli' if missing == 'claude' else 'claude-code',
                              provider='by-source', success=False)
                self.assertFalse(self.log.exists())
                self.tool(missing, 'exit 0')

    def test_corrupt_settings_are_not_overwritten(self):
        self.cache.mkdir()
        file = self.cache / 'settings.json'
        for text in ('{broken', '[]', 'null'):
            file.write_text(text)
            self.run_init(provider='by-source', success=False)
            self.assertEqual(file.read_text(), text)
            self.assertFalse(self.log.exists())

    def test_invalid_ide_lists(self):
        for ide in ('', 'both', ',claude-code', 'claude-code,',
                    'claude-code,,codex-cli', 'claude-code,unknown', 'claude-code\ncodex-cli',
                    'clau de-code'):
            with self.subTest(ide=ide):
                self.run_init(ide, success=False)
                self.assertFalse(self.log.exists())

    def test_installed_worker_capability_guard(self):
        bundle = self.root / 'claude-mem/plugin/scripts/worker-service.cjs'
        bundle.parent.mkdir(parents=True)
        self.tool('npm', 'echo "$PACKAGE_ROOT"')
        guard = self.source.split('echo "Installed: $(claude-mem --version)"', 1)[1].split('# Pre-create', 1)[0]
        for provider, content, success in [
            ('claude', '', True), ('host', '', True),
            ('codex', '', False), ('by-source', 'CLAUDE_MEM_CODEX_MODEL', False),
            ('codex', 'CLAUDE_MEM_CODEX_MODEL', True),
            ('by-source', 'CLAUDE_MEM_PROVIDER_BY_SOURCE', True),
        ]:
            with self.subTest(provider=provider, content=content):
                bundle.write_text(content)
                result = subprocess.run(['bash', '-c', 'set -eu; err() { echo "$*" >&2; };' + guard],
                                        env=dict(self.env, PROVIDER=provider, PACKAGE_ROOT=str(self.root)),
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, success, result.stderr)

    def test_uvx_failure(self):
        self.tool('uvx', 'exit 1')
        self.run_init(success=False)
        self.assertFalse(self.log.exists())

    def test_partial_failure_is_not_success_and_other_ide_is_attempted(self):
        for ide in ('claude-code', 'codex-cli'):
            self.log.unlink(missing_ok=True)
            self.env['FAIL_IDE'] = ide
            self.run_init('claude-code,codex-cli', success=False)
            self.assertEqual(len(self.log.read_text().splitlines()), 2)


if __name__ == '__main__':
    unittest.main()
