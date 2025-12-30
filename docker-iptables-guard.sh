#!/usr/bin/env bash
set -euo pipefail

docker version >/dev/null 2>&1

# Run once at startup to ensure iptables invariants are restored before we start
# listening to Docker events (don't fail the service if this fails)
/usr/bin/ensure-hotspot-iptables.sh || true

docker events --format '{{.Type}} {{.Action}}' | while read -r type action; do
  case "$type $action" in
    container\ start|container\ stop|container\ die|container\ destroy|container\ restart|network\ connect|network\ disconnect|network\ create|network\ destroy)
      /usr/bin/ensure-hotspot-iptables.sh || true
      ;;
  esac
done