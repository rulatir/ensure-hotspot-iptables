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

# Rule specs we'll manage (exact-match deletions use the same args)
# Forward allow from AP -> WAN
FWD_AP_TO_WAN=( -i "$AP_IF" -o "$WAN_IF" -s "$AP_NET" -j ACCEPT )
# Forward allow for return traffic WAN -> AP (conntrack ESTABLISHED,RELATED)
FWD_WAN_TO_AP=( -i "$WAN_IF" -o "$AP_IF" -d "$AP_NET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT )
# NAT MASQUERADE
NAT_POST=( -s "$AP_NET" -o "$WAN_IF" -j MASQUERADE )

# Helper to attempt deletion of a rule in a given table/chain; ignore failures
_delete_rule() {
  local table="$1"; shift
  local chain="$1"; shift
  # shellcheck disable=SC2086
  iptables ${table:+-t "$table"} -D "$chain" "$@" >/dev/null 2>&1 || true
}

# Cleanup old-style rules that might have been added previously
# Remove exact-matching direct rules in FORWARD that might have been used instead of a dedicated chain
_delete_rule "" FORWARD "${FWD_AP_TO_WAN[@]}"
_delete_rule "" FORWARD "${FWD_WAN_TO_AP[@]}"

# Also remove hotspot-specific rules from DOCKER-USER and HOTSPOT-FORWARD if they exist but are not the chosen hook (cleanup below)
# (We will decide the canonical hook next and re-add rules there.)
_delete_rule "" DOCKER-USER "${FWD_AP_TO_WAN[@]}"
_delete_rule "" DOCKER-USER "${FWD_WAN_TO_AP[@]}"
_delete_rule nat POSTROUTING "${NAT_POST[@]}"
_delete_rule "" HOTSPOT-FORWARD "${FWD_AP_TO_WAN[@]}"
_delete_rule "" HOTSPOT-FORWARD "${FWD_WAN_TO_AP[@]}"

# Choose a stable hook chain. If Docker is present (or the DOCKER-USER chain already exists),
# prefer using DOCKER-USER because Docker is designed to preserve that chain and leave it
# as a stable hook point. If Docker is not present, create and use a dedicated HOTSPOT-FORWARD
# chain and insert a top-of-FORWARD jump to ensure hotspot rules are evaluated early.
if command -v docker >/dev/null 2>&1 || iptables -L DOCKER-USER >/dev/null 2>&1; then
  HOOK_CHAIN=DOCKER-USER
  iptables -N "${HOOK_CHAIN}" 2>/dev/null || true
  # Ensure FORWARD jumps to DOCKER-USER (Docker normally inserts this for you); do not duplicate
  iptables -C FORWARD -j "${HOOK_CHAIN}" 2>/dev/null || iptables -I FORWARD -j "${HOOK_CHAIN}"
  # Cleanup any remaining hotspot rules in other chains (ensure single source of truth)
  _delete_rule "" HOTSPOT-FORWARD "${FWD_AP_TO_WAN[@]}"
  _delete_rule "" HOTSPOT-FORWARD "${FWD_WAN_TO_AP[@]}"
else
  HOOK_CHAIN=HOTSPOT-FORWARD
  iptables -N "${HOOK_CHAIN}" 2>/dev/null || true
  # Insert at top of FORWARD to evaluate hotspot rules before other rules.
  # Using -I without position defaults to top; explicitly use position 1 for clarity.
  iptables -C FORWARD -j "${HOOK_CHAIN}" 2>/dev/null || iptables -I FORWARD 1 -j "${HOOK_CHAIN}"
  # If Docker-User contains hotspot rules from an older run, remove them so they don't conflict
  _delete_rule "" DOCKER-USER "${FWD_AP_TO_WAN[@]}"
  _delete_rule "" DOCKER-USER "${FWD_WAN_TO_AP[@]}"
fi

# Allow AP subnet to forward out to WAN; allow return traffic in the chosen hook chain
iptables -C "${HOOK_CHAIN}" -i "$AP_IF" -o "$WAN_IF" -s "$AP_NET" -j ACCEPT 2>/dev/null || \
  iptables -A "${HOOK_CHAIN}" -i "$AP_IF" -o "$WAN_IF" -s "$AP_NET" -j ACCEPT

iptables -C "${HOOK_CHAIN}" -i "$WAN_IF" -o "$AP_IF" -d "$AP_NET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  iptables -A "${HOOK_CHAIN}" -i "$WAN_IF" -o "$AP_IF" -d "$AP_NET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# NAT hotspot subnet out WAN
iptables -t nat -C POSTROUTING -s "$AP_NET" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "$AP_NET" -o "$WAN_IF" -j MASQUERADE

