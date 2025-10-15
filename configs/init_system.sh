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
                              /tmp/gp_bash_functions.sh \
                              /tmp/gpinitsystem \
                              /tmp/gpstop \
                              /tmp/gpstart \
                              /tmp/mainUtils.py \
                              /tmp/smoke-test.sh


cp /tmp/gpinitsystem /usr/local/cloudberry-db/bin/gpinitsystem

cp /tmp/gpstop /usr/local/cloudberry-db/bin/gpstop

cp /tmp/gpstart /usr/local/cloudberry-db/bin/gpstart

cp /tmp/gp_bash_functions.sh /usr/local/cloudberry-db/bin/lib/gp_bash_functions.sh

cp /tmp/mainUtils.py /usr/local/cloudberry-db/lib/python/gppylib/mainUtils.py

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

# Source Cloudberry environment variables and set
# COORDINATOR_DATA_DIRECTORY
source /usr/local/cloudberry-db/greenplum_path.sh
export COORDINATOR_DATA_DIRECTORY=/data0/database/coordinator/gpseg-1

export PGPORT=5432
echo 'export PGPORT=5432' >> ~/.bashrc
source ~/.bashrc

mkdir -p /data0/database/coordinator /data0/database/primary /data0/database/mirror && \
        chown -R gpadmin:gpadmin /data0

# Set ownership of entire CloudBerry DB installation directory to gpadmin
sudo chown -R gpadmin:gpadmin /usr/local/cloudberry-db &&
sudo chmod 755 /usr/local/cloudberry-db/bin/* &&
ls -l /usr/local/cloudberry-db/bin/gpinitsystem


# Initialize single node Cloudberry cluster
if [[ $MULTINODE == "false" && $HOSTNAME == "cdw" ]]; then
    gpinitsystem -a \
                 -c /tmp/gpinitsystem_singlenode \
                 -h /tmp/gpdb-hosts \
                 --max_connections=100
# Initialize multi node Cloudberry cluster
elif [[ $MULTINODE == "true" && $HOSTNAME == "cdw" ]]; then
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no sdw1
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no sdw2
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no scdw
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no etcd1
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no etcd2
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no etcd3

    # Prevent automatic FTS startup on segment hosts
   export SKIP_FTS_CHECK=1
   
   gpinitsystem -a \
                -c /tmp/gpinitsystem_multinode \
                -h /tmp/multinode-gpinit-hosts \
                --max_connections=100 \
                -E /tmp/etcd_service.conf \
                -F /tmp/gpdb_all_hosts \
                -p /tmp/cbdb_etcd.conf \
                -U 1


    gpconfig -c hot_standby -v on
    gpconfig -c wal_level -v replica
    gpconfig -c max_wal_senders -v 16

    
    gpinitstandby -s scdw -a
    printf "sdw1\nsdw2\n" >> /tmp/gpdb-hosts
    
    # Kill any FTS processes on segment hosts first
    echo "Cleaning up FTS processes on segment hosts..."
    gpssh -f /tmp/multinode-gpinit-hosts -e "pkill -f gpfts" || true
    
    # Start FTS only on coordinator (cdw) - not on other hosts
    if [ "$HOSTNAME" == "cdw" ]; then
        echo "Starting FTS only on coordinator (cdw)..."
        mkdir -p /home/gpadmin/gpAdminLogs/fts
        nohup $GPHOME/bin/gpfts -F /tmp/cbdb_etcd.conf -d /home/gpadmin/gpAdminLogs/fts > /home/gpadmin/gpAdminLogs/fts/gpfts.log 2>&1 &
        sleep 5
        echo "FTS started on cdw"
    fi

    gpstate

elif [[ $HOSTNAME == "scdw" ]]; then
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no sdw1
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no sdw2
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no cdw
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no etcd1
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no etcd2
    sshpass -p "cbdb@123" ssh-copy-id -o StrictHostKeyChecking=no etcd3
fi

if [ $HOSTNAME == "cdw" ]; then
     ## Allow any host access the Cloudberry Cluster
     echo 'host all all 0.0.0.0/0 trust' >> /data0/database/coordinator/gpseg-1/pg_hba.conf
     gpstop -u

     psql -d template1 \
          -c "ALTER USER gpadmin PASSWORD 'cbdb@123'"

     cat <<-'EOF'

======================================================================
	  ____ _                 _ _                          
	 / ___| | ___  _   _  __| | |__   ___ _ __ _ __ _   _  
	| |   | |/ _ \| | | |/ _` | '_ \ / _ \ '__| '__| | | |
	| |___| | (_) | |_| | (_| | |_) |  __/ |  | |  | |_| |
	 \____|_|\___/ \__,_|\__,_|_.__/ \___|_|  |_|   \__, |
	                                                |___/
======================================================================
EOF

     cat <<-'EOF'

======================================================================
Sandbox: Apache Cloudberry Cluster details
======================================================================

EOF

     echo "Current time: $(date)"
     source /etc/os-release
     echo "OS Version: ${NAME} ${VERSION}"

     ## Set gpadmin password, display version and cluster configuration
     psql -P pager=off -d template1 -c "SELECT VERSION()"
     psql -P pager=off -d template1 -c "SELECT * FROM gp_segment_configuration ORDER BY dbid"
     psql -P pager=off -d template1 -c "SHOW optimizer"
fi

cat > ~/.pgpass <<EOF
localhost:5432:*:gpadmin:cbdb@123
127.0.0.1:5432:*:gpadmin:cbdb@123
cdw:5432:*:gpadmin:cbdb@123
scdw:5432:*:gpadmin:cbdb@123
sdw1:5432:*:gpadmin:cbdb@123
sdw2:5432:*:gpadmin:cbdb@123
EOF

chmod 600 ~/.pgpass


if [ $HOSTNAME == "cdw" ]; then
    gpconfig -c gp_fts_probe_timeout -v 20 --coordinatoronly
    psql -d postgres -c "SELECT gp_request_fts_probe_scan();"
    #sleep 60
    #mkdir -p /home/gpadmin/gpAdminLogs/fts && nohup $GPHOME/bin/gpfts -F /tmp/cbdb_etcd.conf -d /home/gpadmin/gpAdminLogs/fts > /home/gpadmin/gpAdminLogs/fts/gpfts.log 2>&1 &
fi




echo """
===========================
=  DEPLOYMENT SUCCESSFUL  =
===========================
"""

# ----------------------------------------------------------------------
# Start an interactive bash shell
# ----------------------------------------------------------------------
# Finally, the script starts an interactive bash shell to keep the
# container running and allow the user to interact with the environment.
# ----------------------------------------------------------------------
/bin/bash
