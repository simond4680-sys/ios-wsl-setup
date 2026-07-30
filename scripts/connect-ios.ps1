# connect-ios.ps1
# Attaches an iOS device from Windows to WSL Kali and starts usbmuxd
# Usage: .\connect-ios.ps1          (auto-detects Apple device)
#        .\connect-ios.ps1 -BusId 1-3   (specify BUSID manually)

param(
    [string]$BusId = ""
)

$usbipd = "usbipd"

# --- Step 1: List devices and find Apple device ---
Write-Host "`n[1/4] Scanning USB devices..." -ForegroundColor Cyan
$list = & $usbipd list 2>&1
$list | Write-Host

if (-not $BusId) {
    # Auto-detect first Apple device
    $appleLine = $list | Where-Object { $_ -match "Apple" } | Select-Object -First 1
    if ($appleLine -match "^(\S+-\S+)") {
        $BusId = $Matches[1]
        Write-Host "  -> Auto-detected Apple device at BUSID: $BusId" -ForegroundColor Green
    } else {
        Write-Host "  ERROR: No Apple device found. Plug in your iOS device and retry." -ForegroundColor Red
        exit 1
    }
}

# --- Step 2: Bind (make shareable) ---
Write-Host "`n[2/4] Binding BUSID $BusId (may prompt for admin)..." -ForegroundColor Cyan
$bindResult = & $usbipd bind --busid $BusId 2>&1
if ($LASTEXITCODE -ne 0 -and $bindResult -notmatch "already") {
    Write-Host "  NOTE: $bindResult" -ForegroundColor Yellow
    Write-Host "  If bind failed with access denied, re-run this script as Administrator." -ForegroundColor Yellow
}

# --- Step 3: Attach to WSL ---
Write-Host "`n[3/4] Attaching BUSID $BusId to kali-linux WSL..." -ForegroundColor Cyan
& $usbipd attach --wsl --busid $BusId
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Attach failed. Is WSL running? Try: wsl -d kali-linux -- echo ok" -ForegroundColor Red
    exit 1
}
Write-Host "  -> Device attached. If prompted on your iPhone, tap [Trust]." -ForegroundColor Green
Start-Sleep -Seconds 2

# --- Step 4: Start usbmuxd and verify in WSL ---
Write-Host "`n[4/4] Starting usbmuxd and checking for device in WSL..." -ForegroundColor Cyan
wsl -d kali-linux -u root -- bash -c @"
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Restart usbmuxd cleanly
pkill usbmuxd 2>/dev/null; sleep 1
usbmuxd
sleep 2

echo ''
echo '--- USB devices visible in WSL ---'
lsusb | grep -i apple || echo '  (no Apple device found at USB layer - check usbipd attach)'

echo ''
echo '--- Connected iOS devices (via idevice_id) ---'
idevice_id -l || echo '  (no devices listed - tap Trust on your iPhone if prompted)'
"@

Write-Host "`nDone. To detach when finished:" -ForegroundColor Cyan
Write-Host "  usbipd detach --busid $BusId" -ForegroundColor White
