# Start Rouvy on the VM desktop. A process started straight from the SSH session would live in
# session 0 and never show a window, so a scheduled task starts it in the logged-in session.
$exe = 'C:\Program Files\VirtualTraining\Rouvy\Rouvy.exe'
if (-not (Test-Path $exe)) { 'Rouvy is not installed (rouvy update installs it)'; exit 2 }

$running = Get-Process Rouvy -ErrorAction SilentlyContinue
if (-not $running) {
    $action = New-ScheduledTaskAction -Execute $exe -WorkingDirectory (Split-Path $exe)
    $principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    # The defaults would kill the task after 3 days and refuse to start it on battery power.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName 'Launch Rouvy' -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName 'Launch Rouvy'
    for ($i = 0; $i -lt 30 -and -not $running; $i++) {
        Start-Sleep 1
        $running = Get-Process Rouvy -ErrorAction SilentlyContinue
    }
}
if (-not $running) { 'Rouvy did not start (is the Windows desktop logged in?)'; exit 1 }
"Rouvy $((Get-Item $exe).VersionInfo.ProductVersion) is running"
