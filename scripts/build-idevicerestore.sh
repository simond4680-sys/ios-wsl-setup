#!/bin/bash
# build-idevicerestore.sh
# Builds and installs idevicerestore from source inside the WSL filesystem.
#
# IMPORTANT: Do not run this from a Windows-cloned repo (/mnt/c/...).
# This script clones fresh into the WSL filesystem to avoid CRLF issues.
#
# Prerequisites: all libimobiledevice stack libraries must be installed first.
# Run scripts/build-libs.sh (or the equivalent) before this script.
#
# Usage: bash scripts/build-idevicerestore.sh

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH

DEST=/root/libimd-build/idevicerestore

echo "==> Checking prerequisites..."
for lib in libimobiledevice-1.0 libirecovery-1.0 libtatsu-1.0 libzip libcurl zlib; do
  if ! pkg-config --exists $lib 2>/dev/null; then
    echo "  ERROR: $lib not found. Build the libimobiledevice stack first."
    exit 1
  fi
  echo "  $lib: $(pkg-config --modversion $lib)"
done

echo ""
if [ -d "$DEST/.git" ]; then
  echo "==> Updating existing clone..."
  git -C "$DEST" pull
else
  echo "==> Cloning idevicerestore into WSL filesystem..."
  rm -rf "$DEST"
  git clone https://github.com/libimobiledevice/idevicerestore.git "$DEST"
fi

cd "$DEST"

echo ""
echo "==> Running autogen.sh..."
./autogen.sh --prefix=/usr/local

echo ""
echo "==> Building..."
make -j$(nproc)

echo ""
echo "==> Installing..."
make install
ldconfig

echo ""
echo "==> Done."
idevicerestore --version
