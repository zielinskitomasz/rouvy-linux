# Make the passed-through Bluetooth adapter work. Windows Update usually brings a driver on its
# own shortly after the adapter shows up; when it has not, the vendor packages on the share are
# installed. Exit codes: 0 adapter works, 1 still broken, 3 nothing to install from.
param([string]$UsbId, [switch]$Force, [string]$DriverDir)
if (-not $UsbId) { 'usage: bt-driver.ps1 -UsbId vendor:product [-Force] [-DriverDir path]'; exit 1 }
if (-not $DriverDir) { $DriverDir = Join-Path $PSScriptRoot 'drivers' }
$vid, $prod = $UsbId.ToUpper().Split(':')
$instance = "USB\VID_$vid&PID_$prod*"

function Get-Adapter { Get-PnpDevice -PresentOnly -InstanceId $instance -ErrorAction SilentlyContinue | Select-Object -First 1 }

function Wait-Adapter([int]$Seconds, [switch]$Working) {
    for ($i = 0; $i -lt $Seconds; $i += 2) {
        $dev = Get-Adapter
        if ($dev -and (-not $Working -or $dev.Status -eq 'OK')) { return $dev }
        Start-Sleep 2
    }
    Get-Adapter
}

# Right after the hand-over Windows is still enumerating the device.
$dev = Wait-Adapter 30
if (-not $dev) { "bluetooth: adapter $UsbId is not visible in Windows"; exit 1 }
if ($dev.Status -ne 'OK') { $dev = Wait-Adapter 20 -Working }
if ($dev.Status -eq 'OK' -and -not $Force) { "bluetooth: $($dev.FriendlyName) OK"; exit 0 }

$packages = @(Get-ChildItem -LiteralPath $DriverDir -Filter *.exe -ErrorAction SilentlyContinue)
if (-not $packages) { "bluetooth: '$($dev.FriendlyName)' reports $($dev.Status) and $DriverDir has no driver installer"; exit 3 }

foreach ($package in $packages) {
    $sig = Get-AuthenticodeSignature -LiteralPath $package.FullName
    if ($sig.Status -ne 'Valid') { "skipping $($package.Name), signature is $($sig.Status)"; continue }
    $local = "C:\OEM\$($package.Name)"
    Copy-Item -LiteralPath $package.FullName -Destination $local -Force
    $p = Start-Process -FilePath $local -ArgumentList '/quiet', '/norestart' -Wait -PassThru
    "$($package.Name) (signed by $($sig.SignerCertificate.GetNameInfo('SimpleName', $false))): exit code $($p.ExitCode)"
}

pnputil /scan-devices | Out-Null
$dev = Wait-Adapter 60 -Working
if ($dev.Status -eq 'OK') { "bluetooth: $($dev.FriendlyName) OK"; exit 0 }
"bluetooth: '$($dev.FriendlyName)' still reports $($dev.Status)"
exit 1
