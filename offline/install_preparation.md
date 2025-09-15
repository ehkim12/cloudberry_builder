# Prepare Offline Installation for Apache Cloudberry

This document describes how to prepare an **offline installation bundle** for Apache Cloudberry on Rocky Linux.  
It collects all necessary RPMs, source packages, and build tools into `/tmp/cloudberry-offline`.  

---

## Preparation Script

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE=/tmp/cloudberry-offline
RPMS_DIR="$BASE/rpms"
SRC_DIR="$BASE/src"
mkdir -p "$RPMS_DIR" "$SRC_DIR"

# Basic tooling & cache
sudo dnf -y install dnf-plugins-core epel-release ca-certificates
sudo update-ca-trust || true
sudo dnf config-manager --set-enabled crb || true
sudo dnf clean all && sudo dnf -y makecache

# -----------------------------
# Package set
# -----------------------------
PKGS=(
  # tools & utilities
  sudo git golang rsync wget which curl
  iproute net-tools openssh-server
  glibc-langpack-en sshpass

  # toolchain
  gcc gcc-c++ cpp glibc-devel libgcc libgomp
  libstdc++ libstdc++-devel
  make pkgconf-pkg-config
  cmake cmake-data cmake-filesystem cmake-rpm-macros
  bison flex m4 diffutils

  # libs (+devel)
  openssl openssl-devel
  krb5-libs krb5-devel
  pam pam-devel
  openldap openldap-devel
  readline readline-devel
  zlib zlib-devel
  lz4 lz4-devel
  libzstd libzstd-devel
  libxml2 libxml2-devel
  libicu libicu-devel
  libevent libevent-devel
  libcurl-devel
  libuuid libuuid-devel
  apr-devel
  bzip2 bzip2-devel
  libuv-devel libyaml-devel perl-IPC-Run
  java-11-openjdk-devel

  # protobuf
  protobuf protobuf-compiler protobuf-devel

  # extras for pkg-config
  xz-devel ncurses-devel pcre2-devel keyutils-libs-devel libcom_err-devel   libselinux-devel libsepol-devel libverto-devel

  # python
  python3 python3-pip python3-devel python3-setuptools

  # keep Rocky libpq
  libpq libpq-devel postgresql-libs

  # perl
  perl perl-Env perl-ExtUtils-Embed perl-Test-Simple perl-devel
)

echo "[INFO] Downloading 'Development Tools' group..."
sudo dnf -y groupinstall "Development Tools"   --downloadonly --downloaddir="$RPMS_DIR" --setopt=install_weak_deps=False || true

echo "[INFO] Downloading named packages..."
sudo dnf -y download --resolve --downloaddir="$RPMS_DIR" "${PKGS[@]}"

# Quarantine conflicting RPMs
mkdir -p "$RPMS_DIR/_hold"
mv "$RPMS_DIR"/*.i686.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/libpq5-*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/glibc-*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/openssl-libs-*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/libcurl-*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/audit*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/iproute-*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/clang*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/llvm*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/libomp*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/gcc-toolset-*.rpm "$RPMS_DIR/_hold/" 2>/dev/null || true
mv "$RPMS_DIR"/git-core*.rpm "$RPMS_DIR"/perl-Git*.rpm "$RPMS_DIR"/git-core-doc*.rpm    "$RPMS_DIR/_hold/" 2>/dev/null || true

# Grab libcurl-devel explicitly
sudo dnf -y download --resolve --downloaddir="$RPMS_DIR"   libcurl-devel libcurl curl

echo "[INFO] Quarantined:"
ls -1 "$RPMS_DIR/_hold" || true

# Stage PyGreSQL
curl -fsSL -o "$SRC_DIR/PyGreSQL-5.2.4.tar.gz"   https://files.pythonhosted.org/packages/source/P/PyGreSQL/PyGreSQL-5.2.4.tar.gz

echo "[OK] All artifacts harvested under $BASE"
```

---

## Stage PyGreSQL Source

```bash
sudo dnf -y install libpq-devel postgresql-libs   # provides /usr/bin/pg_config
export PG_CONFIG=/usr/bin/pg_config

python3 -m pip download --no-binary=:all: --no-deps   -d /tmp/cloudberry-offline/src   'PyGreSQL==5.2.4'

cd /tmp/cloudberry-offline/src
sha256sum PyGreSQL-5.2.4.tar.gz > PyGreSQL-5.2.4.tar.gz.sha256
```

---

## Stage Xerces-C

```bash
#mkdir -p /tmp/cloudberry-offline/src

#curl -fsSL https://archive.apache.org/dist/xerces/c/3/sources/xerces-c-3.3.0.tar.gz   -o cloudberry-offline/src/xerces-c-3.3.0.tar.gz
# 1) Create the tar rooted at /
# stay in /usr/local/lib64
cd /usr/local/lib64

# make a tar with just what you need
sudo tar czf /tmp/cloudberry-offline/src/xerces-c-3.3.0-lib64.tar.gz \
  libxerces-c-3.3.so \
  libxerces-c.so \
  cmake/XercesC \
  pkgconfig/xerces-c.pc 2>/dev/null || true

# also grab headers from include/
cd /usr/local
sudo tar czf /tmp/cloudberry-offline/src/xerces-c-3.3.0-include.tar.gz include/xercesc
```

---

## Stage Cloudberry Source

```bash
cd /tmp
git clone --recurse-submodules https://github.com/apache/cloudberry.git
cd cloudberry
git fetch --tags
git checkout 2.0.0-incubating-rc3
cd ..
tar czf /tmp/cloudberry-offline/src/cloudberry-2.0.0-incubating-rc3-src.tar.gz cloudberry
```

---

## Build gpbackup/gprestore

```bash
curl -fsSL https://go.dev/dl/go1.22.5.linux-amd64.tar.gz   -o cloudberry-offline/src/go1.22.5.linux-amd64.tar.gz

mkdir -p /tmp/cloudberry-offline/bins
sudo dnf -y install golang

export GOPATH=/tmp/go
export GOBIN=$GOPATH/bin
export PATH=/usr/bin:/usr/local/go/bin:$GOBIN:$PATH
mkdir -p "$GOBIN"

rm -rf /tmp/gpbackup
git clone https://github.com/cloudberrydb/gpbackup.git /tmp/gpbackup
cd /tmp/gpbackup

make depend
make build

install -m 0755 "$GOBIN/gpbackup"  /tmp/cloudberry-offline/bins/gpbackup
install -m 0755 "$GOBIN/gprestore" /tmp/cloudberry-offline/bins/gprestore

/tmp/cloudberry-offline/bins/gpbackup --version
/tmp/cloudberry-offline/bins/gprestore --version
```

---

## Stage PXF

```bash
mkdir -p /tmp/cloudberry-offline/src /tmp/cloudberry-offline/cache

cd /tmp
rm -rf cloudberry-pxf
git clone --depth=1 https://github.com/apache/cloudberry-pxf.git
tar czf /tmp/cloudberry-offline/src/cloudberry-pxf-src.tar.gz cloudberry-pxf

# Warm Gradle cache
export GRADLE_USER_HOME=/tmp/cloudberry-offline/cache/gradle_home
mkdir -p "$GRADLE_USER_HOME"
cd /tmp/cloudberry-pxf
./gradlew -g "$GRADLE_USER_HOME" --no-daemon -x test assemble

# Warm Go module cache
export GOPATH=/tmp/cloudberry-offline/cache/pxf_gopath
export GOBIN=$GOPATH/bin
export GO111MODULE=on
mkdir -p "$GOBIN"
make -C /tmp/cloudberry-pxf/cli fmt deps || true

# Package caches
tar czf /tmp/cloudberry-offline/cache/gradle_home.tar.gz -C /tmp/cloudberry-offline/cache gradle_home
tar czf /tmp/cloudberry-offline/cache/pxf_gopath.tar.gz  -C /tmp/cloudberry-offline/cache pxf_gopath
```

---

## Stage pgvector

```bash
curl -fL -o /tmp/cloudberry-offline/src/pgvector-0.8.0.tar.gz   https://codeload.github.com/pgvector/pgvector/tar.gz/refs/tags/v0.8.0
```

---

## Package Offline Bundle

```bash
cd /tmp
tar czf cloudberry-offline.tar.gz cloudberry-offline
```
