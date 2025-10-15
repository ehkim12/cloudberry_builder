#!/bin/bash
set -euo pipefail

# ===== 0) 패키지 =====
if command -v dnf >/dev/null 2>&1; then
  dnf -y install wget git gcc gcc-c++ make which tar unzip ca-certificates
  command -v curl >/dev/null 2>&1 || dnf -y install --allowerasing curl || true
else
  yum -y install wget git gcc gcc-c++ make which tar unzip ca-certificates
  command -v curl >/dev/null 2>&1 || yum -y install curl || true
fi
update-ca-trust || true


mkdir -p /opt
chown -R gpadmin:gpadmin /opt
echo 'export PATH=/opt/maven/bin:$PATH' > /etc/profile.d/maven.sh
chown -R gpadmin:gpadmin /etc/profile.d/maven.sh

export JAVA_HOME=/opt/java/jdk-11.0.13+8
export PATH="$JAVA_HOME/bin:$PATH"
cat >/etc/profile.d/java11.sh <<EOF
export JAVA_HOME=/opt/java/jdk-11.0.13+8
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
chown -R gpadmin:gpadmin /etc/profile.d/java11.sh

WORKDIR="/home/gpadmin/workspace"
export GPHOME=/usr/local/cloudberry-db
export PXF_HOME=/usr/local/pxf

mkdir -p "${WORKDIR}" ${PXF_HOME}

chown -R gpadmin:gpadmin /usr/local
chown -R gpadmin:gpadmin "${GPHOME}" "${PXF_HOME}" "${WORKDIR}"
