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
