# Install Apache Cloudberry with Rocky Linux 9.6

This document guides you on how to quickly set up and connect to Apache Cloudberry in a VM environment.

---

## Install Offline Packages

```bash
cd /tmp
tar xzf cloudberry-offline.tar.gz

#install sudo
cd /tmp/cloudberry-offline/rpms
dnf install -y ./sudo-*.rpm --disablerepo='*'

sudo dnf install -y ./*.rpm --skip-broken
```

---

## Build Dependencies (xerces-c)

```bash
# 1) Extract to /
# headers
sudo tar xzf /tmp/cloudberry-offline/src/xerces-c-3.3.0-include.tar.gz -C /usr/local

# libs, cmake config, pkgconfig
sudo tar xzf /tmp/cloudberry-offline/src/xerces-c-3.3.0-lib64.tar.gz -C /usr/local/lib64



# 3) Make sure the dynamic linker sees /usr/local (one-time)
echo -e "/usr/local/lib\n/usr/local/lib64" | sudo tee /etc/ld.so.conf.d/local-local.conf >/dev/null
sudo ldconfig

# 4) Quick checks
ldconfig -p | grep -i xerces || true
ls -l /usr/local/lib64/libxerces-c* || true

```

---

## Create User and Directories

```bash
sudo groupadd -f gpadmin
id gpadmin >/dev/null 2>&1 || sudo useradd -g gpadmin -G wheel gpadmin
echo "gpadmin ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-gpadmin >/dev/null
sudo chmod 0440 /etc/sudoers.d/99-gpadmin

sudo mkdir -p /data0/database/{coordinator,primary,mirror}
sudo chown -R gpadmin:gpadmin /data0
```

Switch to `gpadmin`:

```bash
sudo su - gpadmin
```

---

## Environment Setup

```bash
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk' >> ~/.bashrc
echo 'export GPHOME=/usr/local/cloudberry-db' >> ~/.bashrc
echo 'export PXF_HOME=/usr/local/pxf' >> ~/.bashrc
echo 'export PXF_BASE=/home/gpadmin/pxf-base' >> ~/.bashrc
echo 'export PG_CONFIG=$GPHOME/bin/pg_config' >> ~/.bashrc
echo 'export GOPATH=/tmp/pxf-cache/pxf_gopath' >> ~/.bashrc
echo 'export GOBIN=$GOPATH/bin' >> ~/.bashrc
source ~/.bashrc
```

---

## Install Cloudberry

```bash
sudo tar xzf /tmp/cloudberry-offline/src/cloudberry-db.tar.gz  -C /usr/local
```
Set environment for gpadmin:

```bash
echo 'source /usr/local/cloudberry-db/greenplum_path.sh' | sudo tee -a /home/gpadmin/.bashrc >/dev/null
echo 'export COORDINATOR_DATA_DIRECTORY=/data0/database/coordinator/gpseg-1' | sudo tee -a /home/gpadmin/.bashrc >/dev/null
sudo chown gpadmin:gpadmin /home/gpadmin/.bashrc
```





## Backup Tools

```bash
sudo install -m 0755 /tmp/cloudberry-offline/bins/gpbackup  /usr/local/bin/gpbackup
sudo install -m 0755 /tmp/cloudberry-offline/bins/gprestore /usr/local/bin/gprestore

gpbackup --version || true
gprestore --version || true
```

---



## Install Extensions


### pgvector

```bash
export GPHOME=/usr/local/cloudberry-db
export PATH="$GPHOME/bin:$PATH"
export PG_CONFIG="$GPHOME/bin/pg_config"

tar xzf /tmp/cloudberry-offline/src/pgvector-0.8.0.tar.gz -C /tmp
cd /tmp/pgvector-0.8.0

make USE_PGXS=1 PG_CONFIG="$PG_CONFIG" -j"$(nproc)"
sudo make USE_PGXS=1 PG_CONFIG="$PG_CONFIG" install
```


### PXF

```bash
sudo tar xzf /tmp/cloudberry-offline/src/pxf.tar.gz -C /usr/local
chown -R gpadmin:gpadmin /usr/local/pxf

# add PXF to PATH persistently
grep -q "PXF_HOME=" ~/.bashrc || echo "export PXF_HOME=$PXF_HOME" >> ~/.bashrc
grep -q "PATH=.*\$PXF_HOME/bin" ~/.bashrc || echo "export PATH=\$PXF_HOME/bin:\$PATH" >> ~/.bashrc


# === new shell for gpadmin to pick up PATH (or run source ~/.bashrc) ===

source ~/.bashrc || true
pxf version || true

# initialize and start PXF (single-node)
pxf cluster init || true
pxf cluster start || true
pxf status || true
```



## Install Pygresql

```bash
#extra python3 module (PyGreSQL-5.2.4)
tar xzf /tmp/cloudberry-offline/src/PyGreSQL-5.2.4.tar.gz
cd PyGreSQL-5.2.4

python3 setup.py build
python3 setup.py install --user


# Fallback only if the RPM isn't present:
if ! python3 -c 'import psutil' 2>/dev/null; then
  python3 -m pip install --user --no-index --find-links /tmp/cloudberry-offline/src psutil
fi

```




## SSH Setup

```bash
if ! sudo /usr/sbin/sshd; then
    echo "Failed to start SSH daemon" >&2
    exit 1
fi

sudo rm -rf /run/nologin
sudo chown -R gpadmin.gpadmin /usr/local/cloudberry-db

mkdir -p /home/gpadmin/.ssh
chmod 700 /home/gpadmin/.ssh

if [ ! -f /home/gpadmin/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -C gpadmin -f /home/gpadmin/.ssh/id_rsa -P "" > /dev/null 2>&1
fi

cat /home/gpadmin/.ssh/id_rsa.pub >> /home/gpadmin/.ssh/authorized_keys
chmod 600 /home/gpadmin/.ssh/authorized_keys

ssh-keyscan -t rsa cdw > /home/gpadmin/.ssh/known_hosts 2>/dev/null
```
## Appendix: Docker Option

If you want to test Cloudberry in Docker instead of a VM, see the [Install Apache Cloudberry with Docker](README.md) guide.
