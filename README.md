# iOS Device Access via WSL — Setup Guide

End-to-end setup for communicating with iOS devices from Kali Linux running under
WSL2 on Windows, using the libimobiledevice stack and usbipd-win.

---

## Environment

| Component         | Version / Detail                          |
|-------------------|-------------------------------------------|
| Host OS           | Windows 11                                |
| WSL Distribution  | Kali Linux Rolling (WSL2)                 |
| WSL Kernel        | 6.18.35.2-microsoft-standard-WSL2         |
| usbipd-win        | 5.3.0                                     |

---

## Installed Libraries

All libraries built from source (GitHub `libimobiledevice` org) and installed to `/usr/local`.

| Library                    | Version               |
|----------------------------|-----------------------|
| libplist-2.0               | 2.7.0-66-g32428ab     |
| libimobiledevice-glue-1.0  | 1.3.2-5-gda770a7      |
| libusbmuxd-2.0             | 2.1.1-2-g93eb168      |
| libtatsu-1.0               | 1.0.5-3-g60a39f3      |
| libimobiledevice-1.0       | 1.4.0-9-gfa0f791      |
| libirecovery-1.0           | 1.3.1-5-g04d04f7      |
| **idevicerestore**         | **1.0.0-271-g45145e9** |

---

## Part 1 — Kali WSL Setup

### 1.1 Install Kali Linux via WSL

From an elevated PowerShell prompt:

```powershell
wsl --install -d kali-linux --no-launch
```

### 1.2 Enable systemd

Systemd is required for proper service management (usbmuxd, etc.).

```bash
# Inside Kali WSL as root
printf '[boot]\nsystemd=true\n' > /etc/wsl.conf
```

Then restart WSL from PowerShell:

```powershell
wsl --shutdown
```

Verify systemd is PID 1 after restart:

```bash
ps -p 1 -o comm=   # should output: systemd
```

---

## Part 2 — Build libimobiledevice Stack

### 2.1 Install build dependencies

```bash
sudo apt-get update && sudo apt-get install -y \
  build-essential git autoconf automake libtool pkg-config \
  libssl-dev libusb-1.0-0-dev libcurl4-openssl-dev \
  python3-dev libzip-dev usbmuxd checkinstall \
  usbip usbutils zlib1g-dev dos2unix
```

### 2.2 Build script

> **Critical:** `libtatsu` must be built before `libimobiledevice`.
> The correct dependency order is shown below.

Save as `~/build-libs.sh` and run with `bash ~/build-libs.sh`:

```bash
#!/bin/bash
set -e
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH

BDIR=/root/libimd-build
mkdir -p $BDIR

build_lib() {
  local name=$1
  echo "==> Building: $name"
  if [ -d "$BDIR/$name" ]; then
    git -C "$BDIR/$name" pull
  else
    git clone "https://github.com/libimobiledevice/$name.git" "$BDIR/$name"
  fi
  cd "$BDIR/$name"
  ./autogen.sh --prefix=/usr/local --without-cython
  make -j$(nproc)
  make install
  ldconfig
  export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
  echo "==> $name: INSTALLED"
  cd $BDIR
}

build_lib libplist
build_lib libimobiledevice-glue
build_lib libusbmuxd
build_lib libtatsu              # must come before libimobiledevice
build_lib libimobiledevice
build_lib libirecovery
```

### 2.3 Make pkg-config path permanent

```bash
echo 'export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"' >> ~/.bashrc
```

### 2.4 Verify installations

```bash
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
for lib in libplist-2.0 libimobiledevice-glue-1.0 libusbmuxd-2.0 \
           libtatsu-1.0 libimobiledevice-1.0 libirecovery-1.0; do
  printf "%-35s %s\n" "$lib" "$(pkg-config --modversion $lib 2>/dev/null || echo NOT FOUND)"
done
```

---

## Part 3 — usbipd-win Setup (Windows)

### 3.1 Install usbipd-win

From PowerShell:

```powershell
winget install --exact --id dorssel.usbipd-win --accept-source-agreements --accept-package-agreements
```

Or download the `.msi` from: https://github.com/dorssel/usbipd-win/releases

> Open a new PowerShell window after install so `usbipd` is on PATH.

---

## Part 4 — Connecting an iOS Device

### 4.1 One-time: bind the device (Admin PowerShell)

```powershell
# List devices — note the BUSID of the Apple device
usbipd list

# Bind (makes device shareable; survives reboots)
# Use --force if Apple Mobile Device Service holds the USB handle
usbipd bind --busid <BUSID> --force
```

### 4.2 Each session: attach to WSL

The Apple Mobile Device Service on Windows will reclaim the device on each
reconnect. Stop it before attaching:

```powershell
Stop-Service -Name "Apple Mobile Device Service" -Force
usbipd attach --wsl --busid <BUSID>
```

### 4.3 Start usbmuxd and verify in WSL

```bash
# Confirm device is visible at the USB layer
lsusb | grep -i apple

# Start usbmuxd (restart if already running)
pkill usbmuxd 2>/dev/null; sleep 1 && usbmuxd

# List device UDID
idevice_id -l

# Query full device info
ideviceinfo
```

### 4.4 Detach when done

```powershell
usbipd detach --busid <BUSID>
```

---

## Part 5 — Convenience Script

`scripts/connect-ios.ps1` automates the full attach workflow:
scan → bind → stop AMDS → attach → start usbmuxd → verify.

```powershell
# Auto-detect Apple device
.\scripts\connect-ios.ps1

# Specify BUSID manually
.\scripts\connect-ios.ps1 -BusId 2-1
```

---

## Part 6 — Building idevicerestore

`idevicerestore` restores firmware images (IPSW files) to iOS devices.
It depends on all 6 libraries built in Part 2.

### 6.1 Important: clone into WSL filesystem

> **Do NOT clone on Windows and build from `/mnt/c/...`.**
> Repos cloned on Windows have CRLF line endings. The `autogen.sh` shebang
> becomes `/bin/sh^M` inside WSL, causing: `bad interpreter: No such file or directory`.
> Always clone directly inside the WSL filesystem.

### 6.2 Build

Use `scripts/build-idevicerestore.sh`, or run manually:

```bash
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH

git clone https://github.com/libimobiledevice/idevicerestore.git \
  /root/libimd-build/idevicerestore
cd /root/libimd-build/idevicerestore

./autogen.sh --prefix=/usr/local
make -j$(nproc)
make install
ldconfig
```

### 6.3 Verify

```bash
idevicerestore --version
# idevicerestore 1.0.0-271-g45145e9 (libirecovery 1.3.1-5-g04d04f7, libtatsu 1.0.5-3-g60a39f3)
```

### 6.4 Basic usage

```bash
# List connected device in normal/recovery mode
idevicerestore -l

# Restore a firmware image (will erase the device)
idevicerestore -d /path/to/firmware.ipsw

# Restore with update (preserve data where possible)
idevicerestore -u /path/to/firmware.ipsw

# Erase + restore
idevicerestore -e /path/to/firmware.ipsw
```

> Device must be in **DFU** or **Recovery** mode for a restore.
> To enter DFU mode, follow the button sequence for your device model.

---

## Architecture Overview

```
iPhone / iPad  (USB cable)
      │
      ▼
Windows USB stack
      │  usbipd bind --busid <ID> --force     (one-time setup)
      │  Stop-Service "Apple Mobile Device Service"
      │  usbipd attach --wsl --busid <ID>      (each session)
      ▼
WSL2 virtual USB bus  (/dev/bus/usb/...)
      │  usbmuxd                               (start after attach)
      ▼
Unix socket: /var/run/usbmuxd
      │
      ▼
libimobiledevice tools
  idevice_id, ideviceinfo, idevicebackup2, idevicerestore ...
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `usbipd attach` → "Device busy (exported)" | Run `Stop-Service "Apple Mobile Device Service" -Force` then retry |
| `usbipd attach` → "No WSL 2 distribution running" | Run `wsl -d kali-linux -- echo ok` first to wake WSL, then attach |
| `idevice_id -l` returns nothing | Run `pkill usbmuxd; usbmuxd` then wait 2s and retry |
| `ideviceinfo` → "No device found" | Unplug and replug, re-attach with usbipd, tap **Trust** on device |
| Libraries show `NOT FOUND` in pkg-config | `export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig` |
| Force-bind warns "reboot may be required" | Replug the iOS device after binding |
| `autogen.sh` → `bad interpreter: /bin/sh^M` | Repo was cloned on Windows; clone inside WSL instead (see Part 6.1) |
| `idevicerestore` → `PACKAGE_VERSION is not defined` | Same CRLF issue; clone inside WSL, not from `/mnt/c/...` |

---

## Build Artifacts

| Path | Contents |
|------|----------|
| `/root/libimd-build/` | Source trees for all 7 projects |
| `/usr/local/lib/` | Installed `.so` shared libraries |
| `/usr/local/include/` | Header files |
| `/usr/local/lib/pkgconfig/` | `.pc` files for pkg-config |
| `/usr/local/bin/` | Tools: `idevice_id`, `ideviceinfo`, `iproxy`, `inetcat`, `irecovery`, `idevicerestore`, `plistutil` |
| `scripts/connect-ios.ps1` | iOS attach convenience script (Windows) |
| `scripts/build-idevicerestore.sh` | idevicerestore build script (WSL) |
