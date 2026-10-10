"""No engine, export, gameplay or network; tests use synthetic binary fixtures."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import zipfile

import package_windows_release as package


def pe_fixture(path, machine=0x8664):
    header = bytearray(512)
    header[:2] = b'MZ'
    struct.pack_into('<I', header, 60, 128)
    header[128:132] = b'PE\0\0'
    struct.pack_into('<H', header, 132, machine)
    struct.pack_into('<H', header, 152, 0x20B)
    path.write_bytes(header)


class PackageTests(unittest.TestCase):
    def setup_tree(self, directory):
        base = Path(directory)
        root = base / 'project'
        runtime = base / 'build'
        runtime.mkdir()
        notices = root / 'tools/lan-release'
        notices.mkdir(parents=True)
        for name in package.NOTICE_FILES:
            (notices / name).write_text('license test fixture', encoding='utf-8')
        (notices / '使用说明.txt').write_text('test', encoding='utf-8')
        audio = root / 'assets/audio/free-firearms'
        audio.mkdir(parents=True)
        for name in ('LICENSE.md', 'ADDITIONAL_LICENSES.md'):
            (audio / name).write_text('audio fixture', encoding='utf-8')
        for name in package.RELEASE_DOCS:
            document = root / name
            document.parent.mkdir(parents=True, exist_ok=True)
            document.write_text('selected document fixture', encoding='utf-8')
        pe_fixture(runtime / 'LittleBattlefield.exe')
        (runtime / 'LittleBattlefield.pck').write_bytes(b'GDPC' + bytes(200))
        return root, runtime, base / 'output'

    def test_preset_excludes_previous_packages_and_diagnostics(self):
        text = (Path(__file__).parents[1] / 'export_presets.cfg').read_text()
        line = next(line for line in text.splitlines() if line.startswith('exclude_filter='))
        filters = line.split('=', 1)[1].strip('"').split(',')
        for pattern in ('build/*', 'exports/*', 'qa/iteration_20261009/*', 'qa/flash_registration_contract.json', 'data/campaign/drafts/*', '*.log'):
            self.assertIn(pattern, filters)

    def test_powershell_hashes_preserve_unicode_filenames(self):
        text = (Path(__file__).with_name('package_lan_release.ps1')).read_text()
        self.assertTrue(Path(__file__).with_name('package_lan_release.ps1').read_bytes().startswith(b'\xef\xbb\xbf'))
        self.assertIn('[System.Text.UTF8Encoding]::new($false)', text)
        self.assertNotIn("'SHA256SUMS.txt') -Encoding ASCII", text)

    def test_addresses(self):
        self.assertEqual(package.normalize_endpoint(' 192.168.1.8:27829 '), '192.168.1.8:27829')
        self.assertEqual(package.normalize_endpoint(''), '')
        for bad in ('999.2.3.4', '::1', 'localhost', '1.2.3.4:0', '1.2.3.4:65536', '1.2.3.4\nextra'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                package.normalize_endpoint(bad)

    def test_binary_headers(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'a.exe'
            pe_fixture(file)
            package.check_windows_binary(file)
            pe_fixture(file, machine=0x14C)
            with self.assertRaises(ValueError):
                package.check_windows_binary(file)
            file.write_bytes(b'not executable')
            with self.assertRaises(ValueError):
                package.check_windows_binary(file)

    def test_unique_stages_do_not_carry_host_preset(self):
        with tempfile.TemporaryDirectory() as directory:
            root, runtime, output = self.setup_tree(directory)
            (runtime / 'host-address.txt').write_text('old host')
            (runtime / 'export.log').write_text('log')
            first, _ = package.assemble(root, runtime, output, 'test', '4.6.3.stable', '192.168.1.2')
            first_hash = package.sha256(first)
            second, result = package.assemble(root, runtime, output, 'test', '4.6.3.stable')
            self.assertNotEqual(first, second)
            self.assertTrue(first.is_file())
            self.assertEqual(package.sha256(first), first_hash)
            with zipfile.ZipFile(first) as archive:
                self.assertTrue(any(name.endswith('/host-address.txt') for name in archive.namelist()))
            with zipfile.ZipFile(second) as archive:
                self.assertFalse(any(name.endswith('/host-address.txt') for name in archive.namelist()))
                self.assertFalse(any(name.endswith('/export.log') for name in archive.namelist()))
                self.assertTrue(any(name.endswith('/GODOT_COPYRIGHT.txt') for name in archive.namelist()))
            self.assertEqual(result['zip_sha256'], hashlib.sha256(second.read_bytes()).hexdigest())
            self.assertTrue(second.with_suffix('.zip.sha256').is_file())

    def test_multiple_versions_exact_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root, runtime, output = self.setup_tree(directory)
            expected = {'LittleBattlefield.exe', 'LittleBattlefield.pck', 'GODOT_LICENSE.txt',
                        'GODOT_COPYRIGHT.txt', '使用说明.txt', 'FREE_FIREARM_AUDIO_LICENSE.md',
                        'ADDITIONAL_AUDIO_LICENSES.md', 'VERSION.txt', 'ENGINE_VERSION.txt', 'SHA256SUMS.txt'}
            expected |= set(package.RELEASE_DOCS.values())
            archives = []
            for version in ('2026.10.09.1', '2026.10.09.2'):
                archive, _ = package.assemble(root, runtime, output, version, '4.6.3.stable')
                archives.append(archive)
                prefix = f'LittleBattlefield-LAN-v{version}-Windows'
                self.assertTrue(archive.name.startswith(prefix + '-'))
                with zipfile.ZipFile(archive) as zipped:
                    self.assertEqual(set(zipped.namelist()), {f'{prefix}/{name}' for name in expected})
                    self.assertEqual(zipped.read(prefix + '/VERSION.txt').decode().strip(), version)
                    self.assertEqual(zipped.read(prefix + '/LittleBattlefield.exe'), (runtime / 'LittleBattlefield.exe').read_bytes())
            self.assertTrue(all(archive.is_file() for archive in archives))
            self.assertEqual(len(list(output.glob('*.zip'))), 2)

    def test_launcher_cannot_overwrite_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root, runtime, output = self.setup_tree(directory)
            original = (runtime / 'LittleBattlefield.exe').read_bytes()
            (root / 'tools/lan-release/LittleBattlefield.exe').write_bytes(b'bad replacement')
            with self.assertRaisesRegex(ValueError, 'collides with exported binary'):
                package.assemble(root, runtime, output, 'test', '4.6.3.stable')
            self.assertEqual((runtime / 'LittleBattlefield.exe').read_bytes(), original)
            self.assertEqual(list(output.glob('*.zip')), [])

    def test_tampering_is_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            root, runtime, output = self.setup_tree(directory)
            archive, _ = package.assemble(root, runtime, output, 'test', '4.6.3.stable')
            package_root = archive.with_suffix('') / 'LittleBattlefield-LAN-vtest-Windows'
            (package_root / 'VERSION.txt').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                package.verify_package(package_root, archive)

    def test_invalid_version_and_runtime_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root, runtime, output = self.setup_tree(directory)
            with self.assertRaisesRegex(ValueError, 'Unsafe version'):
                package.assemble(root, runtime, output, '../escape', '4.6.3.stable')
            (runtime / 'LittleBattlefield.pck').write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'PCK header'):
                package.assemble(root, runtime, output, 'test', '4.6.3.stable')

    def test_template_receipt_is_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root, runtime, output = self.setup_tree(directory)
            (root / 'scripts').mkdir()
            (root / 'scripts/proving_ground.gd').write_text('const BUILD_VERSION="test"')
            data_home = Path(directory) / 'toolchain/share'
            templates = data_home / 'godot/export_templates/4.6.3.stable'
            templates.mkdir(parents=True)
            target = templates / package.WINDOWS_RELEASE
            pe_fixture(target)
            (templates / 'version.txt').write_text('4.6.3.stable')
            receipt = Path(directory) / 'receipt.json'
            record = {'engine_version': '4.6.3.stable', 'vendor_checksums_verified': True,
                      'extracted_files': [{'name': package.WINDOWS_RELEASE, 'sha256': package.sha256(target)}]}
            receipt.write_text(json.dumps(record))
            with patch.object(package.subprocess, 'run', return_value=SimpleNamespace(stdout='4.6.3.stable.official.test\n')):
                self.assertEqual(package.preflight(root, 'godot', data_home, receipt)[0], 'test')
                record['extracted_files'][0]['sha256'] = '0' * 64
                receipt.write_text(json.dumps(record))
                with self.assertRaisesRegex(ValueError, 'Template hash changed'):
                    package.preflight(root, 'godot', data_home, receipt)

    def test_launcher_preset_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root, runtime, output = self.setup_tree(directory)
            (root / 'tools/lan-release/host-address.txt').write_text('192.168.1.2')
            with self.assertRaisesRegex(ValueError, 'local host preset'):
                package.assemble(root, runtime, output, 'test', '4.6.3.stable')


if __name__ == '__main__':
    unittest.main()
