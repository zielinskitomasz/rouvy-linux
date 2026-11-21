# Install or upgrade Rouvy silently from an installer on the share.
# Exit codes: 0 installed or already current, 1 failed, 2 no usable installer.
param([string]$Installer, [switch]$Force)
$ErrorActionPreference = 'Stop'
if (-not $Installer) { $Installer = Join-Path $PSScriptRoot 'rouvy\Rouvy_Installer.exe' }
$exe = 'C:\Program Files\VirtualTraining\Rouvy\Rouvy.exe'

if (-not (Test-Path -LiteralPath $Installer)) { "no installer at $Installer"; exit 2 }
$sig = Get-AuthenticodeSignature -LiteralPath $Installer
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=VirtualTraining s\.r\.o\.') {
    "refusing $Installer, signature is $($sig.Status) by '$($sig.SignerCertificate.Subject)'"
    exit 2
}

$new = [version](Get-Item -LiteralPath $Installer).VersionInfo.ProductVersion
$current = $null
if (Test-Path $exe) { $current = [version](Get-Item $exe).VersionInfo.ProductVersion }
if ($current -and $new -le $current -and -not $Force) { "Rouvy $current is up to date"; exit 0 }

Get-Process Rouvy_Installer, Rouvy, UnityCrashHandler64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2

# The installer must run from a local, normally labelled folder (see the note below).
$local = 'C:\OEM\Rouvy_Installer.exe'
Copy-Item -LiteralPath $Installer -Destination $local -Force
$p = Start-Process -FilePath $local -ArgumentList '/S' -PassThru
$null = $p.Handle
if (-not $p.WaitForExit(900000)) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    'the installer did not finish within 15 minutes'
    exit 1
}
if ($p.ExitCode -ne 0) { "the installer failed with exit code $($p.ExitCode)"; exit 1 }

# Rouvy downloads its own updates into LocalLow, which carries a Low integrity label. UAC is off
# in this VM, so nothing elevates the downloaded installer and it starts at Low integrity, cannot
# write to any temp folder and dies with "NSIS Error: Error writing temporary file". A Medium
# label on the download folder makes new files there start like any other program.
$data = Join-Path $env:USERPROFILE 'AppData\LocalLow\VirtualTraining\ROUVY\data'
New-Item -ItemType Directory -Path $data -Force | Out-Null
icacls $data /setintegritylevel '(OI)(CI)M' | Out-Null
$stale = Join-Path $data 'Rouvy_Installer.exe'
if (Test-Path -LiteralPath $stale) { icacls $stale /setintegritylevel M | Out-Null }

"Rouvy $((Get-Item $exe).VersionInfo.ProductVersion) installed" + $(if ($current) { " (was $current)" })
