# Execute Apache Cloudberry Cluster (Master Only)

This document explains how to execute and configure an Apache Cloudberry cluster based on the following nodes:

- **cdw**: master (coordinator)
- **sdw1, sdw2**: segment hosts
- **scdw**: standby coordinator

---

## Load Environment

```bash
sudo su - gpadmin
echo 'source /usr/local/cloudberry-db/greenplum_path.sh' >> ~/.bashrc
source ~/.bashrc
```

---

## Create gpinitsystem Configuration

```bash
cat >/tmp/gpinitsystem_multinode <<'EOF'
# A configuration file for gpinitsystem

################################################
# REQUIRED PARAMETERS
################################################

ARRAY_NAME="Sandbox: Apache Cloudberry Cluster"

# Must point to the host list file created above
MACHINE_LIST_FILE=/tmp/multinode-gpinit-hosts

SEG_PREFIX=gpseg

# Primary SQL port base (increments per content)
PORT_BASE=40000

# Primary data directories (one entry per primary per host)
declare -a DATA_DIRECTORY=(/data0/database/primary                            /data0/database/primary)

# Coordinator settings
COORDINATOR_HOSTNAME=cdw
COORDINATOR_DIRECTORY=/data0/database/coordinator
COORDINATOR_PORT=5432

TRUSTED_SHELL=ssh
CHECK_POINT_SEGMENTS=8
ENCODING=UNICODE

################################################
# OPTIONAL PARAMETERS
################################################

# Create this database after init
DATABASE_NAME=gpadmin

# Mirror configuration
MIRROR_PORT_BASE=50000
declare -a MIRROR_DATA_DIRECTORY=(/data0/database/mirror                                   /data0/database/mirror)

# Replication port bases (explicitly enable to avoid conflicts)
REPLICATION_PORT_BASE=41000
MIRROR_REPLICATION_PORT_BASE=51000
EOF
```

Create host file for segments:

```bash
cat >/tmp/multinode-gpinit-hosts <<'EOF'
sdw1
sdw2
EOF

sudo chown -R gpadmin.gpadmin  /tmp/gpinitsystem_multinode                               /tmp/multinode-gpinit-hosts
```

---

## SSH Preparation for Segments

```bash
# 0) Ensure Cloudberry environment
source /usr/local/cloudberry-db/greenplum_path.sh


echo 'gpadmin:gpadmin' | sudo chpasswd
# 1) Prepare gpadmin SSH key if missing
[[ -f ~/.ssh/id_ed25519 ]] || ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_ed25519
chmod 700 ~/.ssh
touch ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts

# 2) Seed known_hosts
ssh-keyscan -t ed25519 sdw1 sdw2 >> ~/.ssh/known_hosts 2>/dev/null || true
ssh-keyscan -t rsa    sdw1 sdw2 >> ~/.ssh/known_hosts 2>/dev/null || true

# 3) Copy key to segment nodes (requires password)
PASS="gpadmin"
for h in sdw1 sdw2; do
  sshpass -p "$PASS" ssh-copy-id -o StrictHostKeyChecking=no -f "gpadmin@${h}" || {
    echo "ERROR: ssh-copy-id to $h failed"; exit 1; }
  ssh -o BatchMode=yes "gpadmin@${h}" "echo ok from $h"
done
```

---

## Initialize Cluster

```bash
gpinitsystem -a \
  -c /tmp/gpinitsystem_multinode \
  -h /tmp/multinode-gpinit-hosts \
  --max_connections=100 \
  -S gpadmin
```

---

## Configure Access and Verify

```bash
# Allow all hosts access
echo 'host all all 0.0.0.0/0 trust' >> /data0/database/coordinator/gpseg-1/pg_hba.conf
gpstop -u

# Set gpadmin password and verify cluster
psql -d template1 -c "ALTER USER gpadmin PASSWORD 'cbdb@123'"

echo "Current time: $(date)"
source /etc/os-release
echo "OS Version: ${NAME} ${VERSION}"

psql -P pager=off -d template1 -c "SELECT VERSION()"
psql -P pager=off -d template1 -c "SELECT * FROM gp_segment_configuration ORDER BY dbid"
psql -P pager=off -d template1 -c "SHOW optimizer"
```

---

## Configure Standby Coordinator

```bash
# Seed known_hosts for standby
ssh-keyscan -t ed25519 scdw >> ~/.ssh/known_hosts 2>/dev/null || true
ssh-keyscan -t rsa    scdw >> ~/.ssh/known_hosts 2>/dev/null || true

# Copy key to standby
PASS="cbdb@123"
for h in scdw; do
  sshpass -p "$PASS" ssh-copy-id -o StrictHostKeyChecking=no -f "gpadmin@${h}" || {
    echo "ERROR: ssh-copy-id to $h failed"; exit 1; }
  ssh -o BatchMode=yes "gpadmin@${h}" "echo ok from $h"
done

# Initialize standby
gpinitstandby -s scdw -a
```
