#!/bin/bash
#set -euo pipefail

arch=$(uname -m)
case "$arch" in
  x86_64)   etcd_arch=amd64 ;;
  aarch64)  etcd_arch=arm64 ;;
  *) echo "Unsupported arch: $arch"; exit 1 ;;
esac

url="https://github.com/etcd-io/etcd/releases/download/v3.5.13/etcd-v3.5.13-linux-${etcd_arch}.tar.gz"

wget "$url"
tar xvf "etcd-v3.5.13-linux-${etcd_arch}.tar.gz"

sudo cp etcd-v3.5.13-linux-${etcd_arch}/etcd /usr/local/cloudberry-db/bin/
sudo cp etcd-v3.5.13-linux-${etcd_arch}/etcdctl /usr/local/cloudberry-db/bin/
sudo chmod +x /usr/local/cloudberry-db/bin/etcd /usr/local/cloudberry-db/bin/etcdctl

# Also link into /usr/local/bin so it's on PATH
sudo ln -sf /usr/local/cloudberry-db/bin/etcd /usr/local/bin/etcd
sudo ln -sf /usr/local/cloudberry-db/bin/etcdctl /usr/local/bin/etcdctl

rm -rf "etcd-v3.5.13-linux-${etcd_arch}" "etcd-v3.5.13-linux-${etcd_arch}.tar.gz"
