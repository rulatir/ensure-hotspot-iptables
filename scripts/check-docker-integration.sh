#!/usr/bin/env bash
set -euo pipefail

echo "== docker-integration check =="

# Use sudo for iptables/docker if not running as root
if [ "${EUID:-0}" -ne 0 ]; then
  SUDO=sudo
else
  SUDO=""
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI not found; skipping Docker runtime checks."
  exit 0
fi

if ! ${SUDO} docker info >/dev/null 2>&1; then
  echo "Docker daemon not reachable (docker info failed). Ensure Docker is running and you can access it."
  exit 2
fi

# Check DOCKER-USER chain existence
if ${SUDO} iptables -L DOCKER-USER >/dev/null 2>&1; then
  echo "OK: DOCKER-USER chain exists"
else
  echo "WARN: DOCKER-USER chain does NOT exist"
fi

# Check FORWARD -> DOCKER-USER jump
if ${SUDO} iptables -C FORWARD -j DOCKER-USER >/dev/null 2>&1; then
  echo "OK: FORWARD jumps to DOCKER-USER"
else
  echo "WARN: FORWARD does not jump to DOCKER-USER"
fi

# Test outbound connectivity from a bridge-mode container (may pull image)
echo "Testing outbound HTTP connectivity from a bridge-mode container (this may pull an image)..."
if ${SUDO} docker run --rm --network bridge curlimages/curl:latest --max-time 10 -sS --head https://example.com >/dev/null 2>&1; then
  echo "OK: Container outbound HTTP connectivity works (bridge mode)"
else
  echo "FAIL: Container outbound HTTP connectivity failed (bridge mode)."
  echo "Try running: ${SUDO} docker run --rm --network bridge curlimages/curl:latest --max-time 10 https://example.com"
  exit 3
fi

echo "docker-integration check completed. If the above WARN lines appear but container networking works, Docker itself is functional; WARNs may indicate Docker hasn't created the DOCKER-USER hook (harmless for a non-Docker hotspot-only setup)."

