"""Prepare selected bridges on an existing local host without linking accounts.

Requires the existing maintainer Python environment (PyYAML). Fresh installations
and the native onboarding flow use setup-messages.sh and need Docker only.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / 'infra/matrix/compose.yml'
PRIVATE = COMPOSE.parent / 'private'
SERVICES = {'whatsapp': 29318, 'telegram': 29317, 'discord': 29334,
            'signal': 29328, 'slack': 29335, 'gmessages': 29336, 'meta': 29319, 'instagram': 29320}

def run(*args):
    return subprocess.run(['docker', 'compose', '-f', str(COMPOSE), '--profile', 'bridges', *args],
                          capture_output=True, text=True, timeout=600)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--services', nargs='+', choices=SERVICES, default=list(SERVICES))
    names = parser.parse_args().services
    if not (PRIVATE / 'synapse/homeserver.yaml').exists():
        raise RuntimeError('No initialized local host. Use scripts/setup-messages.sh for a fresh host.')
    source = ROOT / 'apple/RelayKit/Sources/RelayKit/Resources/MessageHost/configure.py'
    spec = importlib.util.spec_from_file_location('relay_bridge_config', source)
    config = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(config)
    config.PRIVATE = PRIVATE
    config.PORTS = SERVICES
    os.umask(0o077)
    for name in names:
        folder = PRIVATE / name
        folder.mkdir(parents=True, exist_ok=True)
        if not (folder / 'config.yaml').exists():
            result = run('run', '--rm', '--no-deps', name)
            if not (folder / 'config.yaml').exists():
                raise RuntimeError(f'{name}: configuration generation failed (exit {result.returncode})')
        config.bridge(name)
        if not (folder / 'registration.yaml').exists():
            result = run('run', '--rm', '--no-deps', name)
            if not (folder / 'registration.yaml').exists():
                raise RuntimeError(f'{name}: registration generation failed (exit {result.returncode})')
        config.registration(name)
        print(f'{name}: configured; account linking is pending')
    print('Restart Synapse and start the selected bridges to load registrations. No accounts linked.')

if __name__ == '__main__':
    main()
