#!/system/bin/sh
# IPv4 uplink for the private A51 Docker namespace. Run as Android root.
set -eu
PATH=/system/bin:/system/xbin
export PATH
state=/data/local/tmp/codex-a51-docker-network
self=/data/local/tmp/docker-network.sh
host=a51-dk0
peer=a51-dk1
address=10.231.43.2
fwd=A51_DOCKER_FWD
nat=A51_DOCKER_NAT
socket=/data/local/tmp/codex-a51-docker/docker.sock
ipt() { iptables -w 5 "$@"; }
die() { echo "$*" >&2; exit 1; }
starttime() { awk '{print $22}' "/proc/$1/stat"; }
daemon_ok() {
    [ -r "/proc/$daemon/stat" ] && [ "$(starttime "$daemon")" = "$birth" ] &&
        tr '\000' ' ' <"/proc/$daemon/cmdline" | grep -q "dockerd.*$socket"
}
net() { nsenter -t "$daemon" -n -- "$@"; }
subnet_in_use() {
    # Compare ranges, including broader routes such as a VPN's 10.0.0.0/8.
    awk '
    function number(s, a) { split(s,a,"."); return a[1]*16777216+a[2]*65536+a[3]*256+a[4] }
    BEGIN { low=number("10.231.43.0"); high=low+3; found=0 }
    {
        split($1,cidr,"/");
        if(cidr[1] !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) next;
        bits=cidr[2]=="" ? 32 : cidr[2];
        if(bits==0) next;
        size=2^(32-bits); start=int(number(cidr[1])/size)*size;
        if(start<=high && start+size-1>=low) found=1;
    }
    END { exit !found }'
}
cleanup() {
    set +e
    rm -f "$state/ready"
    # Delete only our exact selectors and chains, never Android's rules.
    ip -4 rule del pref 9001 iif "$host" 2>/dev/null
    ip -4 rule del pref 9002 iif "$host" unreachable 2>/dev/null
    ip -4 rule del pref 9000 to "$address/32" lookup main 2>/dev/null
    ipt -D FORWARD -i "$host" -j "$fwd" 2>/dev/null
    ipt -D FORWARD -o "$host" -j "$fwd" 2>/dev/null
    ipt -t nat -D POSTROUTING -s "$address/32" -j "$nat" 2>/dev/null
    if [ "$owned" = 1 ]; then
        ipt -F "$fwd" 2>/dev/null; ipt -X "$fwd" 2>/dev/null
        ipt -t nat -F "$nat" 2>/dev/null; ipt -t nat -X "$nat" 2>/dev/null
        if ip -d link show "$host" 2>/dev/null | grep -q 'alias a51-docker-uplink'; then
            ip link del "$host"
        fi
        ndc ipfwd disable a51-docker >/dev/null
    fi
    rm -f "$state/pid" "$state/daemon" "$state/ready" "$state/egress"
    rmdir "$state"
}
refresh() {
    # Ask Android where root's ordinary internet traffic goes. Do not assume
    # a Linux main-table default route or hard-code a Wi-Fi/mobile interface.
    route=$(ip -4 route get 1.1.1.1 uid 0 2>/dev/null | head -n 1) || route=
    uplink=$(echo "$route" | awk '{for(i=1;i<NF;i++)if($i=="dev")print $(i+1)}')
    table=$(echo "$route" | awk '{for(i=1;i<NF;i++)if($i=="table")print $(i+1)}')
    [ -n "$table" ] || table=main
    case "$uplink:$table" in *[!a-zA-Z0-9_.:-]*|:*) uplink=;; esac
    case "$uplink" in "$host"|"$peer"|lo|dummy0) uplink=;; esac
    current="$uplink:$table"
    if [ "$current" != "$previous" ]; then
        ip -4 rule del pref 9001 iif "$host" 2>/dev/null || true
        ipt -F "$fwd"
        ipt -t nat -F "$nat"
        if [ -n "$uplink" ]; then
            # The terminal rule below fails closed while no uplink exists.
            ipt -A "$fwd" -i "$host" -s "$address/32" -o "$uplink" -j ACCEPT
            ipt -A "$fwd" -o "$host" -d "$address/32" -i "$uplink" \
                -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
            ipt -t nat -A "$nat" -o "$uplink" -j MASQUERADE
            ip -4 rule add pref 9001 iif "$host" lookup "$table"
        fi
        ipt -A "$fwd" -j DROP
        printf '%s\n' "$current" >"$state/egress"
        echo "Docker uplink: ${uplink:-offline} (Android table $table)"
        previous=$current
    fi
    # Android may regenerate top-level netd hooks during network changes.
    ipt -C FORWARD -i "$host" -j "$fwd" 2>/dev/null || ipt -I FORWARD 1 -i "$host" -j "$fwd"
    ipt -C FORWARD -o "$host" -j "$fwd" 2>/dev/null || ipt -I FORWARD 1 -o "$host" -j "$fwd"
    ipt -t nat -C POSTROUTING -s "$address/32" -j "$nat" 2>/dev/null ||
        ipt -t nat -I POSTROUTING 1 -s "$address/32" -j "$nat"
}
[ "$(id -u)" = 0 ] || die 'Android root required'
[ "$(uname -r)" = 4.14.113-22755563-docker ] || die 'Audited Docker kernel required'
case "${1:-}" in
start)
    daemon=${2:-}
    case "$daemon" in ''|*[!0-9]*) die 'usage: docker-network.sh start DOCKERD_PID';; esac
    [ ! -e "$state" ] || die 'Network supervisor state exists; inspect status or stop it first'
    birth=$(starttime "$daemon")
    daemon_ok || die 'Expected private A51 dockerd'
    nohup sh "$self" watch "$daemon" "$birth" \
        >/data/local/tmp/codex-a51-docker-network.log 2>&1 </dev/null &
    watcher=$!
    for _attempt in $(seq 1 30); do
        [ ! -f "$state/ready" ] || { cat "$state/egress"; exit 0; }
        kill -0 "$watcher" 2>/dev/null || break
        sleep 1
    done
    kill "$watcher" 2>/dev/null || true
    cat /data/local/tmp/codex-a51-docker-network.log >&2
    die 'Docker uplink did not become ready'
    ;;
watch)
    daemon=$2; birth=$3
    daemon_ok || die 'Private daemon disappeared'
    # Refuse collisions before installing cleanup traps or changing anything.
    ! ip link show "$host" >/dev/null 2>&1 || die 'Uplink interface already exists'
    ! ipt -S "$fwd" >/dev/null 2>&1 || die 'Forward chain already exists'
    ! ipt -t nat -S "$nat" >/dev/null 2>&1 || die 'NAT chain already exists'
    ! ip -4 rule show | grep -qE '^900[012]:' || die 'Policy priorities 9000-9002 are occupied'
    ! ip -4 route show table all | subnet_in_use || die 'Uplink subnet is occupied on Android'
    ! net ip -4 route show table all | subnet_in_use || die 'Uplink subnet is occupied in Docker'
    umask 077
    mkdir "$state"
    owned=1
    trap cleanup EXIT
    trap 'exit 0' INT TERM HUP
    echo "$$" >"$state/pid"
    echo "$daemon" >"$state/daemon"
    ipt -N "$fwd"
    ipt -A "$fwd" -j DROP
    ipt -t nat -N "$nat"
    ip link add "$host" type veth peer name "$peer"
    ip link set "$host" alias a51-docker-uplink
    ip link set "$peer" netns "$daemon"
    ip addr add 10.231.43.1/30 dev "$host"
    ip link set "$host" up
    net ip addr add "$address/30" dev "$peer"
    net ip link set "$peer" up
    net ip route add default via 10.231.43.1 dev "$peer"
    ip -4 rule add pref 9000 to "$address/32" lookup main
    ip -4 rule add pref 9002 iif "$host" unreachable
    ndc ipfwd enable a51-docker | grep -q '^200 ' || die 'netd rejected forwarding request'
    [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ] || die 'IPv4 forwarding unavailable'
    previous='unset'
    refresh
    touch "$state/ready"
    while daemon_ok; do sleep 5; refresh; done
    ;;
stop)
    [ -d "$state" ] || exit 0
    watcher=$(cat "$state/pid")
    case "$watcher" in ''|*[!0-9]*) die 'Invalid supervisor PID';; esac
    if [ -r "/proc/$watcher/cmdline" ]; then
        tr '\000' ' ' <"/proc/$watcher/cmdline" | grep -q "$self watch " || die 'Supervisor PID was reused'
        kill "$watcher"
        for _attempt in $(seq 1 15); do [ -d "$state" ] || exit 0; sleep 1; done
        die 'Supervisor cleanup has not completed; inspect network log'
    fi
    # A killed supervisor can leave scoped rules behind. Recover only if the
    # interface still carries our ownership alias.
    ip -d link show "$host" | grep -q 'alias a51-docker-uplink' || die 'Stale state needs inspection'
    owned=1; cleanup
    ;;
status)
    [ -f "$state/ready" ] || die 'Docker uplink is stopped'
    watcher=$(cat "$state/pid")
    case "$watcher" in ''|*[!0-9]*) die 'Invalid supervisor PID';; esac
    [ -r "/proc/$watcher/cmdline" ] || die 'Supervisor stopped; run docker-network.sh stop to clean up'
    tr '\000' ' ' <"/proc/$watcher/cmdline" | grep -q "$self watch " || die 'Supervisor PID was reused'
    cat "$state/egress"
    ip -4 rule show | grep -E '^900[012]:'
    ipt -L "$fwd" -nv
    ;;
*) die 'usage: docker-network.sh start DOCKERD_PID | stop | status';;
esac
