#!/system/bin/sh
set -eu
[ "$(id -u)" = 0 ]
[ "$(uname -r)" = 4.14.113-22755563-docker ]
[ "$(getprop ro.product.model)" = SM-A515F ]
[ "$(getprop ro.bootloader)" = A515FXXU5EUJ4 ]
if pidof dockerd >/dev/null; then
    echo 'A Docker daemon is already running; inspect it before starting another' >&2
    exit 1
fi
[ -f /data/local/tmp/codex-a51-docker-storage.ext4 ]
[ -x /data/local/tmp/docker-daemon-launcher ]
[ -x /data/local/tmp/codex-a51-docker-bin/dockerd ]
nohup /data/local/tmp/docker-daemon-launcher \
    /data/local/tmp/codex-a51-docker-bin/dockerd \
    --host unix:///data/local/tmp/codex-a51-docker/docker.sock \
    --group 0 \
    --data-root /data/local/tmp/codex-a51-docker/data \
    --exec-root /data/local/tmp/codex-a51-docker/exec \
    --pidfile /data/local/tmp/codex-a51-docker/dockerd.pid \
    --storage-driver overlay2 --exec-opt native.cgroupdriver=cgroupfs \
    >/data/local/tmp/codex-a51-dockerd.log 2>&1 </dev/null &
echo 'Started private test daemon; check its process, log and API readiness'
