#!/usr/bin/env python3
"""Run the minimal hardware guests on an already configured, rooted A51."""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True, help='Explicit adb device; never selects a default device')
    parser.add_argument('--build', type=Path, default=Path('build'))
    parser.add_argument('--out', type=Path, default=Path('build/device-validation.json'))
    args = parser.parse_args()
    adb = ['adb', '-s', args.serial]

    def run(arguments, timeout=60):
        result = subprocess.run(adb + arguments, text=True, capture_output=True, timeout=timeout)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        return result.stdout.strip()

    def shell(command):
        return run(['shell', command])

    def root(command):
        return shell('su -c ' + shlex.quote(command))

    try:
        model = shell('getprop ro.product.model')
        firmware = shell('getprop ro.bootloader') or shell('getprop ro.boot.bootloader')
        if model != 'SM-A515F' or firmware != 'A515FXXU5EUJ4':
            raise RuntimeError('Only the validated SM-A515F / A515FXXU5EUJ4 target is supported')
        if root('id -u') != '0':
            raise RuntimeError('Root access required')
        root('test -c /dev/kvm')
        boot_before = root('cat /proc/sys/kernel/random/boot_id')
        idle_command = 'for n in 0 1 2 3 4 5 6 7; do cat /sys/devices/system/cpu/cpu$n/cpuidle/state1/usage; done'
        idle_before = list(map(int, root(idle_command).split()))
        for name in ['kvm-guest-probe', 'kvm-timer-probe', 'kvm-timer-guest.bin']:
            path = args.build / name
            expected = hashlib.sha256(path.read_bytes()).hexdigest()
            remote = '/data/local/tmp/' + name
            run(['push', str(path), remote + '.new'])
            root(f'chmod 755 {remote}.new && mv {remote}.new {remote}')
            actual = root(f'sha256sum {remote}').split()[0]
            if expected != actual:
                raise RuntimeError(f'Transfer hash mismatch for {name}')
        results = []
        for cpu in [0, 1, 2, 3, 4, 5, 6, 7, 0, 4, 0, 4]:
            output = root(f'/data/local/tmp/kvm-guest-probe {cpu}')
            if 'PASS: hardware KVM guest executed' not in output:
                raise RuntimeError(output)
            results.append({'test': 'guest', 'cpu': cpu, 'output': output, 'passed': True})
        held = root('/data/local/tmp/kvm-guest-probe 0 hold')
        if held.count('PASS: same vCPU after idle on CPU') != 10:
            raise RuntimeError(held)
        results.append({'test': 'idle-migration', 'output': held, 'passed': True})
        idle_after = list(map(int, root(idle_command).split()))
        for cpu in [0, 4]:
            output = root(f'/data/local/tmp/kvm-timer-probe {cpu}')
            if 'PASS: guest virtual timer fired; VGICv2 delivered PPI27' not in output:
                raise RuntimeError(output)
            results.append({'test': 'timer', 'cpu': cpu, 'output': output, 'passed': True})
        same_boot = root('cat /proc/sys/kernel/random/boot_id') == boot_before
        if not same_boot:
            raise RuntimeError('Phone rebooted during validation')
        evidence = {'model': model, 'firmware': firmware, 'kernel': root('uname -r'), 'passed': True, 'boot_id_unchanged': same_boot,
                    'deep_idle_usage_deltas': [b-a for a, b in zip(idle_before, idle_after)], 'runs': results,
                    'scope': 'Minimal single-vCPU execution, idle/migration and VGICv2/PPI27; no full guest OS'}
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(evidence, indent=2)+'\n')
        print(f'PASS: 12 guest cycles, held-vCPU migration and both timer clusters. Evidence: {args.out}')
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f'ERROR: {error}\n')

if __name__ == '__main__':
    main()
