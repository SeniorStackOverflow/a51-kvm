#!/system/bin/sh
set -eu
ip=/system/bin/ip
iptables=/system/bin/iptables
ip6tables=/system/bin/ip6tables
$ip link set lo up
$ip link add dk-br0 type bridge
$ip link add dk-v0 type veth peer name dk-v1
$ip link set dk-v0 master dk-br0
$ip addr add 10.231.42.1/24 dev dk-br0
$ip link set dk-br0 up
$ip link set dk-v0 up
$ip link set dk-v1 up
$ip -d link show dk-br0
$ip -d link show dk-v0
echo 'PASS VETH pair and BRIDGE created, linked and brought up in private netns'
$iptables -t nat -N DK_TEST
$iptables -t nat -A DK_TEST -m addrtype --dst-type LOCAL -j RETURN
$iptables -t nat -A POSTROUTING -s 10.231.42.0/24 -j MASQUERADE
$iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
$iptables -t nat -S DK_TEST
echo 'PASS IPv4 NETFILTER NAT/MASQUERADE/addrtype/conntrack rules'
$ip6tables -t nat -N DK6_TEST
$ip6tables -t nat -A POSTROUTING -s fd00:231:42::/64 -j MASQUERADE
$ip6tables -t nat -S DK6_TEST
echo 'PASS IPv6 NETFILTER NAT/MASQUERADE rules'
$ip link set dk-br0 type bridge nf_call_iptables 1 nf_call_ip6tables 1
$ip -d link show dk-br0
echo 'PASS BRIDGE_NETFILTER per-bridge IPv4/IPv6 attributes enabled'
$ip link del dk-v0
$ip link del dk-br0
echo 'PASS all isolated Docker networking checks'
