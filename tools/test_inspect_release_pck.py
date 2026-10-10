import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

import inspect_release_pck as pck


def fixture(path, version, files):
    directory = bytearray(struct.pack('<I', len(files)))
    payload = bytearray()
    for name, data in files:
        encoded = ('res://' + name).encode()
        encoded += b'\0' * (-len(encoded) % 4)
        directory += struct.pack('<I', len(encoded)) + encoded
        directory += struct.pack('<QQ', len(payload), len(data)) + hashlib.md5(data).digest() + struct.pack('<I', 0)
        payload += data
    base = 104 if version == 3 else 96 + len(directory)
    header = b'GDPC' + struct.pack('<IIIIIQ', version, 4, 6, 3, 2, base)
    if version == 3:
        header += struct.pack('<Q', base + len(payload)) + bytes(64)
        path.write_bytes(header + payload + directory)
    else:
        path.write_bytes(header + bytes(64) + directory + payload)


class PckTests(unittest.TestCase):
    def test_v2_v3_and_data_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            for version in (2, 3):
                path = Path(directory) / f'{version}.pck'
                fixture(path, version, [('data/a.json', b'{"x":1}'), ('assets/中文.txt', b'abc')])
                report = pck.read_inventory(path, True)
                self.assertEqual(report['file_count'], 2)
                self.assertTrue(report['content_md5_verified'])
                self.assertEqual(report['files'][0]['path'], 'assets/中文.txt')
                with path.open('r+b') as stream:
                    stream.seek(report['files'][0]['offset'])
                    stream.write(b'X')
                with self.assertRaisesRegex(ValueError, 'MD5 mismatch'):
                    pck.read_inventory(path, True)

    def test_diagnostics_and_required_data(self):
        report = {'files': [{'path': name} for name in pck.REQUIRED_CAMPAIGN_DATA]}
        self.assertEqual(pck.check_release(report), [])
        for name in ('qa/flash_registration_contract.json', 'qa/iteration_20261009/a.json',
                     'data/campaign/drafts/old.json', 'exports/old/SOURCE_MANIFEST.json'):
            bad = {'files': report['files'] + [{'path': name}]}
            self.assertEqual(len(pck.check_release(bad)), 1)
        self.assertTrue(pck.check_release({'files': []}))

    def test_invalid_paths_and_header(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'a.pck'
            for names in ([('../bad', b'x')], [('same', b'x'), ('same', b'y')]):
                fixture(path, 3, names)
                with self.assertRaisesRegex(ValueError, 'Unsafe/duplicate'):
                    pck.read_inventory(path)
            path.write_bytes(b'GDPC')
            with self.assertRaisesRegex(ValueError, 'Truncated'):
                pck.read_inventory(path)


if __name__ == '__main__':
    unittest.main()
