#!/usr/bin/env bats
# Picking the adapter, moving it between Linux and the VM, and the driver fallback.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "bluetooth: the only Bluetooth controller is picked automatically" {
  add_usb_device usb3 1d6b 0002 other
  add_usb_device 3-2 06cb 00f0 other
  intel_adapter
  run rouvy_sh 'bt_select; echo "$BT_VID:$BT_PID ${BT_DEV##*/} $(bt_owner)"'
  [ "$status" -eq 0 ]
  [ "$output" = "8087:0033 3-4 btusb" ]
}

@test "bluetooth: without a controller there is nothing to hand over" {
  add_usb_device 3-2 06cb 00f0 other
  run rouvy_sh 'bt_select'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "bluetooth: two controllers need an explicit choice" {
  intel_adapter
  add_usb_device 1-1 0a12 0001 bluetooth
  run rouvy_sh 'bt_select'
  [ "$status" -eq 1 ]
  [[ $output == *"several Bluetooth adapters found"* ]]
  [[ $output == *"8087:0033"* && $output == *"0a12:0001"* ]]
}

@test "bluetooth: ROUVY_BT=vendor:product picks that device, whatever its USB class" {
  intel_adapter
  add_usb_device 1-1 0a5c 21e8 other
  ROUVY_BT=0A5C:21E8 run rouvy_sh 'bt_select; echo "$BT_VID:$BT_PID ${BT_DEV##*/}"'
  [ "$output" = "0a5c:21e8 1-1" ]
}

@test "bluetooth: ROUVY_BT=off never selects an adapter" {
  intel_adapter
  ROUVY_BT=off run rouvy_sh 'bt_select'
  [ "$status" -eq 1 ]
}

@test "bluetooth: the owner follows the driver bound to the adapter" {
  intel_adapter usbfs
  run rouvy_sh 'bt_select; bt_owner; bt_owner_label'
  [ "${lines[0]}" = usbfs ]
  [ "${lines[1]}" = "the VM" ]
}

@test "bluetooth: an adapter without a driver belongs to nobody" {
  intel_adapter
  rm "$STUB_STATE/sys/3-4/3-4:1.0/driver"
  run rouvy_sh 'bt_select; bt_owner; bt_owner_label'
  [ "${lines[0]}" = none ]
  [ "${lines[1]}" = "nobody (no driver bound)" ]
}

@test "bluetooth: the adapter is named from sysfs, or from lsusb when sysfs has no name" {
  intel_adapter
  run rouvy_sh 'bt_select; bt_name'
  [ "$output" = "Intel Corp. AX211 Bluetooth (8087:0033)" ]
  echo "Fancy Dongle" >"$STUB_STATE/sys/3-4/product"
  run rouvy_sh 'bt_select; bt_name'
  [ "$output" = "Fancy Dongle (8087:0033)" ]
}

@test "bt attach hands the adapter to the running VM" {
  intel_adapter
  vm_running
  run rouvy bt attach
  [ "$status" -eq 0 ]
  assert_called "hmp device_add usb-host,vendorid=0x8087,productid=0x0033,id=bt0"
  [[ $output == *"handed to the VM"* ]]
}

@test "bt attach disconnects what is connected to Linux before the adapter leaves" {
  intel_adapter
  vm_running
  printf '%s\n' 'AA:BB:CC:00:00:01|Sport Headset|yes' '11:22:33:00:00:02|Office Mouse|no' >"$STUB_STATE/bluetooth"
  run rouvy bt attach
  [ "$status" -eq 0 ]
  [[ $output == *"Bluetooth: disconnected Sport Headset from Linux"* ]]
  assert_order "bluetoothctl disconnect AA:BB:CC:00:00:01" "hmp device_add"
  refute_called "bluetoothctl disconnect 11:22:33:00:00:02"
  grep -qxF 'AA:BB:CC:00:00:01|Sport Headset|no' "$STUB_STATE/bluetooth"
}

@test "bt attach does nothing when the VM already owns the adapter" {
  intel_adapter usbfs
  vm_running
  run rouvy bt attach
  [ "$status" -eq 0 ]
  refute_called "device_add"
  [[ $output == *"already belongs to the VM"* ]]
}

@test "bt attach asks for a VM restart when QEMU cannot see the adapter" {
  intel_adapter
  vm_running
  echo broken >"$STUB_STATE/attach"
  run rouvy bt attach
  [ "$status" -eq 1 ]
  [[ $output == *"rouvy stop && rouvy start"* ]]
}

@test "bt detach gives the adapter back to Linux" {
  intel_adapter usbfs
  vm_running
  run rouvy bt detach
  [ "$status" -eq 0 ]
  assert_called "hmp device_del bt0"
  [[ $output == *"belongs to Linux"* ]]
}

@test "bt attach and detach need a running VM" {
  intel_adapter
  vm_stopped
  run rouvy bt attach
  [ "$status" -eq 1 ]
  [[ $output == *"the VM is not running"* ]]
  refute_called "device_add"
}

@test "bt check tells the Windows script which adapter to look at" {
  intel_adapter usbfs
  run rouvy bt check
  [ "$status" -eq 0 ]
  assert_called "bt-check\.ps1' -UsbId '8087:0033'"
}

@test "bt driver: an Intel adapter without a driver gets Intel's package, then a second try" {
  intel_adapter usbfs
  ps1_result bt-driver.ps1 "bluetooth: result" 3 0
  run rouvy bt driver
  [ "$status" -eq 0 ]
  assert_called "curl .*downloadmirror\.intel\.com/.*BT-24\.80\.0-64UWD-Win10-Win11\.exe"
  [ -s "$REPO/shared/setup/drivers/BT-24.80.0-64UWD-Win10-Win11.exe" ]
  [ "$(grep -c 'bt-driver\.ps1' "$STUB_STATE/calls")" -eq 2 ]
}

@test "bt driver: nothing is downloaded for other vendors" {
  add_usb_device 1-1 0a12 0001 bluetooth usbfs
  ps1_result bt-driver.ps1 "bluetooth: no driver" 3
  run rouvy bt driver
  [ "$status" -eq 3 ]
  refute_called "^curl"
}

@test "bt driver: nothing is downloaded when a driver package is already there" {
  intel_adapter usbfs
  mkdir -p "$REPO/shared/setup/drivers"
  : >"$REPO/shared/setup/drivers/vendor.exe"
  ps1_result bt-driver.ps1 "bluetooth: still broken" 3
  run rouvy bt driver
  [ "$status" -eq 3 ]
  refute_called "^curl"
}

@test "bt driver --force asks the Windows script to reinstall" {
  intel_adapter usbfs
  run rouvy bt driver --force
  [ "$status" -eq 0 ]
  assert_called "bt-driver\.ps1' -UsbId '8087:0033' -Force"
}

@test "bt without a subcommand explains itself" {
  run rouvy bt
  [ "$status" -eq 1 ]
  [[ $output == *"usage: rouvy bt"* ]]
}
