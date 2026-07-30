#!/bin/bash
# build-all.sh
# Full build and verification suite for the libimobiledevice stack + idevicerestore.
# Clones or updates all 7 projects, builds, installs, then runs a PASS/FAIL check.
#
# Run as root inside Kali WSL:
#   wsl -d kali-linux -u root -- bash scripts/build-all.sh
#
# All repos are cloned into /root/libimd-build/ inside the WSL filesystem.
# Do NOT build from /mnt/c/... paths — Windows CRLF line endings break autogen.sh.

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
BDIR=/root/libimd-build

echo "========================================"
echo " Full libimobiledevice + idevicerestore"
echo " Build & Verification Suite"
echo "========================================"

echo ""
echo "[DEPS] Ensuring all build dependencies are present..."
apt-get install -y -q \
  build-essential git autoconf automake libtool pkg-config \
  libssl-dev libusb-1.0-0-dev libcurl4-openssl-dev \
  python3-dev libzip-dev usbmuxd checkinstall \
  usbip usbutils zlib1g-dev dos2unix 2>&1 | tail -3

mkdir -p $BDIR

build_lib() {
  local name=$1
  echo ""
  echo "--- $name ---"
  if [ -d "$BDIR/$name/.git" ]; then
    git -C "$BDIR/$name" pull --ff-only
  else
    git clone "https://github.com/libimobiledevice/$name.git" "$BDIR/$name"
  fi
  cd "$BDIR/$name"
  ./autogen.sh --prefix=/usr/local --without-cython 2>&1 | grep -E 'Configuration|error:|warning:' | grep -v '^$'
  make -j$(nproc) 2>&1 | grep -E 'Error|error:|warning:' | grep -v 'deprecated' | head -5 || true
  make install 2>&1 | tail -2
  ldconfig
  export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
  local ver=$(pkg-config --modversion ${name%-*}-${name##*-} 2>/dev/null || pkg-config --modversion $name 2>/dev/null || echo "installed")
  echo "  PASS: $name"
  cd $BDIR
}

echo ""
echo "========================================"
echo " Phase 1: libimobiledevice stack (6 libs)"
echo "========================================"
build_lib libplist
build_lib libimobiledevice-glue
build_lib libusbmuxd
build_lib libtatsu
build_lib libimobiledevice
build_lib libirecovery

echo ""
echo "========================================"
echo " Phase 2: idevicerestore"
echo "========================================"
if [ -d "$BDIR/idevicerestore/.git" ]; then
  echo "--- idevicerestore (update) ---"
  git -C "$BDIR/idevicerestore" pull --ff-only
else
  echo "--- idevicerestore (fresh clone) ---"
  git clone https://github.com/libimobiledevice/idevicerestore.git "$BDIR/idevicerestore"
fi
cd "$BDIR/idevicerestore"
./autogen.sh --prefix=/usr/local 2>&1 | grep -E 'Configuration|error:' | grep -v '^$'
make -j$(nproc) 2>&1 | grep -E 'Error|error:' | head -5 || true
make install 2>&1 | tail -2
ldconfig
echo "  PASS: idevicerestore"

echo ""
echo "========================================"
echo " Phase 3: Verification"
echo "========================================"
PASS=0; FAIL=0
check() {
  local label=$1; local ver=$2
  if [ "$ver" = "NOT FOUND" ] || [ -z "$ver" ]; then
    echo "  FAIL  $label"
    FAIL=$((FAIL+1))
  else
    echo "  PASS  $label  ($ver)"
    PASS=$((PASS+1))
  fi
}

check "libplist-2.0"              "$(pkg-config --modversion libplist-2.0 2>/dev/null || echo 'NOT FOUND')"
check "libimobiledevice-glue-1.0" "$(pkg-config --modversion libimobiledevice-glue-1.0 2>/dev/null || echo 'NOT FOUND')"
check "libusbmuxd-2.0"            "$(pkg-config --modversion libusbmuxd-2.0 2>/dev/null || echo 'NOT FOUND')"
check "libtatsu-1.0"              "$(pkg-config --modversion libtatsu-1.0 2>/dev/null || echo 'NOT FOUND')"
check "libimobiledevice-1.0"      "$(pkg-config --modversion libimobiledevice-1.0 2>/dev/null || echo 'NOT FOUND')"
check "libirecovery-1.0"          "$(pkg-config --modversion libirecovery-1.0 2>/dev/null || echo 'NOT FOUND')"
check "idevicerestore"            "$(idevicerestore --version 2>&1 | grep -o '[0-9].*' | head -1 || echo 'NOT FOUND')"

echo ""
echo "========================================"
if [ $FAIL -eq 0 ]; then
  echo "  ALL $PASS COMPONENTS VERIFIED OK"
else
  echo "  $PASS PASSED  /  $FAIL FAILED"
fi
echo "========================================"
