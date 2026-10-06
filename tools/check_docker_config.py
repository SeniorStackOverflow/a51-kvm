#!/usr/bin/env python3
"""Verify built-in Docker requirements and the A51 KVM pairing in a full config."""
import argparse
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def check(path):
    config = set(path.read_text().splitlines())
    features = json.loads((ROOT / 'kernel/docker.features.json').read_text())
    missing = [name for name in features if f'CONFIG_{name}=y' not in config]
    if '# CONFIG_UH_RKP is not set' not in config:
        missing.append('UH_RKP must remain disabled')
    if missing:
        raise ValueError('Missing built-in requirements: ' + ', '.join(missing))
    print(f'PASS: {len(features)} Docker/KVM requirements built in; native UH RKP configuration preserved')
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path, nargs='?', default=ROOT / 'kernel/docker.config')
    args = parser.parse_args()
    try:
        check(args.config)
    except (OSError, ValueError) as error:
        parser.exit(1, f'ERROR: {error}\n')
