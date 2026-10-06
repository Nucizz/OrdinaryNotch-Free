#!/usr/bin/env python3
"""Build the pinned BSD-licensed Now Playing adapter with the Xcode toolchain."""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import os

identity = os.environ.get('SIGNING_IDENTITY', '-')
root = pathlib.Path(__file__).resolve().parent.parent
source = root / 'Vendor/mediaremote-adapter'
resources = pathlib.Path(sys.argv[1])
framework = resources / 'MediaRemoteAdapter.framework'
version = framework / 'Versions/A'
(version / 'Resources').mkdir(parents=True, exist_ok=True)
sources = sorted(p for p in (source / 'src').rglob('*.m') if 'test' not in p.relative_to(source / 'src').parts)
sources.append(root / 'Sources/MediaAdapterSupport/ParentLifetime.m')
subprocess.run(['xcrun', 'clang', '-dynamiclib', '-fobjc-arc', '-fvisibility=default', '-O2',
                '-mmacosx-version-min=14.0', '-arch', 'arm64', '-arch', 'x86_64',
                '-I' + str(source / 'include'), '-I' + str(source / 'src'),
                '-framework', 'Foundation', '-framework', 'AppKit', '-framework', 'UniformTypeIdentifiers',
                '-install_name', '@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter',
                *map(str, sources), '-o', str(version / 'MediaRemoteAdapter')], check=True)
(version / 'Resources/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'dev.ordinary.notch.media-adapter', 'CFBundleExecutable': 'MediaRemoteAdapter',
    'CFBundleName': 'MediaRemoteAdapter', 'CFBundlePackageType': 'FMWK', 'CFBundleVersion': '1',
}))
for path, target in [(framework / 'Versions/Current', 'A'),
                     (framework / 'MediaRemoteAdapter', 'Versions/Current/MediaRemoteAdapter'),
                     (framework / 'Resources', 'Versions/Current/Resources')]:
    if not path.is_symlink():
        path.symlink_to(target)
shutil.copy2(source / 'bin/mediaremote-adapter.pl', resources)
shutil.copy2(source / 'LICENSE', resources / 'MediaRemoteAdapter-LICENSE.txt')
arguments = ['codesign', '--force', '--sign', identity]
if identity != '-': arguments += ['--options', 'runtime', '--timestamp']
subprocess.run(arguments + [str(framework)], check=True)
