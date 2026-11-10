#!/usr/bin/env python3
"""Project setup using the pinned official installer; no editor config mutation."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parent
OPTIONS = json.loads((ROOT / 'options.json').read_text())


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def skill_hashes(directory):
    return {str(p.relative_to(directory)): digest(p)
            for p in directory.rglob('*') if p.is_file()}


def skill_directory(project, name):
    # State lives in the writable workspace: never trust its keys as paths.
    # Match the complete spelling before Path can normalize ../ or ./ away.
    if not isinstance(name, str) or not re.fullmatch(
            r'\.(?:claude|agents)/skills/bmad-[a-z0-9][a-z0-9-]*', name):
        raise RuntimeError(f'Unsafe BMAD skill path: {name!r}')
    directory = project
    for part in name.split('/'):
        directory = directory / part
        if directory.is_symlink():
            raise RuntimeError(f'Unsafe BMAD skill path (symlink): {directory}')
    if not directory.resolve().is_relative_to(project.resolve()):
        raise RuntimeError(f'Unsafe BMAD skill path: {name!r}')
    return directory


def save_state(path, state):
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent,
                                     prefix='.bmad-feature-', delete=False) as file:
        json.dump(state, file, indent=2)
        file.write('\n')
    os.replace(file.name, path)


def versions_match(bmad):
    manifest = bmad / '_config/manifest.yaml'
    if not manifest.is_file():
        return False
    # This is the fixed v6 manifest format emitted by the official installer.
    installed = dict(re.findall(r'^  - name: ([a-z]+)\n    version: ([^\n]+)',
                                manifest.read_text(), re.MULTILINE))
    expected = dict(core=OPTIONS['bmad'])
    for module in OPTIONS['modules'].split(','):
        expected[module] = OPTIONS['tea'] if module == 'tea' else OPTIONS['bmad']
    return installed == expected


def main():
    account = pwd.getpwnam(OPTIONS['user'])
    if os.getuid() == 0 and account.pw_uid != 0:
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)
    if os.getuid() != account.pw_uid:
        raise RuntimeError('Run bmad-setup as the configured remote user.')
    os.environ['HOME'] = OPTIONS['home']
    os.environ['UV_PYTHON_DOWNLOADS'] = 'never'
    # Lifecycle scripts start in the workspace; an explicit argument/env wins.
    project = Path(sys.argv[1] if len(sys.argv) > 1 else
                   os.environ.get('BMAD_WORKSPACE', os.getcwd())).resolve(strict=True)
    if not project.is_dir() or project == Path('/'):
        raise RuntimeError('BMAD workspace must be an existing project directory.')
    lock_name = hashlib.sha256(str(project).encode()).hexdigest()
    with open(f'/tmp/bmad-feature-{os.getuid()}-{lock_name}.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        setup(project)


def setup(project):
    bmad = project / '_bmad'
    state_path = bmad / '.devcontainer-feature.json'
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    desired = {k: OPTIONS[k] for k in ('bmad', 'tea', 'modules', 'tools')}
    inventory = json.loads((ROOT / 'skills.json').read_text())
    old_skills = state.get('skills', {})
    if not isinstance(old_skills, dict):
        raise RuntimeError('Invalid BMAD skills state: expected an object.')
    # Validate even on the no-op path, and before hashing or invoking BMAD.
    for name in old_skills:
        skill_directory(project, name)
    wanted = set()
    for relative in inventory:
        if not isinstance(relative, str) or not relative.endswith('/SKILL.md'):
            raise RuntimeError(f'Invalid BMAD skill inventory entry: {relative!r}')
        name = relative.removesuffix('/SKILL.md')
        skill_directory(project, name)
        wanted.add(name)
    required = ('_config/manifest.yaml', 'config.toml', 'scripts/resolve_config.py')
    if (state.get('configuration') == desired
            and old_skills
            and versions_match(bmad)
            and all((project / name / 'SKILL.md').is_file() for name in old_skills)
            and all((bmad / name).is_file() for name in required)):
        print(f'BMAD: already configured in {project}')
        return
    # An owned skill may be refreshed only while unmodified. Users should put
    # durable BMAD customizations in the official _bmad/custom directory.
    for name, hashes in old_skills.items():
        directory = project / name
        if directory.exists() and skill_hashes(directory) != hashes:
            raise RuntimeError(f'Modified generated skill preserved: {directory}. '
                               'Move overrides to _bmad/custom before updating.')
    for relative in inventory:
        directory = (project / relative).parent
        name = str(directory.relative_to(project))
        if (directory.exists() or directory.is_symlink()) and name not in old_skills:
            raise RuntimeError(f'Existing skill preserved: {directory}; '
                               'resolve this name collision before setup.')
    fresh = not (bmad / 'config.toml').exists()
    args = ['bmad', 'install', '--directory', str(project), '--modules', OPTIONS['modules'],
            '--tools', OPTIONS['tools'], '--pin', f"tea={OPTIONS['tea']}",
            '--action', 'update' if bmad.exists() else 'install', '--yes', '--no-shims']
    if fresh:
        args += ['--user-name', 'BMad', '--communication-language', OPTIONS['communication'],
                 '--document-output-language', OPTIONS['document']]
    else:
        # Preserve install answers, including language edits to central files.
        core = {}
        for name in ('config.toml', 'config.user.toml'):
            file = bmad / name
            if file.exists():
                core.update(tomllib.loads(file.read_text()).get('core', {}))
        for key, flag in (('user_name', '--user-name'),
                          ('communication_language', '--communication-language'),
                          ('document_output_language', '--document-output-language')):
            if key in core:
                args += [flag, str(core[key])]
    # Adding TEA also needs safe defaults. Do not rewrite existing TEA answers.
    new_tea = ('tea' in OPTIONS['modules'].split(',')
               and (not (bmad / 'tea').exists() or state.get('initialize_tea', False)))
    if new_tea:
        args += ['--set', 'tea.tea_use_playwright_utils=false',
                 '--set', 'tea.tea_use_pactjs_utils=false',
                 '--set', 'tea.tea_pact_mcp=none',
                 '--set', 'tea.tea_browser_automation=none']
    with tempfile.TemporaryDirectory(prefix='bmad-installer-') as temp:
        home = Path(temp)
        cache = ROOT / 'installer-cache'
        if cache.exists():
            shutil.copytree(cache, home / '.bmad')
        env = dict(os.environ, HOME=str(home))
        try:
            run(*args, cwd=project, env=env)
        finally:
            # A failed/ interrupted installer may have created some skills.
            # Record ownership without a success configuration, allowing a
            # later retry while still detecting edits to partial output.
            if bmad.is_dir():
                owned = set(old_skills) | wanted
                pending = {name: skill_hashes(skill_directory(project, name)) for name in owned
                           if skill_directory(project, name).is_dir()}
                save_state(state_path, dict(skills=pending, initialize_tea=new_tea))
    if new_tea:
        # v6.12.4 --set emits strings for false, including in TOML. Correct
        # only the two values supplied above, then verify the actual resolver.
        file = bmad / 'config.toml'
        text = file.read_text()
        for key in ('tea_use_playwright_utils', 'tea_use_pactjs_utils'):
            text = text.replace(f'{key} = "false"', f'{key} = false')
        file.write_text(text)
        file = bmad / 'tea/config.yaml'
        if file.exists():
            text = file.read_text()
            for key in ('tea_use_playwright_utils', 'tea_use_pactjs_utils'):
                for quote in ('"', "'"):
                    text = text.replace(f'{key}: {quote}false{quote}', f'{key}: false')
            file.write_text(text)
        output = subprocess.check_output(
            ['python3', str(bmad / 'scripts/resolve_config.py'), '--project-root', str(project)],
            text=True)
        values = json.loads(output)['modules']['tea']
        for key in ('tea_use_playwright_utils', 'tea_use_pactjs_utils'):
            if not isinstance(values[key], bool):
                raise RuntimeError(f'Expected boolean from BMAD resolver for {key}')
    # Remove only previously owned, unmodified skill trees on deselection.
    for name in old_skills.keys() - wanted:
        directory = skill_directory(project, name)
        if directory.exists():
            shutil.rmtree(directory)
    skills = {name: skill_hashes(skill_directory(project, name)) for name in sorted(wanted)}
    for name in skills:
        if not (project / name / 'SKILL.md').is_file():
            raise RuntimeError(f'Official installer did not generate {name}')
    save_state(state_path, dict(configuration=desired, skills=skills))
    print(f'BMAD: configured in {project}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(f'BMAD setup failed: {error}')
