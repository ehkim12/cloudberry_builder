#!/bin/bash

#!/bin/bash
## ======================================================================
## Container initialization script
## ======================================================================

# ----------------------------------------------------------------------
# Start SSH daemon and setup for SSH access
# ----------------------------------------------------------------------
# The SSH daemon is started to allow remote access to the container via
# SSH. This is useful for development and debugging purposes. If the SSH
# daemon fails to start, the script exits with an error.
# ----------------------------------------------------------------------
if ! sudo /usr/sbin/sshd; then
    echo "Failed to start SSH daemon" >&2
    exit 1
fi

# ----------------------------------------------------------------------
# Remove /run/nologin to allow logins
# ----------------------------------------------------------------------
# The /run/nologin file, if present, prevents users from logging into
# the system. This file is removed to ensure that users can log in via SSH.
# ----------------------------------------------------------------------
sudo rm -rf /run/nologin

# ## Set gpadmin ownership - Clouberry install directory and supporting
# ## cluster creation files.
sudo chown -R gpadmin.gpadmin /usr/local/cloudberry-db \
                              /tmp/gpinitsystem_singlenode \
                              /tmp/gpinitsystem_multinode \
                              /tmp/gpdb-hosts \
                              /tmp/multinode-gpinit-hosts \
                              /tmp/faa.tar.gz \
                              /tmp/smoke-test.sh

# ----------------------------------------------------------------------
# Configure passwordless SSH access for 'gpadmin' user
# ----------------------------------------------------------------------
# The script sets up SSH key-based authentication for the 'gpadmin' user,
# allowing passwordless SSH access. It generates a new SSH key pair if one
# does not already exist, and configures the necessary permissions.
# ----------------------------------------------------------------------
mkdir -p /home/gpadmin/.ssh
chmod 700 /home/gpadmin/.ssh

if [ ! -f /home/gpadmin/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -C gpadmin -f /home/gpadmin/.ssh/id_rsa -P "" > /dev/null 2>&1
fi

cat /home/gpadmin/.ssh/id_rsa.pub >> /home/gpadmin/.ssh/authorized_keys
chmod 600 /home/gpadmin/.ssh/authorized_keys

# Add the container's hostname to the known_hosts file to avoid SSH warnings
ssh-keyscan -t rsa cdw > /home/gpadmin/.ssh/known_hosts 2>/dev/null

# prometheus 메트릭 수집을 위해 etcd 설정
echo 'export ETCD_LISTEN_METRICS_URLS="http://0.0.0.0:2381"' >> ~/.bashrc

# Start etcd with proper configuration
HOSTNAME=$(hostname)
sudo mkdir -p /var/lib/etcd
sudo chown gpadmin:gpadmin /var/lib/etcd

# Clear conflicting environment variables to avoid shadowing command-line flags
unset ETCD_INITIAL_CLUSTER
unset ETCD_INITIAL_CLUSTER_STATE
unset ETCD_INITIAL_CLUSTER_TOKEN

# Start etcd in background using command-line flags only
/usr/local/cloudberry-db/bin/etcd \
  --name $HOSTNAME \
  --data-dir /var/lib/etcd \
  --listen-peer-urls http://0.0.0.0:2380 \
  --listen-client-urls http://0.0.0.0:2379 \
  --initial-advertise-peer-urls http://$HOSTNAME:2380 \
  --advertise-client-urls http://$HOSTNAME:2379 \
  --initial-cluster "etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380" \
  --initial-cluster-state "new" \
  --initial-cluster-token "tutorial" \
  --listen-metrics-urls http://0.0.0.0:2381 &

# Wait for etcd to start
sleep 5




  
# ----------------------------------------------------------------------
# Start an interactive bash shell
# ----------------------------------------------------------------------
# Finally, the script starts an interactive bash shell to keep the
# container running and allow the user to interact with the environment.
# ----------------------------------------------------------------------
tail -f /dev/null
