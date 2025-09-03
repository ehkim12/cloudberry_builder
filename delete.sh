#!/bin/bash
set -e

# Check if image exists before removing
if docker images cbdb-main:rockylinux9.6 --format "{{.Repository}}:{{.Tag}}" | grep -q "^cbdb-main:rockylinux9.6$"; then
    echo "[INFO] Removing image cbdb-main:rockylinux9.6..."
    docker rmi cbdb-main:rockylinux9.6
else
    echo "[INFO] Image cbdb-main:rockylinux9.6 not found, skipping"
fi
echo "[INFO] Cleanup completed."