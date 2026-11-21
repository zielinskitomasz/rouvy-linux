# One-shot provisioning. C:\OEM\install.bat copies this file from the share and runs it once,
# at the end of the unattended Windows setup.
$ErrorActionPreference = 'Continue'
$Share = '\\host.lan\Data\setup'
Start-Transcript -Path 'C:\OEM\setup.log' -Append | Out-Null

function Step([string]$Name, [scriptblock]$Body) {
    Write-Output "=== $Name ($(Get-Date -Format s)) ==="
    try { & $Body } catch { Write-Output "FAILED: $Name -> $($_.Exception.Message)" }
}

$settings = @{}
$raw = Get-Content (Join-Path $Share 'provision.txt') -Raw -ErrorAction SilentlyContinue
if ($raw) { $settings = ConvertFrom-StringData $raw }

Step 'Power: never sleep, never blank the display' {
    powercfg /change standby-timeout-ac 0
    powercfg /change monitor-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    powercfg /hibernate off
}

Step 'Clock' {
    # The VM's hardware clock runs in UTC. Windows assumes local time by default, so after every
    # boot the clock would be off by the UTC offset, and Rouvy refuses to log in with a wrong clock.
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
        -Name RealTimeIsUniversal -PropertyType DWord -Value 1 -Force | Out-Null
    if ($settings.TIMEZONE) { Set-TimeZone -Id $settings.TIMEZONE }
    "time zone: $((Get-TimeZone).Id)"
}

Step 'OpenSSH server (the host drives the VM through it)' {
    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
    if ($cap.State -ne 'Installed') {
        # Windows Update is often still busy right after setup, so the download needs retries.
        for ($i = 1; $i -le 12; $i++) {
            try { Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null; break }
            catch { Write-Output "Add-WindowsCapability attempt ${i}: $($_.Exception.Message)"; Start-Sleep 30 }
        }
    }
    Set-Service sshd -StartupType Automatic
    Start-Service sshd
    New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -PropertyType String -Force `
        -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' | Out-Null
    if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    }
    $keys = Join-Path $Share 'authorized_keys'
    if (Test-Path $keys) {
        $dst = 'C:\ProgramData\ssh\administrators_authorized_keys'
        Copy-Item $keys $dst -Force
        # sshd ignores the file unless only Administrators and SYSTEM can access it.
        icacls $dst /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
    }
    Restart-Service sshd
}

Step 'Rouvy' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Share 'rouvy-update.ps1')
}

Step 'Done' {
    Get-Date -Format s | Out-File 'C:\OEM\setup.done'
}
Stop-Transcript | Out-Null
# The host waits for this copy to know that provisioning has finished.
Copy-Item 'C:\OEM\setup.log' (Join-Path $Share 'last-setup.log') -Force -ErrorAction SilentlyContinue
