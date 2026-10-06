#!/usr/bin/env python3
"""Replace only an uncompressed kernel in the audited Android boot-v2 layout."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

def require(condition, message):
    if not condition:
        raise ValueError(message)

def parse(data):
    require(len(data) >= 1660 and data[:8] == b'ANDROID!', 'Not an Android boot image')
    kernel, ka, ramdisk, ra, second, sa, tags, page, version, osv = struct.unpack_from('<10I', data, 8)
    require(version == 2 and page == 2048, 'Only the tested boot-v2 / 2048-byte-page layout is supported')
    dtbo_size, dtbo_off, header_size, dtb_size, dtb_addr = struct.unpack_from('<IQIIQ', data, 1632)
    require(header_size == 1660 and dtbo_size == 0 and second == 0, 'Unexpected boot layout')
    align = lambda n: (n + page - 1) // page * page
    ramdisk_off = page + align(kernel)
    dtb_off = ramdisk_off + align(ramdisk)
    tail = dtb_off + align(dtb_size)
    require(0 < kernel and 0 < ramdisk and 0 < dtb_size and tail + 64 <= len(data), 'Invalid boot section lengths')
    require(data[tail:tail+16].startswith(b'SEANDROIDENFORCE') and not any(data[tail+64:]), 'Unexpected footer / nonzero partition tail')
    require(data[page:page+4] != b'\x1f\x8b\x08\x00', 'Input kernel must be uncompressed, as on the tested handset')
    return {'page': page, 'kernel': data[page:page+kernel], 'ramdisk': data[ramdisk_off:ramdisk_off+ramdisk], 'dtb': data[dtb_off:dtb_off+dtb_size], 'footer': data[tail:tail+64], 'tail': tail}

def replace(original, image, system_map):
    parts = parse(original)
    require(len(original) == 61865984, 'Expected the audited 61,865,984-byte boot partition dump')
    require(hashlib.sha256(parts['dtb']).hexdigest() == 'd46b80ec339e009b66c1adc7b12622e8b108eda5673ba663995103b75e62a973', 'Original boot DTB does not match the audited firmware')
    require(len(image) > 64 and image[56:60] == b'ARM\x64', 'Not an uncompressed arm64 Image')
    require(b'A51 UH handoff gateway detected' in image and b'KVMEL2HAND_V1' in image, 'Handoff kernel markers missing')
    banner = re.search(rb'Linux version [^\x00]+', image)
    require(banner is not None and re.match(rb'Linux version 4\.14\.113-22755563(?:-docker)? ', banner.group()) and b'clang version 6.0.1' in banner.group(), 'Unexpected kernel version / toolchain')
    names = ['__kvm_exynos_hyp_init', '__hyp_idmap_text_start', '__hyp_idmap_text_end', 'exynos_uh_forward', '__kvm_hyp_vector']
    symbols = {}
    for line in system_map.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] in names:
            symbols[fields[2]] = int(fields[0], 16)
    require(len(symbols) == len(names), 'Missing Hyp symbols')
    require(symbols['__hyp_idmap_text_start'] >> 12 == (symbols['__hyp_idmap_text_end'] - 1) >> 12, 'Hyp idmap spans multiple pages')
    require(symbols['__hyp_idmap_text_start'] <= symbols['__kvm_exynos_hyp_init'] < symbols['__hyp_idmap_text_end'], 'Handoff entry outside Hyp idmap')
    require(symbols['exynos_uh_forward'] % 2048 == 0 and abs(symbols['exynos_uh_forward'] - symbols['__kvm_hyp_vector']) < 1 << 27, 'Invalid vector forwarding alignment / range')
    page = parts['page']
    pad = lambda data: data + bytes((-len(data)) % page)
    header = bytearray(original[:page])
    struct.pack_into('<I', header, 8, len(image))
    # Standard Android boot ID: each section followed by its uint32 length.
    digest = hashlib.sha1()
    for section in [image, parts['ramdisk'], b'', b'', parts['dtb']]:
        digest.update(section)
        digest.update(struct.pack('<I', len(section)))
    header[576:608] = digest.digest() + bytes(12)
    rebuilt = bytes(header) + pad(image) + pad(parts['ramdisk']) + pad(parts['dtb']) + parts['footer']
    require(len(rebuilt) <= len(original), 'Rebuilt image exceeds the boot partition')
    rebuilt = rebuilt.ljust(len(original), b'\0')
    result = parse(rebuilt)
    for name in ['ramdisk', 'dtb', 'footer']:
        require(result[name] == parts[name], f'{name} changed')
    require(result['kernel'] == image, 'Kernel copy mismatch')
    return rebuilt

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('original', type=Path)
    parser.add_argument('image', type=Path)
    parser.add_argument('--system-map', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    try:
        original = args.original.read_bytes()
        rebuilt = replace(original, args.image.read_bytes(), args.system_map.read_text())
        args.out.parent.mkdir(parents=True, exist_ok=True)
        with args.out.open('xb') as handle:
            handle.write(rebuilt)
        print(json.dumps({'bytes': len(rebuilt), 'sha256': hashlib.sha256(rebuilt).hexdigest(), 'original_sha256': hashlib.sha256(original).hexdigest(), 'preserved': ['ramdisk', 'dtb', '64-byte footer', 'header fields except kernel size and boot ID']}, indent=2))
    except (OSError, ValueError) as error:
        parser.exit(1, f'ERROR: {error}\n')

if __name__ == '__main__':
    main()
