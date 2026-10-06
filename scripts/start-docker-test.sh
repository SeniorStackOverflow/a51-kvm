#!/system/bin/sh
set -eu
[ "$(id -u)" = 0 ]
[ "$(uname -r)" = 4.14.113-22755563-docker ]
[ "$(getprop ro.product.model)" = SM-A515F ]
[ "$(getprop ro.bootloader)" = A515FXXU5EUJ4 ]
case "${1:-}" in
    '') network=internet;;
    --isolated) network=isolated;;
    *) echo 'usage: start-docker-test.sh [--isolated]' >&2; exit 2;;
esac
[ "$#" -le 1 ]
if pidof dockerd >/dev/null; then
    echo 'A Docker daemon is already running; inspect it before starting another' >&2
    exit 1
fi
[ -f /data/local/tmp/codex-a51-docker-storage.ext4 ]
[ -x /data/local/tmp/docker-daemon-launcher ]
[ -x /data/local/tmp/codex-a51-docker-bin/dockerd ]
if [ "$network" = internet ]; then
    [ -f /data/local/tmp/docker-network.sh ]
    [ -f /data/local/tmp/stop-docker-test.sh ]
    [ ! -e /data/local/tmp/codex-a51-docker-network ]
fi
nohup /data/local/tmp/docker-daemon-launcher \
    /data/local/tmp/codex-a51-docker-bin/dockerd \
    --host unix:///data/local/tmp/codex-a51-docker/docker.sock \
    --group 0 \
    --data-root /data/local/tmp/codex-a51-docker/data \
    --exec-root /data/local/tmp/codex-a51-docker/exec \
    --pidfile /data/local/tmp/codex-a51-docker/dockerd.pid \
    --dns 1.1.1.1 --dns 8.8.8.8 \
    --storage-driver overlay2 --exec-opt native.cgroupdriver=cgroupfs \
    >/data/local/tmp/codex-a51-dockerd.log 2>&1 </dev/null &
launcher=$!
ready=0
for _attempt in $(seq 1 30); do
    if /data/local/tmp/codex-a51-docker-bin/docker \
        --host unix:///data/local/tmp/codex-a51-docker/docker.sock info >/dev/null 2>&1; then
        ready=1; break
    fi
    kill -0 "$launcher" 2>/dev/null || break
    sleep 1
done
if [ "$ready" != 1 ]; then
    kill "$launcher" 2>/dev/null || true
    cat /data/local/tmp/codex-a51-dockerd.log >&2
    exit 1
fi
if [ "$network" = internet ]; then
    daemon=$(cat /data/local/tmp/codex-a51-docker/dockerd.pid)
    if ! sh /data/local/tmp/docker-network.sh start "$daemon"; then
        sh /data/local/tmp/stop-docker-test.sh
        exit 1
    fi
fi
echo "Docker ready ($network) on unix:///data/local/tmp/codex-a51-docker/docker.sock"
