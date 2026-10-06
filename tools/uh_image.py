#!/usr/bin/env python3
"""Prepare local UH images for the one audited firmware. Never flashes a device."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import tarfile

ORIGINAL_SHA = 'ebdf765c5087cd1953b2e4a11878a65611b2705618c0a31ed05b1419c4571574'
CANONICAL_SHA = '9006b493765b1c57214e5b1f9370066a7e86ca2f620961c53f030edb230b922f'
PATCHED_SHA = 'd05d6cdfc282c953d3b048c42fdc77279c2f996a2ed76e36c87fd4c9ff21273a'
PARTITION_SIZE = 2097152
CANONICAL_SIZE = 284056
MARKER = b'KVMEL2HAND_V1\0\0\0'

def require(condition, message):
    if not condition:
        raise ValueError(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def normalize_original(data):
    require(len(data) in [CANONICAL_SIZE, PARTITION_SIZE], 'Expected canonical signed UH or full 2 MiB partition')
    data = data.ljust(PARTITION_SIZE, b'\0')
    require(sha(data) == ORIGINAL_SHA, 'UH hash mismatch: only the audited A515FXXU5EUJ4 image is supported')
    require(not any(data[CANONICAL_SIZE:]), 'Reserved partition tail is nonzero')
    require(4096 + struct.unpack_from('<I', data, 8)[0] + 0x210 == CANONICAL_SIZE, 'Unexpected signed container size')
    return data

def offset(pa):
    return 4096 + pa - 0x87000000

def branch(pa, target, link=False):
    distance = target - pa
    require(distance % 4 == 0 and -(1 << 27) <= distance < (1 << 27), 'Branch out of range or unaligned')
    return struct.pack('<I', (0x94000000 if link else 0x14000000) | ((distance // 4) & 0x3ffffff))

def branch_target(word, pa):
    require(word & 0xfc000000 == 0x14000000, 'Expected an unconditional B instruction')
    immediate = word & 0x3ffffff
    if immediate & (1 << 25):
        immediate -= 1 << 26
    return pa + immediate * 4

def check_gateway(build):
    gateway = (build / 'gateway.bin').read_bytes()
    tested = (build / 'test-gateway.bin').read_bytes()
    require(len(gateway) == len(tested) == 1132, 'Unexpected gateway size')
    differences = []
    for i in range(0, len(gateway), 4):
        a, b = gateway[i:i+4], tested[i:i+4]
        if a != b:
            target = branch_target(struct.unpack('<I', a)[0], 0x8701b190 + i)
            require(0x8701c784 <= target <= 0x8701d3b4, 'Only native fallback branch relocations may differ')
            branch_target(struct.unpack('<I', b)[0], 0x8701b190 + i)
            differences.append(i)
    require(len(differences) == 16, 'Expected exactly 16 synthetic native fallback relocations')
    require((build / 'handoff-result.txt').read_text().startswith('PASS:'), 'Run make test successfully before packing')
    require((build / 'publisher.bin').stat().st_size == 44, 'Unexpected publisher size')
    require((build / 'marker.bin').read_bytes() == MARKER, 'Wrong handoff marker')
    return gateway

def pack(data, build):
    original = normalize_original(data)
    gateway = check_gateway(build)
    symbols = {}
    for line in (build / 'symbols.txt').read_text().splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2].startswith('uh_slot_'):
            symbols[fields[2]] = int(fields[0], 16)
    require(len(symbols) == 16, 'Missing vector entry symbols')
    patches = [(0x8701b190, gateway), (0x8701b700, (build / 'publisher.bin').read_bytes()), (0x8701b780, MARKER)]
    for pa, code in patches:
        require(original[offset(pa):offset(pa)+len(code)] == struct.pack('<I', 0xd503201f) * (len(code)//4), 'Target padding is not NOPs')
    for slot in range(16):
        pa = 0x8701c000 + 128 * slot
        branch_target(struct.unpack_from('<I', original, offset(pa))[0], pa)
        patches.append((pa, branch(pa, symbols[f'uh_slot_{slot}'])))
    require(original[offset(0x870010a8):offset(0x870010ac)] == branch(0x870010a8, 0x870129c0, True), 'Native init call changed')
    patches.append((0x870010a8, branch(0x870010a8, 0x8701b700, True)))
    image = bytearray(original)
    for pa, code in patches:
        image[offset(pa):offset(pa)+len(code)] = code
    require(image[:0x2000] == original[:0x2000], 'Container header / ELF prefix changed')
    payload_end = 4096 + struct.unpack_from('<I', original, 8)[0]
    require(image[payload_end:] == original[payload_end:], 'Signature footer / reserved tail changed')
    require(image[offset(0x870129c0):offset(0x870129c0)+4096] == original[offset(0x870129c0):offset(0x870129c0)+4096], 'Native init changed')
    require(sha(image) == PATCHED_SHA, 'Patched image differs from the hardware-tested artifact')
    return bytes(image)

def write_new(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as handle:
        handle.write(data)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    check = sub.add_parser('check-gateway')
    check.add_argument('--build', type=Path, default=Path('build'))
    for name in ['pack', 'rollback']:
        command = sub.add_parser(name)
        command.add_argument('original', type=Path)
        command.add_argument('--out', type=Path, required=True)
        if name == 'pack':
            command.add_argument('--build', type=Path, default=Path('build'))
    args = parser.parse_args()
    try:
        if args.command == 'check-gateway':
            check_gateway(args.build)
            print('PASS: real/test gateways differ only in 16 native fallback B relocations')
            return
        original = normalize_original(args.original.read_bytes())
        if args.command == 'pack':
            data = pack(original, args.build)
        else:
            canonical = original[:CANONICAL_SIZE]
            require(sha(canonical) == CANONICAL_SHA, 'Canonical signed UH checksum mismatch')
            if args.out.suffix == '.tar':
                stream = io.BytesIO()
                with tarfile.open(fileobj=stream, mode='w', format=tarfile.USTAR_FORMAT) as tar:
                    member = tarfile.TarInfo('uh.bin')
                    member.size = len(canonical)
                    member.mode = 0o644
                    tar.addfile(member, io.BytesIO(canonical))
                data = stream.getvalue()
            else:
                data = canonical
        write_new(args.out, data)
        print(json.dumps({'file': str(args.out), 'bytes': len(data), 'sha256': sha(data)}, indent=2))
    except (OSError, ValueError) as error:
        parser.exit(1, f'ERROR: {error}\n')

if __name__ == '__main__':
    main()
