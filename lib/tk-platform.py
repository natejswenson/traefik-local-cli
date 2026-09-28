#!/usr/bin/env python3
"""Verify a selected local-k8s package before forwarding structured commands."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys

CONTRACT = 'schemas/frontend-package-v1.json'
ENTRIES = {'dev': 'tk-dev.py', 'kube': 'tk-kube.py', 'app': 'tk-app.py',
           'service': 'tk-platform.py', 'agent': 'tk-platform.py', 'platform': 'tk-platform.py'}


class PackageError(ValueError):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def regular(path):
    """Refuse links at every path component before opening installed code."""
    if not path.is_absolute():
        raise PackageError('platform_package_unavailable', 'Selected release path must be absolute')
    for component in (path, *path.parents):
        if component.is_symlink():
            raise PackageError('platform_package_unavailable', 'Selected release contains a linked path')
    if not path.is_file():
        raise PackageError('platform_package_unavailable', 'Selected release file is missing')


def sha256(path):
    regular(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()


def selected_entry(selector, name):
    regular(selector)
    selected = json.loads(selector.read_text())
    if type(selected) is not dict or type(selected.get('schema_version')) is not int or selected['schema_version'] != 1:
        raise PackageError('platform_package_unavailable', 'Unsupported platform selector')
    root = Path(selected['root']).expanduser()
    if not root.is_absolute():
        raise PackageError('platform_package_unavailable', 'Selected release root must be absolute')
    for component in (root, *root.parents):
        if component.is_symlink():
            raise PackageError('platform_package_unavailable', 'Selected release contains a linked path')
    release_path = root / 'release.json'
    regular(release_path)
    release = json.loads(release_path.read_text())
    if type(release) is not dict or type(release.get('schema_version')) is not int or release['schema_version'] != 1:
        raise PackageError('platform_package_unavailable', 'Unsupported release metadata')
    files = release.get('files')
    if type(files) is not dict or not files or any(type(k) is not str or type(v) is not str or not re.fullmatch('[0-9a-f]{64}', v) for k, v in files.items()):
        raise PackageError('platform_package_unavailable', 'Malformed release inventory')
    inventory_sha = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    if (type(release.get('version')) is not str or type(selected.get('version')) is not str
            or inventory_sha != release.get('sha256') or inventory_sha != selected.get('sha256')
            or release.get('version') != selected.get('version')):
        raise PackageError('platform_package_unavailable', 'Selected release identity differs')
    entry_name = 'src/' + ENTRIES[name]
    if entry_name not in files or sha256(root / entry_name) != files[entry_name]:
        raise PackageError('platform_package_unavailable', 'Selected command differs from release inventory')
    if CONTRACT in files:
        if sha256(root / CONTRACT) != files[CONTRACT]:
            raise PackageError('platform_package_unavailable', 'Frontend contract differs from release inventory')
        contract = json.loads((root / CONTRACT).read_text())
        version = (contract.get('frontend_protocol_version') if type(contract) is dict
                   and type(contract.get('schema_version')) is int and contract['schema_version'] == 1 else None)
    elif release.get('version') == '0.2.1':
        version = 1  # Known legacy package predates the in-package contract.
    else:
        version = None
    if type(version) is not int or version < 1:
        raise PackageError('platform_package_unavailable', 'Malformed or missing frontend protocol version')
    if version > 1:
        raise PackageError('platform_protocol_incompatible',
                           'Selected local-k8s release needs a newer tk frontend')
    return root / entry_name


def main():
    try:
        command = sys.argv[1:]
        group = command[0] if command else ''
        if group not in ENTRIES:
            raise PackageError('platform_package_unavailable', 'Unsupported platform command')
        override = os.environ.get('TK_PLATFORM_ROOT')
        if override:
            entry = Path(override).expanduser().resolve() / 'src' / ENTRIES[group]
            if not entry.is_file():
                raise PackageError('platform_package_unavailable', 'Development source entry is missing')
        else:
            selector = Path(os.environ.get('TK_PLATFORM_CONFIG', Path.home() / '.config/tk/platform.json')).expanduser()
            entry = selected_entry(selector, group)
        os.execv(sys.executable, [sys.executable, str(entry), *command])
    except (OSError, ValueError, KeyError, TypeError) as exc:
        code = exc.code if isinstance(exc, PackageError) else 'platform_package_unavailable'
        message = str(exc) if isinstance(exc, PackageError) else 'Selected platform release is malformed or unavailable'
        print(json.dumps({'schema_version': 1, 'ok': False, 'error': {'code': code, 'message': message,
            'next_action': 'Inspect ~/.config/tk/platform.json and install a compatible local-k8s package'}}))
        return 30


if __name__ == '__main__':
    raise SystemExit(main())
