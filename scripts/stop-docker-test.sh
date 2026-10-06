#!/system/bin/sh
set -eu
[ "$(id -u)" = 0 ]
sh /data/local/tmp/docker-network.sh stop
pidfile=/data/local/tmp/codex-a51-docker/dockerd.pid
[ -f "$pidfile" ] || exit 0
daemon=$(cat "$pidfile")
case "$daemon" in ''|*[!0-9]*) echo 'Invalid dockerd PID' >&2; exit 1;; esac
[ -r "/proc/$daemon/cmdline" ] || exit 0
tr '\000' ' ' <"/proc/$daemon/cmdline" | grep -q \
    'dockerd.*unix:///data/local/tmp/codex-a51-docker/docker.sock'
kill "$daemon"
for _attempt in $(seq 1 30); do
    [ -e "/proc/$daemon" ] || { echo 'Docker stopped; uplink removed'; exit 0; }
    sleep 1
done
echo 'Docker has not finished stopping; inspect its log' >&2
exit 1
