#!/usr/bin/env python3
"""Generate a reversible Magisk module from the user's audited FCM4 matrix."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ORIGINAL_SHA = '5d18ac9acc5dfdc59bf6aeaa2f57d02f5e6d26712cc65179fa5f670641d74fb0'
PATCHED_SHA = '8fb661c2f6ba065141054d9baf581f38c3c8de6b5f4cb8fd167cd6c920f94149'

def transform(raw):
    if hashlib.sha256(raw).hexdigest() != ORIGINAL_SHA:
        raise ValueError('Unsupported matrix; only the audited A515FXXU5EUJ4 FCM4 file is supported')
    source = raw.decode('utf-8')
    count = 0
    def kernel(match):
        nonlocal count
        body, n = re.subn(r'(<key>CONFIG_SYSVIPC</key>\s*<value type="tristate">)n(</value>)',
                          r'\g<1>y\2', match[2])
        count += n
        return match[1] + body + match[3]
    patched = re.sub(r'(<kernel\b[^>]*version="4\.14\.[^"]*"[^>]*>)(.*?)(</kernel>)',
                     kernel, source, flags=re.S)
    a, b = list(ET.fromstring(source).iter()), list(ET.fromstring(patched).iter())
    if count != 1 or len(a) != len(b):
        raise ValueError('Expected exactly one SYSVIPC contract change')
    differences = []
    for old, new in zip(a, b):
        if (old.tag, old.attrib, old.tail) != (new.tag, new.attrib, new.tail):
            raise ValueError('Unexpected XML structural change')
        if old.text != new.text:
            differences.append((old.tag, old.text, new.text))
    output = patched.encode('utf-8')
    if differences != [('value', 'n', 'y')] or hashlib.sha256(output).hexdigest() != PATCHED_SHA:
        raise ValueError('Unexpected matrix transformation')
    return output

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('matrix', type=Path)
    parser.add_argument('--out', type=Path, required=True, help='New module directory')
    args = parser.parse_args()
    patched = transform(args.matrix.read_bytes())
    if args.out.exists():
        parser.error('Output already exists; choose a fresh directory')
    (args.out / 'overlay').mkdir(parents=True)
    (args.out / 'overlay/compatibility_matrix.4.xml').write_bytes(patched)
    (args.out / 'module.prop').write_text(
        'id=a51_docker_vintf\nname=A51 Docker kernel VINTF contract\n'
        'version=0.2\nversionCode=2\nauthor=SeniorStackOverflow\n'
        'description=Match native SYSVIPC for the audited A51 Docker kernel.\n', encoding='utf-8', newline='\n')
    (args.out / 'post-fs-data.sh').write_text('''#!/system/bin/sh
MODDIR=${0%/*}
[ "$(uname -r)" = "4.14.113-22755563-docker" ] || exit 0
[ "$(getprop ro.bootloader)" = "A515FXXU5EUJ4" ] || exit 0
TARGET=/system/etc/vintf/compatibility_matrix.4.xml
SOURCE=$MODDIR/overlay/compatibility_matrix.4.xml
[ "$(sha256sum "$TARGET" | cut -d ' ' -f 1)" = "''' + ORIGINAL_SHA + '''" ] || exit 0
chcon u:object_r:system_file:s0 "$SOURCE" || exit 1
mount -o bind "$SOURCE" "$TARGET"
''', encoding='utf-8', newline='\n')
    manifest = {'original_sha256': ORIGINAL_SHA, 'patched_sha256': PATCHED_SHA,
                'only_change': 'FCM4 kernel4.14 CONFIG_SYSVIPC n -> y',
                'certification': 'Custom kernel contract; not stock VTS compliance'}
    (args.out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Prepared reversible Docker VINTF module; no device writes')

if __name__ == '__main__':
    main()
