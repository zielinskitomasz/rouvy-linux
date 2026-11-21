# Report how Windows sees the passed-through Bluetooth adapter and which BLE devices are in range.
param([string]$UsbId)
$instance = if ($UsbId) { $vid, $prod = $UsbId.ToUpper().Split(':'); "USB\VID_$vid&PID_$prod*" } else { $null }
$devices = Get-PnpDevice -PresentOnly | Where-Object { $_.Class -eq 'Bluetooth' -or ($instance -and $_.InstanceId -like $instance) }

'--- devices:'
$devices | Sort-Object Class | Format-Table Status, Class, FriendlyName, InstanceId -AutoSize | Out-String -Width 200
'--- problems:'
$devices | Where-Object Status -ne 'OK' | ForEach-Object {
    "$($_.FriendlyName): $($_.Status), problem code $((Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemCode).Data)"
}
"--- bluetooth service: $((Get-Service bthserv).Status)"

# WinRT calls return IAsyncOperation, which Windows PowerShell cannot await by itself.
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($Operation, $ResultType) {
    $task = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.Wait(-1) | Out-Null
    $task.Result
}

$null = [Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime]
'--- radios:'
Await ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]]) |
    ForEach-Object { "$($_.Kind) '$($_.Name)' state=$($_.State)" }

$null = [Windows.Devices.Bluetooth.BluetoothLEDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
$null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
'--- BLE devices in range (not paired):'
$selector = [Windows.Devices.Bluetooth.BluetoothLEDevice]::GetDeviceSelectorFromPairingState($false)
$found = Await ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($selector)) ([Windows.Devices.Enumeration.DeviceInformationCollection])
"visible: $($found.Count)"
$found | Select-Object -First 20 | ForEach-Object { " - '$($_.Name)' $($_.Id.Substring([Math]::Max(0, $_.Id.Length - 17)))" }
