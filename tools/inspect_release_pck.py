#!/usr/bin/env python3
"""Read unencrypted standalone Godot 4 PCK v2/v3 inventories without starting Godot.
Format reference: official 4.6.3-stable core/io/file_access_pack.cpp and .h:
https://github.com/godotengine/godot/blob/4.6.3-stable/core/io/file_access_pack.cpp
"""
import argparse
import fnmatch
import hashlib
import json
from pathlib import Path, PurePosixPath
import struct

RELEASE_EXCLUSIONS = ('build/*', 'exports/*', 'qa/iteration_20261009/*',
                      'qa/flash_registration_contract.json', 'data/campaign/drafts/*', '*.log')
REQUIRED_CAMPAIGN_DATA = ('data/campaign/chapters.json', 'data/campaign/level01_rules.json',
                          'data/original/scenes.json', 'data/original/catalog.json')


def read_inventory(path: Path, verify_md5: bool = False) -> dict:
    total = path.stat().st_size
    entries = []
    names = set()
    with path.open('rb') as stream:
        def read(count):
            data = stream.read(count)
            if len(data) != count:
                raise ValueError('Truncated PCK directory/header')
            return data

        def uint32():
            return struct.unpack('<I', read(4))[0]

        def uint64():
            return struct.unpack('<Q', read(8))[0]

        if read(4) != b'GDPC':
            raise ValueError('Expected standalone Godot PCK magic')
        version = uint32()
        if version not in (2, 3):
            raise ValueError(f'Unsupported PCK version: {version}')
        engine = [uint32(), uint32(), uint32()]
        flags = uint32()
        if flags & ~2:
            raise ValueError('Encrypted/sparse/unknown PCK mode is not supported by this reader')
        file_base = uint64()
        if version == 3:
            directory = uint64()
            if directory < 40 or directory > total - 4:
                raise ValueError('PCK directory offset is outside the file')
            stream.seek(directory)
        else:
            read(64)
        count = uint32()
        if count > 1000000:
            raise ValueError('Unreasonable PCK file count')
        for _ in range(count):
            length = uint32()
            if not 0 < length <= 1048576:
                raise ValueError('Invalid PCK path length')
            name = read(length).rstrip(b'\0').decode('utf-8').removeprefix('res://')
            relative = PurePosixPath(name)
            if not name or '\0' in name or '\\' in name or relative.is_absolute() or '..' in relative.parts or name in names:
                raise ValueError(f'Unsafe/duplicate PCK path: {name!r}')
            offset, size = file_base + uint64(), uint64()
            checksum = read(16).hex()
            file_flags = uint32()
            if file_flags:
                raise ValueError('Encrypted/removal/delta entry is unsupported for a full release')
            if offset > total or size > total - offset:
                raise ValueError(f'PCK entry lies outside file: {name}')
            entries.append({'path': name, 'bytes': size, 'offset': offset, 'md5': checksum})
            names.add(name)
        if verify_md5:
            for item in entries:
                stream.seek(item['offset'])
                left = item['bytes']
                digest = hashlib.md5()
                while left:
                    block = read(min(1024 * 1024, left))
                    digest.update(block)
                    left -= len(block)
                if digest.hexdigest() != item['md5']:
                    raise ValueError(f'PCK content MD5 mismatch: {item["path"]}')
    return {'schema_version': 1, 'pck_format': version, 'engine_version': '.'.join(map(str, engine)),
            'file_count': len(entries), 'content_md5_verified': verify_md5,
            'files': sorted(entries, key=lambda item: item['path'])}


def check_release(report):
    names = {item['path'] for item in report['files']}
    errors = [f'Missing campaign data: {name}' for name in REQUIRED_CAMPAIGN_DATA if name not in names]
    for name in sorted(names):
        if any(fnmatch.fnmatchcase(name, pattern) for pattern in RELEASE_EXCLUSIONS):
            errors.append(f'Excluded diagnostic/old output present in PCK: {name}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pck', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify-md5', action='store_true')
    parser.add_argument('--check-release', action='store_true')
    args = parser.parse_args()
    try:
        result = read_inventory(args.pck, args.verify_md5)
        errors = check_release(result) if args.check_release else []
        if errors:
            raise ValueError('\n'.join(errors))
        if args.output:
            args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'PCK inventory PASS: {result["file_count"]} files, format {result["pck_format"]}, engine {result["engine_version"]}; content MD5 checked: {args.verify_md5}')
        return 0
    except (OSError, ValueError, UnicodeError) as error:
        print(f'FAILED: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
