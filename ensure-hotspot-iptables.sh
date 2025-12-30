#!/usr/bin/env bash
set -euo pipefail

# Find the Wi-Fi interface currently in AP mode (hotspot)
AP_IF="$(
  iw dev 2>/dev/null \
  | awk '
      $1=="Interface"{iface=$2}
      $1=="type" && $2=="AP"{print iface; exit}
    '
)"
[[ -n "${AP_IF:-}" ]] || exit 0  # hotspot not active

# Find the hotspot subnet (connected route) for that AP interface
AP_NET="$(ip -4 route show dev "$AP_IF" scope link 2>/dev/null | awk 'NR==1{print $1; exit}')"
[[ -n "${AP_NET:-}" ]] || exit 0

# Find current uplink interface from default IPv4 route
WAN_IF="$(ip -4 route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[[ -n "${WAN_IF:-}" ]] || exit 0

# Ensure stable hook point that Docker is supposed to preserve
iptables -N DOCKER-USER 2>/dev/null || true
iptables -C FORWARD -j DOCKER-USER 2>/dev/null || iptables -I FORWARD -j DOCKER-USER

# Allow AP subnet to forward out to WAN; allow return traffic
iptables -C DOCKER-USER -i "$AP_IF" -o "$WAN_IF" -s "$AP_NET" -j ACCEPT 2>/dev/null || \
  iptables -A DOCKER-USER -i "$AP_IF" -o "$WAN_IF" -s "$AP_NET" -j ACCEPT

iptables -C DOCKER-USER -i "$WAN_IF" -o "$AP_IF" -d "$AP_NET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  iptables -A DOCKER-USER -i "$WAN_IF" -o "$AP_IF" -d "$AP_NET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# NAT hotspot subnet out WAN
iptables -t nat -C POSTROUTING -s "$AP_NET" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "$AP_NET" -o "$WAN_IF" -j MASQUERADE