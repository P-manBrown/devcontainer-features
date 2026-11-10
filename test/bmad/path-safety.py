#!/usr/bin/env python3
"""Workspace state must never grant ownership of arbitrary directories."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'src/bmad/setup.py'
if not SOURCE.exists():
    SOURCE = Path('/usr/local/share/bmad-feature/setup.py')


class PathSafety(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        fixture = self.base / 'feature'
        fixture.mkdir()
        shutil.copy(SOURCE, fixture / 'setup.py')
        options = dict(user='unused', home='unused', modules='bmm', tools='claude-code',
                       bmad='6.12.4', tea='v1.27.2', communication='English', document='English')
        (fixture / 'options.json').write_text(json.dumps(options))
        (fixture / 'skills.json').write_text('[]')
        spec = importlib.util.spec_from_file_location('bmad_setup', fixture / 'setup.py')
        self.setup = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.setup)
        self.project = self.base / 'project'
        (self.project / '_bmad').mkdir(parents=True)
        (self.project / '_bmad/config.toml').write_text('')
        self.outside = self.base / 'outside-project'
        self.outside.mkdir()
        (self.outside / 'SKILL.md').write_text('must survive\n')

    def state(self, name, directory):
        hashes = self.setup.skill_hashes(directory)
        (self.project / '_bmad/.devcontainer-feature.json').write_text(
            json.dumps(dict(skills={name: hashes}, configuration={
                k: self.setup.OPTIONS[k] for k in ('bmad', 'tea', 'modules', 'tools')})))

    def assert_rejected(self, name, directory):
        self.state(name, directory)
        with patch.object(self.setup, 'run') as installer:
            with self.assertRaisesRegex(RuntimeError, 'Unsafe BMAD skill path'):
                self.setup.setup(self.project)
            installer.assert_not_called()
        self.assertEqual((self.outside / 'SKILL.md').read_text(), 'must survive\n')
        self.assertTrue(directory.exists())

    def test_forged_state_paths(self):
        for name in ('../outside-project', str(self.outside),
                     '.claude/skills/../../..//outside-project',
                     '.claude/skills/../bmad-old', '.claude/skills/./bmad-old',
                     '.claude/skills/bmad-old/child', '.claude/skills',
                     '.claude/skills/unrelated', '.codex/skills/bmad-old'):
            with self.subTest(name=name):
                self.assert_rejected(name, self.outside)

    def test_symlink_in_each_path_component(self):
        for prefix in ('.claude', '.claude/skills', '.claude/skills/bmad-old',
                       '.agents', '.agents/skills', '.agents/skills/bmad-old'):
            with self.subTest(prefix=prefix):
                top = self.project / prefix.split('/')[0]
                if top.exists():
                    if top.is_symlink():
                        top.unlink()
                    else:
                        shutil.rmtree(top)
                link = self.project / prefix
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(self.outside, target_is_directory=True)
                self.assert_rejected(prefix.split('/')[0] + '/skills/bmad-old', self.outside)

    def test_no_op_does_not_bypass_validation(self):
        for relative in ('_config/manifest.yaml', 'scripts/resolve_config.py'):
            file = self.project / '_bmad' / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('present\n')
        with patch.object(self.setup, 'versions_match', return_value=True):
            self.assert_rejected('../outside-project', self.outside)

    def test_dangling_skill_symlink(self):
        link = self.project / '.claude/skills/bmad-old'
        link.parent.mkdir(parents=True)
        link.symlink_to(self.base / 'missing', target_is_directory=True)
        self.state('.claude/skills/bmad-old', self.outside)
        with patch.object(self.setup, 'run') as installer:
            with self.assertRaisesRegex(RuntimeError, 'symlink'):
                self.setup.setup(self.project)
            installer.assert_not_called()
        self.assertTrue(link.is_symlink())

    def test_regular_owned_skill_can_be_removed(self):
        for tool in ('.claude', '.agents'):
            directory = self.project / tool / 'skills/bmad-old'
            directory.mkdir(parents=True)
            (directory / 'SKILL.md').write_text('generated\n')
            self.state(f'{tool}/skills/bmad-old', directory)
            with patch.object(self.setup, 'run') as installer:
                self.setup.setup(self.project)
                installer.assert_called_once()
            self.assertFalse(directory.exists())
        self.assertEqual((self.outside / 'SKILL.md').read_text(), 'must survive\n')

    def test_installer_cannot_replace_skill_parent_with_symlink(self):
        directory = self.project / '.claude/skills/bmad-old'
        directory.mkdir(parents=True)
        (directory / 'SKILL.md').write_text('generated\n')
        self.state('.claude/skills/bmad-old', directory)

        def replace_parent(*args, **kwargs):
            shutil.rmtree(self.project / '.claude')
            (self.project / '.claude').symlink_to(self.outside, target_is_directory=True)

        with patch.object(self.setup, 'run', side_effect=replace_parent):
            with self.assertRaisesRegex(RuntimeError, 'symlink'):
                self.setup.setup(self.project)
        self.assertEqual((self.outside / 'SKILL.md').read_text(), 'must survive\n')


if __name__ == '__main__':
    unittest.main()
