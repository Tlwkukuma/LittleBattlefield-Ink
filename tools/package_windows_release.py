#!/usr/bin/env python3
"""Cross-platform Windows release export/packaging, using Python's standard library.

Default is preflight only. --export must be explicitly supplied to export a game.
No downloads, installation, gameplay, firewall changes or old-output removal.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import uuid
import zipfile

import validate_delivery
import inspect_release_pck

ENGINE_VERSION = '4.6.3.stable'
WINDOWS_RELEASE = 'windows_release_x86_64.exe'
NOTICE_FILES = ('GODOT_LICENSE.txt', 'GODOT_COPYRIGHT.txt')
RELEASE_DOCS = {
    'docs/historical-five-levels.md': '资料/historical-five-levels.md',
    'docs/pixi-fidelity-matrix.md': '资料/pixi-fidelity-matrix.md',
    'docs/ten-level-source-runtime.md': '资料/ten-level-source-runtime.md',
    'docs/combat-ai-iteration-20261009.md': '资料/combat-ai-iteration-20261009.md',
}


def sha256(path: Path) -> str:
    return validate_delivery.digest(path)


def normalize_endpoint(value: str) -> str:
    value = value.strip()
    if not value:
        return ''
    match = re.fullmatch(r'(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?', value)
    if not match:
        raise ValueError('Host address must be IPv4, optionally followed by :port')
    address = str(ipaddress.IPv4Address(match[1]))
    if match[2]:
        port = int(match[2])
        if not 1 <= port <= 65535:
            raise ValueError('Host port must be 1..65535')
        return f'{address}:{port}'
    return address


def check_windows_binary(path: Path) -> None:
    with path.open('rb') as stream:
        header = stream.read(64)
        if len(header) != 64 or header[:2] != b'MZ':
            raise ValueError(f'Not a Windows executable: {path.name}')
        offset = struct.unpack_from('<I', header, 60)[0]
        if offset > path.stat().st_size - 26:
            raise ValueError(f'Invalid Windows executable header: {path.name}')
        stream.seek(offset)
        pe = stream.read(26)
    if pe[:4] != b'PE\0\0' or struct.unpack_from('<H', pe, 4)[0] != 0x8664:
        raise ValueError(f'Expected x86-64 Windows executable: {path.name}')
    if struct.unpack_from('<H', pe, 24)[0] != 0x20B:
        raise ValueError(f'Expected PE32+ executable: {path.name}')


def check_pck(path: Path) -> None:
    with path.open('rb') as stream:
        if stream.read(4) != b'GDPC':
            raise ValueError(f'Invalid Godot PCK header: {path.name}')
    if path.stat().st_size < 100:
        raise ValueError(f'Truncated Godot PCK: {path.name}')


def safe_environment(data_home: Path) -> dict:
    env = dict(os.environ)
    # All new editor/cache/user files stay in this task's toolchain directory.
    env['XDG_DATA_HOME'] = str(data_home)
    env['XDG_CACHE_HOME'] = str(data_home.parent / 'cache')
    env['XDG_CONFIG_HOME'] = str(data_home.parent / 'config')
    if os.name == 'nt':
        env['APPDATA'] = str(data_home)
        env['LOCALAPPDATA'] = str(data_home.parent / 'cache')
    for key in ('XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME'):
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    return env


def preflight(root: Path, engine: str, data_home: Path, receipt: Path | None) -> tuple[str, str]:
    source = (root / 'scripts/proving_ground.gd').read_text(encoding='utf-8-sig')
    match = validate_delivery.VERSION_RE.search(source)
    if not match or not re.fullmatch(r'[A-Za-z0-9._-]+', match[1]):
        raise ValueError('Missing or unsafe BUILD_VERSION')
    result = subprocess.run([engine, '--version'], check=True, text=True, capture_output=True,
                            env=safe_environment(data_home), timeout=30)
    version = result.stdout.strip()
    if not version.startswith(ENGINE_VERSION + '.') and version != ENGINE_VERSION:
        raise ValueError(f'Expected {ENGINE_VERSION}, found {version}')
    template_dir = data_home / 'godot/export_templates' / ENGINE_VERSION
    check_windows_binary(template_dir / WINDOWS_RELEASE)
    if (template_dir / 'version.txt').read_text().strip() != ENGINE_VERSION:
        raise ValueError('Export template version.txt does not match the engine')
    if receipt:
        record = json.loads(receipt.read_text())
        if record.get('engine_version') != ENGINE_VERSION or not record.get('vendor_checksums_verified'):
            raise ValueError('Template receipt lacks matching version/vendor checksum verification')
        entries = {item['name']: item for item in record['extracted_files']}
        if WINDOWS_RELEASE not in entries:
            raise ValueError('Template receipt does not include the Windows release template')
        for name, entry in entries.items():
            if Path(name).name != name:
                raise ValueError('Unsafe template receipt filename')
            template = template_dir / name
            if sha256(template) != entry['sha256']:
                raise ValueError(f'Template hash changed: {name}')
    for name in NOTICE_FILES:
        if not (root / 'tools/lan-release' / name).is_file():
            raise ValueError(f'Missing engine license notice: {name}')
    for name in RELEASE_DOCS:
        if not (root / name).is_file():
            raise ValueError(f'Missing selected release document: {name}')
    return match[1], version


def verify_package(package_root: Path, archive_path: Path) -> dict:
    expected = {}
    for line in (package_root / 'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines():
        checksum, name = line.split('  ', 1)
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts or name in expected:
            raise ValueError('Unsafe or duplicate checksum entry')
        expected[name] = checksum
        if sha256(package_root / relative) != checksum:
            raise ValueError(f'Package file hash mismatch: {name}')
    actual = {path.relative_to(package_root).as_posix() for path in package_root.rglob('*') if path.is_file()}
    if actual != set(expected) | {'SHA256SUMS.txt'}:
        raise ValueError('Package has missing or unrecorded files')
    with zipfile.ZipFile(archive_path) as archive:
        wanted = {f'{package_root.name}/{name}' for name in actual}
        if len(archive.namelist()) != len(wanted) or set(archive.namelist()) != wanted:
            raise ValueError('ZIP file inventory differs from the package folder')
        for name in actual:
            digest = hashlib.sha256()
            with archive.open(f'{package_root.name}/{name}') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            if digest.hexdigest() != sha256(package_root / name):
                raise ValueError(f'ZIP content mismatch: {name}')
    return {'files': len(actual), 'zip_bytes': archive_path.stat().st_size, 'zip_sha256': sha256(archive_path)}


def assemble(root: Path, runtime_dir: Path, output_dir: Path, version: str,
             engine_version: str, host_address: str = '', source_manifest: dict | None = None,
             receipt: Path | None = None) -> tuple[Path, dict]:
    if not re.fullmatch(r'[A-Za-z0-9._-]+', version):
        raise ValueError('Unsafe version')
    host_address = normalize_endpoint(host_address)
    check_windows_binary(runtime_dir / 'LittleBattlefield.exe')
    check_pck(runtime_dir / 'LittleBattlefield.pck')
    identity = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '-' + uuid.uuid4().hex[:8]
    package_name = f'LittleBattlefield-LAN-v{version}-Windows'
    run_root = output_dir / f'{package_name}-{identity}'
    package_root = run_root / package_name
    package_root.mkdir(parents=True, exist_ok=False)
    # Only runtime binary formats enter from the export directory. An old host preset
    # or launcher never comes from here, even if the export directory unexpectedly contains unrelated files.
    for path in sorted(runtime_dir.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'Symlink in export output: {path.name}')
        if path.is_file() and path.suffix.lower() in {'.exe', '.dll', '.pck'}:
            target = package_root / path.relative_to(runtime_dir)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    for path in sorted((root / 'tools/lan-release').iterdir()):
        if path.is_symlink():
            raise ValueError(f'Symlink in launcher source: {path.name}')
        if path.is_file():
            if path.name.lower() == 'host-address.txt':
                raise ValueError('Remove a local host preset from launcher sources before packaging')
            target = package_root / path.name
            if target.exists():
                raise ValueError(f'Launcher collides with exported binary: {path.name}')
            shutil.copy2(path, target)
    for name in NOTICE_FILES:
        if not (package_root / name).is_file():
            raise ValueError(f'Missing engine license notice: {name}')
    for source, destination in RELEASE_DOCS.items():
        source_path = root / source
        if source_path.is_symlink():
            raise ValueError(f'Symlink in release documentation: {source}')
        target = package_root / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, target)
    audio = root / 'assets/audio/free-firearms'
    shutil.copy2(audio / 'LICENSE.md', package_root / 'FREE_FIREARM_AUDIO_LICENSE.md')
    shutil.copy2(audio / 'ADDITIONAL_LICENSES.md', package_root / 'ADDITIONAL_AUDIO_LICENSES.md')
    (package_root / 'VERSION.txt').write_text(version + '\n', encoding='ascii')
    (package_root / 'ENGINE_VERSION.txt').write_text(engine_version + '\n', encoding='ascii')
    if host_address:
        (package_root / 'host-address.txt').write_text(host_address + '\n', encoding='ascii')
    if source_manifest:
        (package_root / 'SOURCE_MANIFEST.json').write_text(json.dumps(source_manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if receipt:
        shutil.copy2(receipt, package_root / 'TEMPLATE_RECEIPT.json')
    files = sorted(path for path in package_root.rglob('*') if path.is_file())
    hashes = [f'{sha256(path)}  {path.relative_to(package_root).as_posix()}' for path in files]
    (package_root / 'SHA256SUMS.txt').write_text('\n'.join(hashes) + '\n', encoding='utf-8')
    archive_path = output_dir / (run_root.name + '.zip')
    with zipfile.ZipFile(archive_path, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(package_root.rglob('*')):
            if path.is_file():
                archive.write(path, arcname=f'{package_name}/{path.relative_to(package_root).as_posix()}')
    result = verify_package(package_root, archive_path)
    archive_path.with_suffix('.zip.sha256').write_text(f"{result['zip_sha256']}  {archive_path.name}\n", encoding='ascii')
    return archive_path, result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--godot', default=os.environ.get('GODOT_EXE', 'godot'))
    parser.add_argument('--data-home', type=Path, help='Task-scoped XDG data home containing godot/export_templates/4.6.3.stable')
    parser.add_argument('--receipt', type=Path, help='Verified template acquisition receipt')
    parser.add_argument('--host-address', default='')
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--export', action='store_true', help='Explicitly export and package; otherwise preflight only')
    args = parser.parse_args()
    root = args.root.resolve()
    data_home = (args.data_home or root.parent / 'toolchain/share').resolve()
    receipt = args.receipt
    default_receipt = data_home.parent / 'receipts/template-receipt.json'
    if receipt is None and default_receipt.is_file():
        receipt = default_receipt
    try:
        output_dir = (args.output_dir or root / 'exports').resolve()
        if output_dir.is_relative_to(root) and validate_delivery.included(output_dir.relative_to(root)):
            raise ValueError('Output directory must be outside source inventory, e.g. exports/ or outside the project')
        endpoint = normalize_endpoint(args.host_address)
        version, engine_version = preflight(root, args.godot, data_home, receipt)
        print(f'Preflight PASS: game v{version}, Godot {engine_version}, Windows x86-64 template')
        if not args.export:
            print('No game export performed. Supply --export after source integration is approved.')
            return 0
        manifest, errors = validate_delivery.inspect(root)
        if manifest['project_version'] != version:
            errors.append('BUILD_VERSION changed during preflight; rerun after integration')
        if errors:
            raise ValueError('Source delivery validation failed:\n' + '\n'.join(errors))
        if args.export:
            build = root / 'build' / ('windows-' + uuid.uuid4().hex)
            build.mkdir(parents=True, exist_ok=False)
            logfile = build / 'export.log'
            with logfile.open('w', encoding='utf-8') as output:
                result = subprocess.run([args.godot, '--headless', '--path', str(root), '--export-release',
                                         'Windows Release', str(build / 'LittleBattlefield.exe')],
                                        env=safe_environment(data_home), stdout=output, stderr=subprocess.STDOUT,
                                        timeout=1800)
            log = logfile.read_text(encoding='utf-8', errors='replace')
            if result.returncode or re.search(r'^\s*(?:SCRIPT ERROR|SHADER ERROR|ERROR):', log, re.MULTILINE):
                raise ValueError(f'Godot export failed; inspect {logfile}')
        pck_report = inspect_release_pck.read_inventory(build / 'LittleBattlefield.pck', verify_md5=True)
        pck_errors = inspect_release_pck.check_release(pck_report)
        if pck_errors:
            raise ValueError('PCK inventory validation failed:\n' + '\n'.join(pck_errors))
        (build / 'pck-inventory.json').write_text(json.dumps(pck_report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        after, errors = validate_delivery.inspect(root)
        errors += validate_delivery.verify_manifest(after, manifest)
        if errors:
            raise ValueError('Source changed during export; do not ship this mixed build:\n' + '\n'.join(errors))
        path, result = assemble(root, build, output_dir, version,
                                engine_version, endpoint, manifest, receipt)
        print(f'Package verified: {path}\n{json.dumps(result)}')
        print('Archive/binary integrity passed; this does not certify gameplay or Windows runtime testing.')
        return 0
    except (OSError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        print(f'FAILED: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
