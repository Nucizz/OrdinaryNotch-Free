import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('local_release', ROOT/'scripts/release-local.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class FreeReleaseTests(unittest.TestCase):
    def test_free_tags_cannot_use_the_official_release_namespace(self):
        self.assertEqual(release.version_tag('0.2.0'), 'free-v0.2.0')
        for value in ['v0.2.0', '../latest', '0.2.0/bad']:
            with self.assertRaises(ValueError): release.version_tag(value)

    def test_local_or_modified_archive_never_reaches_github(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = {'version': '0.2.0', 'tag': 'free-v0.2.0', 'file': 'OrdinaryNotch-Free-0.2.0.zip',
                        'dirty': True, 'sha256': 'invalid', 'size': 3}
            manifest = root/'free-release.json'
            manifest.write_text(json.dumps(metadata))
            with patch.object(release.subprocess, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, 'clean, committed'): release.publish(root)
                run.assert_not_called()
                metadata['dirty'] = False
                manifest.write_text(json.dumps(metadata))
                (root/metadata['file']).write_bytes(b'zip')
                with self.assertRaisesRegex(RuntimeError, 'archive changed'): release.publish(root)
                run.assert_not_called()

    def test_failed_upload_keeps_local_assets_and_does_not_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root/'OrdinaryNotch-Free-0.2.0.zip'; archive.write_bytes(b'zip')
            checksum = hashlib.sha256(b'zip').hexdigest()
            (root/'SHA256SUMS').write_text(f'{checksum}  {archive.name}\n')
            (root/'free-release.json').write_text(json.dumps({'version': '0.2.0', 'tag': 'free-v0.2.0',
                'file': archive.name, 'dirty': False, 'commit': 'a'*40, 'size': 3, 'sha256': checksum}))
            calls = []
            def run(args, **kwargs):
                calls.append(args)
                if args[2] == 'upload': raise subprocess.CalledProcessError(1, args)
                return subprocess.CompletedProcess(args, 0, json.dumps({'isDraft': True, 'assets': []}))
            with patch.object(release.subprocess, 'run', side_effect=run):
                with self.assertRaises(subprocess.CalledProcessError): release.publish(root)
            self.assertTrue(archive.exists())
            self.assertFalse(any('edit' in args for args in calls))

    def test_remote_checksum_must_match_before_reusing_an_asset(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'file.zip'; path.write_bytes(b'data')
            asset = {'name': path.name, 'size': 4, 'state': 'uploaded', 'digest': 'sha256:' + release.sha256(path)}
            release.verify_assets({'assets': [asset]}, [path])
            path.write_bytes(b'else')
            with self.assertRaises(RuntimeError): release.verify_assets({'assets': [asset]}, [path])
