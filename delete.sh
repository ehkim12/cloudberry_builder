#!/bin/bash
set -e

# Stop and remove compose stack if running
if docker compose -f docker-compose.yml ps -q | grep -q .; then
    echo "[INFO] Stopping services..."
    docker compose -f docker-compose.yml stop
    docker compose -f docker-compose.yml down -v
else
    echo "[INFO] No running services found in docker-compose.yml"
fi

# Check if image exists before removing
if docker images cbdb-main:rockylinux9.6 --format "{{.Repository}}:{{.Tag}}" | grep -q "^cbdb-main:rockylinux9.6$"; then
    echo "[INFO] Removing image cbdb-main:rockylinux9.6..."
    docker rmi cbdb-main:rockylinux9.6
else
    echo "[INFO] Image cbdb-main:rockylinux9.6 not found, skipping"
fi
echo "[INFO] Cleanup completed."