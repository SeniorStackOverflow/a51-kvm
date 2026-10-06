#!/usr/bin/env python3
"""Fetch the pinned Samsung kernel base, normalize patch targets and apply our patch."""
import argparse
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[1]
BASE = (REPO / 'kernel/base-commit.txt').read_text().strip()
ORIGIN = 'https://github.com/UtsavBalar1231/kernel_samsung_universal9611.git'

def run(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path, help='A new directory, outside this repository or under build/')
    parser.add_argument('--profile', choices=['kvm', 'docker'], default='kvm')
    args = parser.parse_args()
    target = args.destination.resolve()
    if target.exists():
        parser.error('Destination already exists; choose a fresh directory')
    target.mkdir(parents=True)
    run('git', 'init', str(target))
    run('git', 'remote', 'add', 'origin', ORIGIN, cwd=target)
    run('git', 'fetch', '--depth=1', 'origin', BASE, cwd=target)
    run('git', '-c', 'core.autocrlf=false', 'checkout', '--detach', BASE, cwd=target)
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=target).decode().strip()
    if actual != BASE:
        raise RuntimeError('Unexpected kernel base')
    patches = [REPO / 'kernel/a51-kvm.patch']
    if args.profile == 'docker':
        patches.append(REPO / 'kernel/docker-cpuset.patch')
    # Some stock files use CRLF. The published diff omits pure newline changes.
    for patch in patches:
        for line in patch.read_text().splitlines():
            if line.startswith('diff --git '):
                name = line.split(' b/', 1)[1]
                path = target / name
                if path.is_file():
                    path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
        run('git', 'apply', '--check', str(patch), cwd=target)
        run('git', 'apply', str(patch), cwd=target)
    print(f'Prepared pinned kernel {BASE} at {target}')

if __name__ == '__main__':
    main()
