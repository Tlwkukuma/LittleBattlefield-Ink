#!/usr/bin/env python3
"""Read-only source/resource checks and SHA-256 manifests; never launches Godot.

Generate a manifest outside the project (or in build/) once integration is quiet:
  python tools/validate_delivery.py --manifest ../source-manifest.json
Verify an unpacked source tree:
  python tools/validate_delivery.py --verify ../source-manifest.json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

GENERATED_DIRS = {'.godot', '.git', '__pycache__'}
GENERATED_ROOTS = {'build', 'exports'}
REQUIRED = (
    'project.godot', 'export_presets.cfg', 'proving_ground.tscn',
    'scripts/proving_ground.gd', 'scripts/source_catalog.gd',
    'tools/package_lan_release.ps1', 'tools/lan-release/使用说明.txt',
    'tools/package_windows_release.py', 'tools/lan-release/GODOT_LICENSE.txt',
    'tools/lan-release/GODOT_COPYRIGHT.txt',
    'assets/audio/free-firearms/LICENSE.md',
    'assets/audio/free-firearms/ADDITIONAL_LICENSES.md',
    'README.md', 'AGENTS.md',
)
RESOURCE_RE = re.compile(r'''(?:preload|load)\(\s*["'](res://[^"']+)["']\s*\)|\bpath="(res://[^"\n]+)"''')
VERSION_RE = re.compile(r'const\s+BUILD_VERSION\s*(?::\s*String)?\s*=\s*"([^"]+)"')


def included(relative: Path) -> bool:
    parts = relative.parts
    return bool(parts) and parts[0] not in GENERATED_ROOTS and not any(
        part in GENERATED_DIRS for part in parts
    ) and relative.suffix.lower() not in {'.log', '.pyc', '.pyo'} and not (
        relative.name == '.env' or (relative.name.startswith('.env.') and relative.name != '.env.example')
    )


def source_files(root: Path):
    # Do not traverse .godot, including during a concurrent importer run.
    import os
    for directory, dirs, files in os.walk(root, followlinks=False):
        base = Path(directory)
        dirs[:] = sorted(d for d in dirs if included((base / d).relative_to(root)))
        for name in sorted(files):
            path = base / name
            if included(path.relative_to(root)):
                yield path


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def reject_nonfinite(value):
    raise ValueError(f'Non-standard JSON numeric constant: {value}')


def inspect(root: Path):
    errors, records = [], []
    for name in REQUIRED:
        if not (root / name).is_file():
            errors.append(f'Missing required file: {name}')
    version_path = root / 'scripts/proving_ground.gd'
    version_match = VERSION_RE.search(version_path.read_text(encoding='utf-8-sig')) if version_path.is_file() else None
    version = version_match.group(1) if version_match else None
    if not version:
        errors.append('Missing BUILD_VERSION')
    json_count = 0
    for path in sorted(source_files(root)):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            errors.append(f'Symlink requires explicit packaging review: {relative}')
            continue
        before = path.stat()
        checksum = digest(path)
        after = path.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            errors.append(f'File changed during manifest generation; rerun after integration: {relative}')
        records.append({'path': relative, 'bytes': after.st_size, 'sha256': checksum})
        # Imported original and auxiliary references can contain tool-specific formats;
        # validate JSON everywhere but only resolve literal runtime resource paths.
        if path.suffix == '.json':
            try:
                json.loads(path.read_text(encoding='utf-8-sig'), parse_constant=reject_nonfinite)
                json_count += 1
            except (ValueError, UnicodeError) as exc:
                errors.append(f'Invalid JSON {relative}: {exc}')
        if (path.suffix == '.gd' and relative.startswith('scripts/')) or (
            path.suffix in {'.tscn', '.tres'} and not relative.startswith('qa/')
        ):
            pattern = re.compile(r'''\b(?:preload|load)\(\s*["'](res://[^"']+)["']\s*\)''') if path.suffix == '.gd' else RESOURCE_RE
            for match in pattern.finditer(path.read_text(encoding='utf-8-sig')):
                resource = next(value for value in match.groups() if value)
                target = root / resource.removeprefix('res://')
                if not target.resolve().is_relative_to(root.resolve()) or not target.is_file():
                    errors.append(f'Missing literal resource in {relative}: {resource}')
    report = {
        'schema_version': 1, 'project_version': version,
        'scope': 'Source delivery inventory; excludes caches, builds, exports, logs and local secrets. Not a gameplay or license-rights certification.',
        'json_files_validated': json_count,
        'file_count': len(records), 'total_bytes': sum(item['bytes'] for item in records),
        'files': records,
    }
    return report, errors


def verify_manifest(report, expected):
    errors = []
    if expected.get('schema_version') != 1:
        return ['Unsupported manifest schema_version']
    actual = {item['path']: item for item in report['files']}
    wanted = {item['path']: item for item in expected['files']}
    for name in sorted(wanted.keys() - actual.keys()):
        errors.append(f'Missing manifest file: {name}')
    for name in sorted(actual.keys() - wanted.keys()):
        errors.append(f'Unexpected source file: {name}')
    for name in sorted(actual.keys() & wanted.keys()):
        if actual[name] != wanted[name]:
            errors.append(f'Changed source file: {name}')
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--manifest', type=Path, help='Write source manifest; prefer a path outside the project')
    parser.add_argument('--verify', type=Path, help='Compare all source files with an existing manifest')
    args = parser.parse_args()
    root = args.root.resolve()
    if args.manifest:
        output = args.manifest.resolve()
        if output.is_relative_to(root) and included(output.relative_to(root)):
            parser.error('--manifest must be outside the source inventory (outside project or under build/)')
    report, errors = inspect(root)
    if args.verify:
        errors.extend(verify_manifest(report, json.loads(args.verify.read_text(encoding='utf-8-sig'))))
    for error in errors:
        print(f'ERROR: {error}')
    if errors:
        print(f'FAILED: {len(errors)} issue(s); no manifest written')
        return 1
    if args.manifest:
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"PASS: v{report['project_version']}; {report['file_count']} source files, {report['json_files_validated']} JSON files, {report['total_bytes']} bytes")
    print('Static delivery checks only; gameplay, export execution and third-party rights are not verified by this command.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
