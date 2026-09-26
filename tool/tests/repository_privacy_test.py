"""Exercise pre-commit privacy checks with synthetic, isolated repositories."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class RepositoryPrivacyTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='mubangumi-privacy-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'tool').mkdir()
        shutil.copy2(Path(__file__).resolve().parents[1] / 'verify_repository_privacy.ps1',
                     self.root / 'tool/verify_repository_privacy.ps1')
        subprocess.run(['git', 'init', '--quiet', str(self.root)], check=True)
        self.write('.gitignore', 'config/oauth.local.json\n.dart_tool/\n')

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value if isinstance(value, bytes) else value.encode())

    def check(self):
        return subprocess.run(
            ['pwsh', '-NoProfile', '-File', str(self.root / 'tool/verify_repository_privacy.ps1')],
            # PowerShell's diagnostic decoration follows the host console code
            # page. Assertions use ASCII file names and synthetic secrets only.
            cwd=self.root, capture_output=True, text=True, encoding='utf-8',
            errors='replace')

    def test_ignores_private_local_configuration(self):
        self.write('config/oauth.local.json', 'synthetic-local-only')
        self.write('.dart_tool/private.sqlite', b'SQLite format 3\0')
        self.assertEqual(self.check().returncode, 0)

    def test_rejects_new_runtime_data_and_symbols(self):
        for name in ('data.sqlite', 'session/Cookies', 'app.windows.symbols',
                     'model.onnx', 'private.pdb', 'weights.npz'):
            with self.subTest(name=name):
                self.write(name, 'synthetic')
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name, result.stderr)
                (self.root / name).unlink()

    def test_rejects_renamed_database(self):
        self.write('snapshot.bin', b'SQLite format 3\0synthetic')
        self.assertNotEqual(self.check().returncode, 0)

    def test_rejects_personal_path_without_echoing_it(self):
        value = 'C:' + '/Users/' + 'synthetic-person/private'
        self.write('report.txt', value)
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(value, result.stdout + result.stderr)

    def test_rejects_token_without_echoing_it(self):
        value = 'ghp_' + 'A' * 36
        self.write('report.md', value)
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(value, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
