#!/usr/bin/env bash
set -euo pipefail

docker version >/dev/null 2>&1

docker events --format '{{.Type}} {{.Action}}' | while read -r type action; do
  case "$type $action" in
    container\ start|container\ stop|container\ die|container\ destroy|container\ restart|network\ connect|network\ disconnect|network\ create|network\ destroy)
      /usr/local/sbin/ensure-hotspot-iptables.sh || true
      ;;
  esac
done