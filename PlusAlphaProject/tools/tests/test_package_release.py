import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location('package_release',
    Path(__file__).resolve().parents[1] / 'package_release.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseArchiveTests(unittest.TestCase):
    def fixture(self, root):
        output = root / 'portable'
        (output / 'assets').mkdir(parents=True)
        (output / 'exPlusAlpha.exe').write_bytes(b'fake PE fixture; no compiler' * 100)
        (output / 'assets' / 'font.txt').write_text('runtime asset')
        files = {p.relative_to(output).as_posix(): release.sha256_file(p)
                 for p in output.rglob('*') if p.is_file()}
        (output / 'release-manifest.json').write_text(json.dumps(dict(schema=1, files=files)))
        return output

    def test_zip_contains_only_staged_inventory_and_checksum_matches(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = self.fixture(root)
            (root / 'private-save.mcr').write_text('not staged')
            archive = root / 'portable.zip'
            release.create_archive(output, archive)
            with zipfile.ZipFile(archive) as zipped:
                self.assertEqual(set(zipped.namelist()), {'portable/exPlusAlpha.exe',
                    'portable/assets/font.txt', 'portable/release-manifest.json'})
                self.assertIsNone(zipped.testzip())
            self.assertEqual(Path(str(archive) + '.sha256').read_text().split()[0],
                             release.sha256_file(archive))
            self.assertFalse(Path(str(archive) + '.partial').exists())

    def test_changed_binary_is_refused_before_zip_is_created(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = self.fixture(root)
            (output / 'exPlusAlpha.exe').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                release.create_archive(output, root / 'portable.zip')
            self.assertFalse((root / 'portable.zip').exists())

    def test_extra_personal_settings_are_not_silently_archived(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = self.fixture(root)
            (output / 'settings.toml').write_text('personal state')
            with self.assertRaises(ValueError):
                release.create_archive(output, root / 'portable.zip')

    def test_existing_archive_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = self.fixture(root)
            archive = root / 'portable.zip'
            archive.write_bytes(b'existing release')
            with self.assertRaises(ValueError):
                release.create_archive(output, archive)
            self.assertEqual(archive.read_bytes(), b'existing release')

    def test_zip_inside_package_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            output = self.fixture(Path(directory))
            with self.assertRaises(ValueError):
                release.create_archive(output, output / 'portable.zip')

    def test_diagnostic_cache_is_refused_without_running_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = root / 'build'
            build.mkdir()
            (build / 'CMakeCache.txt').write_text('CMAKE_BUILD_TYPE:STRING=RelWithDebInfo\n')
            with self.assertRaisesRegex(ValueError, 'CMAKE_BUILD_TYPE'):
                release.package(build, root / 'output', root / 'ucrt')
            self.assertFalse((root / 'output').exists())


if __name__ == '__main__':
    unittest.main()
