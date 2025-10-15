#!/bin/bash
## ======================================================================
## Container initialization script (robust version)
## ======================================================================

set -Eeuo pipefail

log() { printf '%s %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '%s [WARN] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { printf '%s [FATAL] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

# ----------------------------------------------------------------------
# Start SSH daemon and allow logins
# ----------------------------------------------------------------------
if ! sudo /usr/sbin/sshd; then
  die "Failed to start SSH daemon"
fi
sudo rm -rf /run/nologin || true

# ----------------------------------------------------------------------
# Ownership for assets used during init
# ----------------------------------------------------------------------
sudo chown -R gpadmin:gpadmin /usr/local/cloudberry-db \
  /tmp/gpinitsystem_singlenode \
  /tmp/gpinitsystem_multinode \
  /tmp/gpdb-hosts \
  /tmp/multinode-gpinit-hosts \
  /tmp || true

# Optional files; don't fail if missing
sudo chown gpadmin:gpadmin /tmp/faa.tar.gz 2>/dev/null || true
sudo chown gpadmin:gpadmin /tmp/smoke-test.sh 2>/dev/null || true

# ----------------------------------------------------------------------
# Passwordless SSH for gpadmin (skip etcd*)
# ----------------------------------------------------------------------
mkdir -p /home/gpadmin/.ssh
chmod 700 /home/gpadmin/.ssh

if [ ! -f /home/gpadmin/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -b 4096 -C gpadmin -f /home/gpadmin/.ssh/id_rsa -P "" >/dev/null 2>&1
fi

# Ensure authorized_keys contains our pubkey (idempotent)
grep -qF "$(cat /home/gpadmin/.ssh/id_rsa.pub)" /home/gpadmin/.ssh/authorized_keys 2>/dev/null || \
  cat /home/gpadmin/.ssh/id_rsa.pub >> /home/gpadmin/.ssh/authorized_keys
chmod 600 /home/gpadmin/.ssh/authorized_keys

# Helper: add host key if reachable
add_known_host() {
  local h="$1"
  ssh-keyscan -T 2 -t rsa "$h" >> /home/gpadmin/.ssh/known_hosts 2>/dev/null || true
}
> /home/gpadmin/.ssh/known_hosts
add_known_host cdw
add_known_host scdw
add_known_host sdw1
add_known_host sdw2

# Helper: push key only if ssh reachable
copy_key_if_ssh_up() {
  local h="$1"
  if timeout 2 bash -c "cat < /dev/null >/dev/tcp/${h}/22" 2>/dev/null; then
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no "$h" || warn "ssh-copy-id to $h failed"
  else
    warn "ssh port closed on $h; skipping ssh-copy-id"
  fi
}

# ----------------------------------------------------------------------
# Cloudberry environment
# ----------------------------------------------------------------------
# shellcheck disable=SC1091
source /usr/local/cloudberry-db/greenplum_path.sh || die "Missing greenplum_path.sh"
export COORDINATOR_DATA_DIRECTORY=/data0/database/coordinator/gpseg-1
export PGPORT=${PGPORT:-5432}

# Persist PGPORT in bashrc (idempotent)
grep -q "export PGPORT=" ~/.bashrc 2>/dev/null || echo "export PGPORT=${PGPORT}" >> ~/.bashrc

mkdir -p /data0/database/coordinator /data0/database/primary /data0/database/mirror
chown -R gpadmin:gpadmin /data0

# ----------------------------------------------------------------------
# Ensure external FTS is not running before init
# ----------------------------------------------------------------------
pkill -f gpfts 2>/dev/null || true

# ----------------------------------------------------------------------
# Initialization
# ----------------------------------------------------------------------
MULTINODE=${MULTINODE:-false}
HOSTNAME=${HOSTNAME:-$(hostname)}

db_up() { pg_isready -h localhost -p "${PGPORT}" -t 2 >/dev/null 2>&1; }

gpinitsystem_single() {
  gpinitsystem -a \
    -c /tmp/gpinitsystem_singlenode \
    -h /tmp/gpdb-hosts \
    --max_connections=100
}

gpinitsystem_multi() {
  # push keys only to data/standby nodes (no etcd)
  for h in sdw1 sdw2 scdw; do copy_key_if_ssh_up "$h"; done

  # Run multi-node init; extra args provided by your file set
  gpinitsystem -a \
    -c /tmp/gpinitsystem_multinode \
    -h /tmp/multinode-gpinit-hosts \
    --max_connections=100 \
    -E /tmp/etcd_service.conf \
    -F /tmp/gpdb_all_hosts \
    -p /tmp/cbdb_etcd.conf \
    -U 1
}

INIT_OK=false
if [[ "$HOSTNAME" == "cdw" ]]; then
  log "Starting cluster initialization on coordinator (cdw). MULTINODE=${MULTINODE}"

  if [[ "$MULTINODE" == "false" ]]; then
    if gpinitsystem_single; then INIT_OK=true; else INIT_OK=false; fi
  else
    if gpinitsystem_multi; then INIT_OK=true; else INIT_OK=false; fi
  fi

  # Post-init: only proceed if DB is up
  if [[ "${INIT_OK}" == "true" ]]; then
    # Wait up to ~30s for postgres
    for i in {1..30}; do db_up && break || sleep 1; done
  fi

  if db_up; then
    # pg_hba trust (only if file exists)
    if [[ -f /data0/database/coordinator/gpseg-1/pg_hba.conf ]]; then
      echo 'host all all 0.0.0.0/0 trust' >> /data0/database/coordinator/gpseg-1/pg_hba.conf
      gpstop -u || true
    else
      warn "pg_hba.conf not found; skipping trust rule"
    fi

    # Basic runtime configs (safe even on multinode)
    gpconfig -c hot_standby -v on || warn "gpconfig hot_standby failed"
    gpconfig -c wal_level -v replica || warn "gpconfig wal_level failed"
    gpconfig -c max_wal_senders -v 16 || warn "gpconfig max_wal_senders failed"
  else
    INIT_OK=false
  fi
elif [[ "$HOSTNAME" == "scdw" ]]; then
  # Standby container: only distribute keys to data/coordinator nodes
  for h in sdw1 sdw2 cdw; do copy_key_if_ssh_up "$h"; done
  INIT_OK=true  # nothing to init here
else
  # Segment containers do nothing special here
  INIT_OK=true
fi

# ----------------------------------------------------------------------
# pgpass
# ----------------------------------------------------------------------
cat > ~/.pgpass <<EOF
localhost:${PGPORT}:*:gpadmin:cbdb@123
127.0.0.1:${PGPORT}:*:gpadmin:cbdb@123
cdw:${PGPORT}:*:gpadmin:cbdb@123
scdw:${PGPORT}:*:gpadmin:cbdb@123
sdw1:${PGPORT}:*:gpadmin:cbdb@123
sdw2:${PGPORT}:*:gpadmin:cbdb@123
EOF
chmod 600 ~/.pgpass

# ----------------------------------------------------------------------
# Final banner (truthful)
# ----------------------------------------------------------------------
if [[ "${INIT_OK}" == "true" && ( "$HOSTNAME" != "cdw" || db_up ) ]]; then
  echo """
===========================
=  DEPLOYMENT SUCCESSFUL  =
===========================
"""
else
  echo """
======================
=  DEPLOYMENT FAILED =
======================
"""
  # Keep the shell running for debugging, but non-zero exit helps CI
  # Comment out the 'exit 1' if you prefer success exit regardless.
  # exit 1
fi

# ----------------------------------------------------------------------
# Keep container alive for interactive use
# ----------------------------------------------------------------------
exec /bin/bash
