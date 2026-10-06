#!/usr/bin/env python3
"""Reject unreviewed source additions and known commercial-only components."""
import json
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'SOURCE_SCOPE.json').read_text())
expected = set(manifest['reviewedFiles'])
actual = {str(p.relative_to(root)) for folder in ('Sources', 'Resources', 'Vendor', 'Tests', 'scripts', '.github') for p in (root / folder).rglob('*') if p.is_file()}
errors = []
for name in sorted(actual - expected):
    errors.append(f'Unreviewed file: {name}')
for name in sorted(expected - actual):
    errors.append(f'Missing reviewed file: {name}')
for name in sorted(actual):
    p = root / name
    if p.suffix not in ('.swift', '.m', '.h', '.plist', '.py', '.yml'):
        continue
    text = p.read_text()
    if name.startswith('Sources/'):
        for token in ('FaceUnlock', 'FaceRecognition', 'FanHelper', 'FanControlService', 'PerformanceFanController', 'FanCurve', 'Membership', 'Patreon', 'VPNService', 'EyeBreak', 'WaterReminder', 'WorkAppService', 'WorkSetup', 'gptWork', 'claudeWork', 'SUUpdater', 'Sparkle'):
            if token in text:
                errors.append(f'Commercial component {token}: {name}')
    if re.search(r'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)', text):
        errors.append(f'Possible credential: {name}')
    if name.startswith('Sources/') and re.search(r'/Users/[^/\s]+/', text):
        errors.append(f'Local personal path: {name}')
telemetry = (root / 'Sources/FanCore/FanTelemetry.swift').read_text()
if re.search(r'command:\s*6\b|writeFan|setRPM|setManual', telemetry):
    errors.append('Fan telemetry contains a write operation')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'Free source scope verified: {len(actual)} reviewed files; no known commercial components.')
