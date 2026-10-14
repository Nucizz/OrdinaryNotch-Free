#!/usr/bin/env python3
"""Test and package Free locally; optionally upload a separate free-v release."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPO = 'Nucizz/OrdinaryNotch-Free'


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''): digest.update(chunk)
    return digest.hexdigest()


def version_tag(version):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version): raise ValueError('Free version must use x.y.z.')
    return 'free-v' + version


def prepare(check_only=False):
    env = {**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'}
    sdk = run('xcrun', '--sdk', 'macosx', '--show-sdk-version', capture_output=True, text=True).stdout.strip()
    if int(sdk.split('.')[0]) < 27: raise RuntimeError('Select Xcode 27 or later with DEVELOPER_DIR.')
    run(sys.executable, 'scripts/check-source-scope.py', cwd=ROOT, env=env)
    with tempfile.TemporaryDirectory(prefix='ordinary-free-release-') as temporary:
        scratch = Path(temporary)/'swift'
        env['ORDINARY_FREE_BUILD_DIR'] = str(scratch)
        env['ORDINARY_FREE_APP_OUTPUT'] = str(Path(temporary)/'Ordinary Notch Free.app')
        run('swift', 'test', '--disable-sandbox', '--scratch-path', scratch, cwd=ROOT, env=env)
        run(sys.executable, '-m', 'unittest', 'discover', '-s', 'Tests', '-p', 'test_*.py', cwd=ROOT, env=env)
        if check_only: return None
        info = plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
        version = info['CFBundleShortVersionString']
        tag = version_tag(version)
        output = ROOT/'build'/tag
        if output.exists(): raise RuntimeError(f'{output} already exists. Reuse it with --publish --resume, or move it before rebuilding.')
        run(sys.executable, 'scripts/build-app.py', cwd=ROOT, env=env)
        name = f'OrdinaryNotch-Free-{version}.zip'
        archive = Path(temporary)/name
        run('ditto', '-c', '-k', '--keepParent', env['ORDINARY_FREE_APP_OUTPUT'], archive)
        commit = run('git', 'rev-parse', 'HEAD', cwd=ROOT, capture_output=True, text=True).stdout.strip()
        dirty = bool(run('git', 'status', '--porcelain', cwd=ROOT, capture_output=True, text=True).stdout.strip())
        output.mkdir(parents=True)
        shutil.copy2(archive, output/name)
        (output/'SHA256SUMS').write_text(f'{sha256(archive)}  {name}\n')
        (output/'free-release.json').write_text(json.dumps({'tag': tag, 'version': version, 'commit': commit,
            'dirty': dirty, 'file': name, 'sha256': sha256(archive), 'size': archive.stat().st_size}, indent=2) + '\n')
        print(f'Free package ready: {output}')
        return output


def verify_assets(release, paths):
    for path in paths:
        asset = next((item for item in release['assets'] if item['name'] == path.name), None)
        if not asset or asset.get('state') != 'uploaded' or asset.get('size') != path.stat().st_size or asset.get('digest') != 'sha256:' + sha256(path):
            raise RuntimeError('GitHub asset missing or changed: ' + path.name)


def publish(directory):
    metadata = json.loads((directory/'free-release.json').read_text())
    tag = version_tag(metadata['version'])
    name = f'OrdinaryNotch-Free-{metadata["version"]}.zip'
    if metadata.get('tag') != tag or metadata.get('file') != name or metadata.get('dirty') is not False:
        raise RuntimeError('Publish only a clean, committed Free build. Rebuild after committing the source.')
    archive = directory/name
    if metadata['sha256'] != sha256(archive) or metadata['size'] != archive.stat().st_size:
        raise RuntimeError('Prepared Free archive changed; refusing to publish.')
    if (directory/'SHA256SUMS').read_text() != f'{sha256(archive)}  {name}\n':
        raise RuntimeError('Prepared checksums changed; refusing to publish.')
    paths = [archive, directory/'SHA256SUMS', directory/'free-release.json']
    def gh(*args, check=True):
        return subprocess.run(['gh', *args], check=check, capture_output=True, text=True)
    def view():
        result = gh('release', 'view', tag, '--repo', REPO, '--json', 'assets,isDraft', check=False)
        if result.returncode:
            if 'release not found' in result.stderr.lower(): return None
            raise RuntimeError('Cannot inspect Free release. Check GitHub authentication and repository access.')
        return json.loads(result.stdout)
    release = view()
    if release is None:
        gh('release', 'create', tag, '--repo', REPO, '--target', metadata['commit'], '--draft', '--latest=false',
           '--title', 'Ordinary Notch Free ' + metadata['version'], '--notes',
           'MIT-licensed Free app built from this repository. Ad-hoc/local signing; not Apple notarized. Official app downloads are separate v releases.')
        release = view()
    for path in paths:
        if any(asset['name'] == path.name for asset in release['assets']): verify_assets(release, [path])
        elif release['isDraft']: gh('release', 'upload', tag, '--repo', REPO, str(path))
        else: raise RuntimeError('Published Free release is incomplete; refusing to change it.')
    verify_assets(view(), paths)
    if release['isDraft']: gh('release', 'edit', tag, '--repo', REPO, '--draft=false', '--latest=false')
    final = view()
    if final['isDraft']: raise RuntimeError('Free release is still a draft.')
    verify_assets(final, paths)
    for path in paths: path.unlink()
    if not any(directory.iterdir()): directory.rmdir()
    print(f'Published {tag}; removed uploaded local files. The official latest release and update feed were not changed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Run source-scope and all tests without creating an app bundle.')
    parser.add_argument('--publish', action='store_true', help='Publish a Free release to GitHub, without changing the official latest release.')
    parser.add_argument('--resume', type=Path, help='Publish a previously prepared directory without rebuilding.')
    options = parser.parse_args()
    if options.resume and (not options.publish or options.check): parser.error('--resume requires --publish and cannot use --check')
    if options.check and options.publish: parser.error('--check cannot use --publish')
    output = options.resume.resolve() if options.resume else prepare(check_only=options.check)
    if options.publish: publish(output)


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error: sys.exit(str(error))
