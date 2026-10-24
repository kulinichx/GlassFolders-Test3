#!/usr/bin/env python3
"""Run v8 unit tests without modifying the user's Python installation.

If NumPy/Pillow are missing, bootstrap a *temporary* virtual environment
and install the binary wheels there. The temporary environment is removed
when tests finish, including on failure. No repository files are changed.
"""
from __future__ import annotations

import importlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import venv

ROOT = Path(__file__).resolve().parents[1]
REQUIREMENTS = ('numpy>=2.3.4,<3', 'pillow>=12,<13')


def dependencies_available() -> bool:
    for module in ('numpy', 'PIL'):
        try:
            importlib.import_module(module)
        except (ImportError, OSError) as error:
            print(f"TEST DEPENDENCY MISSING/BROKEN: {module}: {error}", flush=True)
            return False
    return True


def run_tests(python: Path | str) -> int:
    command = [str(python), '-m', 'unittest', 'discover', '-s', str(ROOT / 'tests'), '-p', 'test_*.py', '-v']
    print('Running:', ' '.join(command), flush=True)
    return subprocess.call(command, cwd=ROOT)


def main() -> int:
    print(f'Using Python: {sys.executable} ({sys.version_info.major}.{sys.version_info.minor})', flush=True)
    if sys.version_info < (3, 11):
        print('STOP: Please use Python 3.11–3.14 for this test launcher.', file=sys.stderr)
        return 2
    if dependencies_available():
        return run_tests(sys.executable)
    if os.environ.get('GF_TEST_SETUP', '').lower() == 'never':
        print('STOP: Test dependencies are missing. To install in this Python environment, run:',
              file=sys.stderr)
        print('  python3 -m pip install "numpy>=2.3.4,<3" "pillow>=12,<13"', file=sys.stderr)
        print('Or unset GF_TEST_SETUP and retry: the script uses a temporary, isolated venv.',
              file=sys.stderr)
        return 4
    print('Creating disposable isolated Python environment (may download binary wheels).', flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='gf-refraction-tests-') as directory:
            env_dir = Path(directory) / 'venv'
            venv.EnvBuilder(with_pip=True).create(env_dir)
            python = env_dir / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
            print('Installing NumPy/Pillow in temporary environment only…', flush=True)
            command = [str(python), '-m', 'pip', '--disable-pip-version-check', 'install',
                       '--only-binary=:all:', *REQUIREMENTS]
            if subprocess.call(command) != 0:
                print('STOP: Could not install binary test dependencies (check network/Python version).',
                      file=sys.stderr)
                return 5
            return run_tests(python)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f'STOP: Could not create/use temporary test environment: {exc}', file=sys.stderr)
        return 5


if __name__ == '__main__':
    raise SystemExit(main())
