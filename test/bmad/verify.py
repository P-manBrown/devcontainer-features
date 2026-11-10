#!/usr/bin/env python3
"""Real-installer integration checks. Runs without AI accounts or Docker."""
import hashlib
import itertools
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile

FEATURE = Path('/usr/local/share/bmad-feature')
SOURCE = Path(__file__).resolve().parents[2] / 'src/bmad/setup.py'


def run(*args, **kwargs):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, **kwargs)
    if result.returncode:
        raise AssertionError(f'{args}:\n{result.stdout}')
    return result.stdout


def snapshot(directory):
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob('*') if p.is_file()}


def resolved(project):
    return json.loads(run('uv', 'run', '--no-python-downloads',
                         str(project / '_bmad/scripts/resolve_config.py'),
                         '--project-root', str(project)))


def verify():
    options = json.loads((FEATURE / 'options.json').read_text())
    inventories = {}
    with tempfile.TemporaryDirectory(prefix='bmad-verification-') as temp:
        base = Path(temp)
        for modules in ('bmm', 'bmm,tea'):
            # Generate a complete official inventory for this module set.
            template = base / f'template-{modules}'
            run('bmad', 'install', '--directory', str(template), '--modules', modules,
                '--tools', 'claude-code,codex', '--pin', 'tea=v1.27.2', '--yes',
                env=dict(os.environ, HOME=str(base / 'cache-home')))
            all_skills = [str(p.relative_to(template)) for folder in ('.claude', '.agents')
                          for p in (template / folder / 'skills').glob('*/SKILL.md')]
            inventories[modules] = all_skills
            for tools in ('claude-code', 'codex', 'claude-code,codex'):
                for communication, document in itertools.product(('English', 'Japanese'), repeat=2):
                    root = base / f'{modules}-{tools}-{communication}-{document}'
                    root.mkdir()
                    project = root / 'workspace with spaces'
                    project.mkdir()
                    fixture = root / 'feature'
                    fixture.mkdir()
                    shutil.copy(SOURCE if SOURCE.exists() else FEATURE / 'setup.py', fixture / 'setup.py')
                    options.update(modules=modules, tools=tools, communication=communication, document=document)
                    (fixture / 'options.json').write_text(json.dumps(options))
                    inventory = [p for p in all_skills if
                                 (p.startswith('.claude/') and 'claude-code' in tools) or
                                 (p.startswith('.agents/') and 'codex' in tools)]
                    (fixture / 'skills.json').write_text(json.dumps(inventory))
                    # Preserve unrelated editor settings and skills.
                    sentinel = project / '.claude/skills/my-skill/SKILL.md'
                    sentinel.parent.mkdir(parents=True)
                    sentinel.write_text('keep my skill\n')
                    config = project / '.claude/settings.json'
                    config.write_text('{"keep":true}\n')
                    run('python3', str(fixture / 'setup.py'), str(project))
                    values = resolved(project)
                    assert values['core']['communication_language'] == communication
                    assert values['core']['document_output_language'] == document
                    assert values['core']['user_name'] == 'BMad'
                    assert config.read_text() == '{"keep":true}\n'
                    assert sentinel.read_text() == 'keep my skill\n'
                    assert (project / '.claude/skills/bmad-help/SKILL.md').exists() == ('claude-code' in tools)
                    assert (project / '.agents/skills/bmad-help/SKILL.md').exists() == ('codex' in tools)
                    manifest = (project / '_bmad/_config/manifest.yaml').read_text()
                    assert 'version: 6.12.4' in manifest
                    if modules == 'bmm,tea':
                        assert 'version: v1.27.2' in manifest
                        assert values['modules']['tea']['tea_use_playwright_utils'] is False
                        assert values['modules']['tea']['tea_use_pactjs_utils'] is False
                        yaml_values = json.loads(run('node', '-e',
                            'const fs=require("fs"),yaml=require(process.argv[1]);'
                            'console.log(JSON.stringify(yaml.parse(fs.readFileSync(process.argv[2],"utf8"))))',
                            str(FEATURE / 'runtime/node_modules/yaml'), str(project / '_bmad/tea/config.yaml')))
                        assert yaml_values['tea_use_playwright_utils'] is False
                        assert yaml_values['tea_use_pactjs_utils'] is False
                    assert all(p.stat().st_uid == os.getuid() for p in project.rglob('*'))
                    custom = project / '_bmad/custom/config.user.toml'
                    custom.write_text('[core]\ncommunication_language = "Japanese"\n'
                                      'document_output_language = "English"\nuser_name = "Local User"\n')
                    before = snapshot(project)
                    # Language option changes do not overwrite existing configuration.
                    options.update(communication='English', document='Japanese')
                    (fixture / 'options.json').write_text(json.dumps(options))
                    run('python3', str(fixture / 'setup.py'), str(project))
                    assert before == snapshot(project)
                    assert resolved(project)['core']['user_name'] == 'Local User'
                    # Rebuild simulation: replace only the image-side Feature files.
                    copied = root / 'rebuilt-feature'
                    shutil.copytree(fixture, copied)
                    run('python3', str(copied / 'setup.py'), str(project))
                    assert before == snapshot(project)
                    # Force a program refresh using the official update path.
                    state_path = project / '_bmad/.devcontainer-feature.json'
                    state = json.loads(state_path.read_text())
                    if communication == document == 'English':
                        # Do not trust only our marker after an external update.
                        manifest_path = project / '_bmad/_config/manifest.yaml'
                        manifest_path.write_text(manifest_path.read_text().replace(
                            'version: 6.12.4', 'version: 0.0.0'))
                    else:
                        state['configuration']['bmad'] = 'old'
                        state_path.write_text(json.dumps(state))
                    run('python3', str(copied / 'setup.py'), str(project))
                    assert 'version: 6.12.4' in (project / '_bmad/_config/manifest.yaml').read_text()
                    assert custom.read_text().endswith('user_name = "Local User"\n')
                    assert resolved(project)['core']['user_name'] == 'Local User'
                    print(f'PASS {modules} / {tools} / {communication} / {document}', flush=True)
        # Change the actual selection on an existing project.
        for modules, tools in (('bmm', 'claude-code'), ('bmm,tea', 'claude-code,codex')):
            options.update(modules=modules, tools=tools)
            (fixture / 'options.json').write_text(json.dumps(options))
            inventory = [p for p in inventories[modules] if
                         p.startswith('.claude/') or 'codex' in tools]
            (fixture / 'skills.json').write_text(json.dumps(inventory))
            run('python3', str(fixture / 'setup.py'), str(project))
            assert (project / '.agents/skills/bmad-help/SKILL.md').exists() == ('codex' in tools)
            assert (project / '.claude/skills/bmad-tea/SKILL.md').exists() == ('tea' in modules)
            assert resolved(project)['core']['user_name'] == 'Local User'
        print('PASS module/tool removal and addition', flush=True)
        # A changed generated skill is preserved on an ordinary restart and
        # blocks an update before any project file is overwritten.
        generated = project / inventory[0]
        generated.write_text(generated.read_text() + '\nUser edit\n')
        before = snapshot(project)
        run('python3', str(fixture / 'setup.py'), str(project))
        assert snapshot(project) == before
        state_path = project / '_bmad/.devcontainer-feature.json'
        state = json.loads(state_path.read_text())
        state['configuration']['bmad'] = 'old'
        state_path.write_text(json.dumps(state))
        before = snapshot(project)
        result = subprocess.run(['python3', str(fixture / 'setup.py'), str(project)],
                                capture_output=True, text=True)
        assert result.returncode != 0 and 'Modified generated skill preserved' in result.stderr
        assert snapshot(project) == before
        print('PASS modified generated skill protection', flush=True)
        # Simulate a failure after official generation, then retry. The pending
        # ownership record must allow repair, including the false-string fix.
        retry_project = base / 'retry'
        retry_project.mkdir()
        existing_custom = retry_project / '_bmad/custom/config.user.toml'
        existing_custom.parent.mkdir(parents=True)
        existing_custom.write_text('[core]\ncommunication_language="Japanese"\n')
        shim = base / 'shim'
        shim.mkdir()
        executable = shim / 'bmad'
        executable.write_text('#!/bin/sh\n' + shlex.quote(shutil.which('bmad')) +
                              ' "$@"\nexit 17\n')
        executable.chmod(0o755)
        failed = subprocess.run(['python3', str(fixture / 'setup.py'), str(retry_project)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                env=dict(os.environ, PATH=str(shim) + ':' + os.environ['PATH']))
        assert failed.returncode != 0
        pending = json.loads((retry_project / '_bmad/.devcontainer-feature.json').read_text())
        assert 'configuration' not in pending
        run('python3', str(fixture / 'setup.py'), str(retry_project))
        assert resolved(retry_project)['modules']['tea']['tea_use_playwright_utils'] is False
        assert existing_custom.read_text() == '[core]\ncommunication_language="Japanese"\n'
        print('PASS partial install retry and preexisting customization', flush=True)
        # Name collisions fail without modifying existing skills.
        collision = base / 'collision'
        target = collision / Path(inventory[0]).parent
        target.mkdir(parents=True)
        (target / 'SKILL.md').write_text('existing user skill')
        result = subprocess.run(['python3', str(fixture / 'setup.py'), str(collision)],
                                capture_output=True, text=True)
        assert result.returncode != 0 and 'Existing skill preserved' in result.stderr
        assert (target / 'SKILL.md').read_text() == 'existing user skill'
        print('PASS collision protection', flush=True)


if __name__ == '__main__':
    verify()
