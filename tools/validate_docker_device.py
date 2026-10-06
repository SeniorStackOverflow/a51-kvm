#!/usr/bin/env python3
"""Validate native Docker on an already prepared A51 test daemon."""
import argparse
import io
import ipaddress
import json
from pathlib import Path
import shlex
import subprocess
import tarfile
import time

REPO = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--build', type=Path, default=REPO / 'build')
    parser.add_argument('--out', type=Path, default=REPO / 'build/docker-device.json')
    args = parser.parse_args()
    def adb(*command, timeout=90):
        return subprocess.run(['adb', '-s', args.serial, *command], capture_output=True,
                              text=True, encoding='utf-8', errors='replace', timeout=timeout)
    def su(command):
        p = adb('shell', 'su -c ' + shlex.quote(command))
        if p.returncode:
            raise RuntimeError(p.stderr.strip() or p.stdout.strip())
        return p.stdout.strip()
    def push(local, remote):
        p = adb('push', str(local), remote)
        p.check_returncode()
    if su('getprop ro.product.model') != 'SM-A515F' or su('getprop ro.bootloader') != 'A515FXXU5EUJ4':
        raise RuntimeError('Only the audited SM-A515F / A515FXXU5EUJ4 target is supported')
    if su('uname -r') != '4.14.113-22755563-docker' or su('getprop sys.boot_completed') != '1':
        raise RuntimeError('Docker kernel and completed Android boot required')
    before = su('cat /proc/sys/kernel/random/boot_id')
    group = '/dev/cpuset/a51-docker-alias-check'
    su('test ! -e ' + group + ' && mkdir ' + group)
    try:
        su('echo 0-1 > ' + group + '/cpuset.cpus')
        if su('cat ' + group + '/cpus') != '0-1':
            raise RuntimeError('Prefixed cpuset writes did not reach the native controller')
        su('echo 0 > ' + group + '/cpus')
        if su('cat ' + group + '/cpuset.cpus') != '0':
            raise RuntimeError('Android cpuset writes did not reach the alias')
        su('echo 0 > ' + group + '/cpuset.mems')
        if su('cat ' + group + '/mems') != '0':
            raise RuntimeError('Memory-node cpuset alias mismatch')
        su('mkdir ' + group + '/child && test -f ' + group + '/child/cpuset.cpus && rmdir ' + group + '/child')
    finally:
        su('rmdir ' + group)
    push(args.build / 'docker-kernel-probe', '/data/local/tmp/docker-kernel-probe')
    push(REPO / 'probes/docker/network.sh', '/data/local/tmp/docker-network-test.sh')
    su('chmod 755 /data/local/tmp/docker-kernel-probe')
    primitives = su('/data/local/tmp/docker-kernel-probe /data/local/tmp/codex-a51-docker-native-tmpfs')
    network = su('/data/adb/magisk/busybox unshare -n /system/bin/sh /data/local/tmp/docker-network-test.sh')
    prefix = '/data/local/tmp/codex-a51-docker-bin/docker --host unix:///data/local/tmp/codex-a51-docker/docker.sock '
    info = json.loads(su(prefix + "info --format '{{json .}}'"))
    if info.get('Driver') != 'overlay2' or not info.get('MemoryLimit') or not info.get('PidsLimit'):
        raise RuntimeError('Native overlay2, memory and pids support required')
    pid = su('pidof dockerd')
    if not pid.isdigit() or '/data/local/tmp/codex-a51-docker/docker.sock' not in su('cat /proc/' + pid + '/cmdline'):
        raise RuntimeError('Expected one prepared private test daemon')
    with io.BytesIO() as stream:
        with tarfile.open(fileobj=stream, mode='w') as t:
            binary = (args.build / 'docker-container-probe').read_bytes()
            item = tarfile.TarInfo('container-smoke')
            item.mode, item.uid, item.gid, item.size = 0o755, 0, 0, len(binary)
            t.addfile(item, io.BytesIO(binary))
        archive = args.build / 'docker-smoke-rootfs.tar'
        archive.write_bytes(stream.getvalue())
    push(archive, '/data/local/tmp/container-smoke-rootfs.tar')
    push(args.build / 'docker-container-probe', '/data/local/tmp/codex-a51-docker-bin/container-smoke')
    su('chmod 755 /data/local/tmp/codex-a51-docker-bin/container-smoke')
    gateway = su(prefix + "network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}'")
    ipaddress.IPv4Address(gateway)
    su('nsenter -t ' + pid + ' -n /system/bin/ip link set docker0 type bridge nf_call_iptables 1 nf_call_ip6tables 1')
    su('/system/bin/nohup /system/bin/nsenter -t ' + pid + ' -n -- /data/local/tmp/codex-a51-docker-bin/container-smoke --server >/data/local/tmp/codex-a51-docker/net-echo.log 2>&1 </dev/null &')
    for _ in range(15):
        if 'READY UDP bridge echo' in su('cat /data/local/tmp/codex-a51-docker/net-echo.log'):
            break
        time.sleep(.2)
    else:
        raise RuntimeError('UDP echo server did not become ready')
    su(prefix + "import --change 'ENTRYPOINT [\"/container-smoke\"]' /data/local/tmp/container-smoke-rootfs.tar a51-smoke:local")
    output = su(prefix + 'run --rm --name a51-native-full --memory 64m --memory-swap 64m --pids-limit 32 --cpus 0.5 --cpuset-cpus 0,1 --blkio-weight 500 a51-smoke:local --resources ' + gateway)
    required = ['PASS Docker memory cgroup', 'PASS Docker pids limit', 'PASS cpuset CPU affinity',
                'PASS UDP round trip', 'PASS native SYSVIPC', 'PASS native Docker container']
    if any(x not in output for x in required) or before != su('cat /proc/sys/kernel/random/boot_id'):
        raise RuntimeError('Incomplete container proof or unexpected phone reboot')
    result = {'kernel': su('uname -r'), 'kernel_build': su('uname -v'),
              'docker_version': info['ServerVersion'],
              'runc_version': su('/data/local/tmp/codex-a51-docker-bin/runc --version'),
              'storage_driver': info['Driver'], 'backing_filesystem': info['DriverStatus'],
              'cpuset_alias_reads_and_writes': True,
              'primitives': primitives, 'network_passes': [x for x in network.splitlines() if x.startswith('PASS')],
              'container': output, 'boot_id_unchanged': True, 'selinux': su('getenforce'), 'passed': True}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(output)
    print('PASS native Docker kernel, container resources and bridge traffic. Evidence:', args.out)

if __name__ == '__main__':
    main()
