#!/usr/bin/env bash
# Wipe EVERYTHING from Docker: containers, images, volumes, non-default networks, build cache.
# Usage: bash wipe_docker_all.sh [-y]
set -Eeuo pipefail

YES=0
[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && YES=1

# Resolve docker binary (with sudo fallback if needed)
DOCKER_BIN="${DOCKER:-docker}"
if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
  echo "docker not found in PATH." >&2
  exit 1
fi
if ! "$DOCKER_BIN" info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
    DOCKER_BIN="sudo $DOCKER_BIN"
  fi
fi

echo "This will REMOVE ALL Docker containers, images, volumes, and non-default networks on this host."
echo "It will also prune ALL build cache and system data."
if [[ $YES -ne 1 ]]; then
  read -r -p "Type 'WIPE' to continue: " CONFIRM
  [[ "$CONFIRM" == "WIPE" ]] || { echo "Aborted."; exit 1; }
fi

# Helpful function: safe xargs (no error when input is empty)
_xargs() { xargs -r "$@"; }

echo "==> Stopping all running containers..."
$DOCKER_BIN ps -q | _xargs $DOCKER_BIN stop || true

echo "==> Removing all containers..."
$DOCKER_BIN ps -aq | _xargs $DOCKER_BIN rm -f || true

echo "==> Removing all volumes..."
$DOCKER_BIN volume ls -q | _xargs $DOCKER_BIN volume rm -f || true

echo "==> Removing all non-default networks..."
# Keep the default networks: bridge, host, none
NON_DEFAULT_NETS=$($DOCKER_BIN network ls --format '{{.Name}}' \
  | grep -v -E '^(bridge|host|none)$' || true)
if [[ -n "${NON_DEFAULT_NETS}" ]]; then
  # shellcheck disable=SC2086
  echo "$NON_DEFAULT_NETS" | _xargs $DOCKER_BIN network rm || true
fi

echo "==> Removing all images..."
$DOCKER_BIN images -q | _xargs $DOCKER_BIN rmi -f || true

echo "==> Pruning all builders' cache..."
$DOCKER_BIN builder prune -a -f || true
if $DOCKER_BIN buildx version >/dev/null 2>&1; then
  $DOCKER_BIN buildx prune -a -f || true
fi

echo "==> Final system prune (images, networks, build cache, and volumes)..."
$DOCKER_BIN system prune -a --volumes -f || true

echo "==> Checking disk usage after cleanup..."
$DOCKER_BIN system df || true

echo "✅ Docker wipe complete."

