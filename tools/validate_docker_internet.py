#!/usr/bin/env python3
"""Exercise real registry, DNS, HTTP(S), and bridge egress on the prepared A51."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
import time

REPO = Path(__file__).resolve().parents[1]
PREFIX = '/data/local/tmp/codex-a51-docker-bin/docker --host unix:///data/local/tmp/codex-a51-docker/docker.sock '


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--image', default='alpine:3.22')
    parser.add_argument('--out', type=Path, default=REPO / 'build/docker-internet.json')
    args = parser.parse_args()

    def su(command, timeout=180):
        result = subprocess.run(
            ['adb', '-s', args.serial, 'shell'], input='su -c ' + shlex.quote(command) + '\n',
            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout)
        if result.returncode:
            raise RuntimeError(f'{command}\n{result.stdout}\n{result.stderr}')
        return result.stdout.strip()

    def docker(*words, timeout=180):
        return su(PREFIX + shlex.join(words), timeout)

    if su('getprop ro.product.model') != 'SM-A515F' or su('getprop ro.bootloader') != 'A515FXXU5EUJ4':
        raise RuntimeError('Audited SM-A515F / A515FXXU5EUJ4 required')
    if su('uname -r') != '4.14.113-22755563-docker' or su('getprop sys.boot_completed') != '1':
        raise RuntimeError('Booted Docker kernel required')
    before = su('cat /proc/sys/kernel/random/boot_id')
    status = su('sh /data/local/tmp/docker-network.sh status')
    if docker('network', 'ls', '--format', '{{.Name}}').splitlines().count('a51-internet-check'):
        raise RuntimeError('Test network already exists; inspect it first')
    pull = docker('pull', args.image, timeout=300)
    image = json.loads(docker('image', 'inspect', args.image))[0]
    script = '''set -eu
nslookup example.com
echo 'PASS external DNS'
wget -q -O /tmp/http http://1.1.1.1/cdn-cgi/trace
test -s /tmp/http
echo 'PASS IPv4 HTTP without DNS'
wget -q -O /tmp/https https://example.com
grep -q 'Example Domain' /tmp/https
echo 'PASS HTTPS with certificate verification'
if wget -T 10 -q -O /tmp/untrusted https://self-signed.badssl.com 2>/tmp/tls-error; then
    echo 'FAIL untrusted HTTPS certificate was accepted' >&2
    exit 1
fi
grep -q 'certificate verify failed' /tmp/tls-error
echo 'PASS untrusted HTTPS certificate rejected'
apk update
echo 'PASS package repository downloads'
'''
    default = docker('run', '--rm', '--memory', '64m', '--pids-limit', '64', args.image, 'sh', '-ec', script)
    docker('network', 'create', 'a51-internet-check')
    try:
        # Prove Docker's embedded DNS and egress on a user-created bridge too.
        docker('run', '-d', '--rm', '--name', 'a51-internet-peer', '--network', 'a51-internet-check',
               '--memory', '32m', '--pids-limit', '32', args.image, 'sleep', '120')
        time.sleep(1)
        custom = docker('run', '--rm', '--network', 'a51-internet-check', '--memory', '64m',
                        '--pids-limit', '64', args.image, 'sh', '-ec',
                        "ping -c 1 -W 5 a51-internet-peer; "
                        "echo 'PASS container-name DNS and bridge round trip'; " + script)
    finally:
        docker('rm', '-f', 'a51-internet-peer')
        docker('network', 'rm', 'a51-internet-check')
    docker('network', 'create', '--internal', 'a51-internet-check')
    try:
        internal = docker('run', '--rm', '--network', 'a51-internet-check', args.image, 'sh', '-ec',
                          'if timeout 5 wget -qO- http://1.1.1.1/cdn-cgi/trace; then exit 1; fi; '
                          "echo 'PASS internal bridge has no internet egress'")
    finally:
        docker('network', 'rm', 'a51-internet-check')
    android = su('ping -c 1 -W 5 1.1.1.1')
    if before != su('cat /proc/sys/kernel/random/boot_id') or su('getenforce') != 'Enforcing':
        raise RuntimeError('Phone rebooted or SELinux state changed')
    result = {
        'kernel': su('uname -r'), 'docker_version': docker('version', '--format', '{{.Server.Version}}'),
        'image': args.image, 'image_digests': image['RepoDigests'], 'platform': image['Architecture'],
        'registry_pull': pull, 'uplink_status': status, 'default_bridge': default,
        'user_bridge': custom, 'internal_bridge': internal, 'android_ping': android,
        'boot_id_unchanged': True, 'selinux': 'Enforcing', 'passed': True,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(default)
    print(custom)
    print(internal)
    print('PASS Docker internet; evidence:', args.out)


if __name__ == '__main__':
    main()
