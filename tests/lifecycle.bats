#!/usr/bin/env bats
# start, stop, status, view, screenshot, build, update and doctor against the fakes.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

rouvy_is_up() { probe ROUVY=1 RDP=0 VERSION=4.8.4.253; }
rouvy_is_down() { probe ROUVY=0 RDP=0 VERSION=4.8.4.253; }

# Makes the fake VM "finish provisioning" the moment its container comes up.
provisioning_succeeds() {
  cat >"$STUB_STATE/on-up" <<EOF
#!/usr/bin/env bash
sleep 0.05
mkdir -p "$REPO/storage"
: >"$REPO/storage/windows.boot"
printf '=== Rouvy (2026) ===\r\nRouvy 4.8.4.253 installed\r\n=== Done (2026) ===\r\n' >"$REPO/shared/setup/last-setup.log"
EOF
  chmod +x "$STUB_STATE/on-up"
}

@test "start refuses to run before the VM is built" {
  run rouvy start
  [ "$status" -eq 1 ]
  [[ $output == *"run: rouvy build"* ]]
  refute_called "compose"
}

@test "start boots the VM, hands over Bluetooth, starts Rouvy and opens the screen, in that order" {
  intel_adapter
  vm_built
  rouvy_is_up
  run rouvy start
  [ "$status" -eq 0 ]
  wait_for 5 assert_called "google-chrome --app=http://127.0.0.1:8006/"
  assert_order "docker compose .* up -d" "hmp device_add" "ssh hostname" "bt-driver\.ps1" "rouvy-launch\.ps1" "google-chrome"
  [[ $output == *"Ready. Stop with: rouvy stop"* ]]
  wait_for 5 test -s "$RUN_DIR/watch.pid"
}

@test "start --no-bt leaves Bluetooth alone" {
  intel_adapter
  vm_built
  run rouvy start --no-bt --no-view
  [ "$status" -eq 0 ]
  refute_called "device_add"
  refute_called "bt-driver\.ps1"
  assert_called "rouvy-launch\.ps1"
}

@test "start with ROUVY_BT=off leaves Bluetooth alone without a warning" {
  intel_adapter
  vm_built
  ROUVY_BT=off run rouvy start --no-view
  [ "$status" -eq 0 ]
  refute_called "device_add"
  [[ $output != *"warning"* ]]
}

@test "start --no-launch and --no-view skip their steps" {
  vm_built
  run rouvy start --no-bt --no-launch --no-view
  [ "$status" -eq 0 ]
  sleep 0.5
  refute_called "rouvy-launch\.ps1"
  refute_called "google-chrome"
}

@test "start carries on with a warning when there is no adapter" {
  vm_built
  run rouvy start --no-view
  [ "$status" -eq 0 ]
  [[ $output == *"warning: no USB Bluetooth adapter found"* ]]
  assert_called "rouvy-launch\.ps1"
}

@test "start warns when the adapter does not work inside Windows" {
  add_usb_device 1-1 0a12 0001 bluetooth
  vm_built
  ps1_result bt-driver.ps1 "bluetooth: 'Generic Radio' still reports Error" 1
  run rouvy start --no-view
  [ "$status" -eq 0 ]
  [[ $output == *"warning: Bluetooth is not working inside Windows"* ]]
  assert_called "rouvy-launch\.ps1"
}

@test "start on a running VM does not boot it again" {
  vm_built
  vm_running
  run rouvy start --no-bt --no-view
  [ "$status" -eq 0 ]
  [[ $output == *"The VM is already running"* ]]
  refute_called "compose .* up"
}

@test "start rejects options it does not know" {
  vm_built
  run rouvy start --fast
  [ "$status" -eq 1 ]
  [[ $output == *"unknown option for start: --fast"* ]]
  refute_called "compose"
}

@test "start reports progress as desktop notifications when there is no terminal" {
  vm_built
  run rouvy start --no-bt --no-view
  assert_called "notify-send .*Starting the Windows VM"
  assert_called "notify-send .*Rouvy is ready"
}

@test "ROUVY_INHIBIT=off starts no watcher" {
  vm_built
  ROUVY_INHIBIT=off run rouvy start --no-bt --no-view
  [ "$status" -eq 0 ]
  sleep 0.5
  [ ! -e "$RUN_DIR/watch.pid" ]
}

@test "view: ROUVY_VIEWER=none only prints the address" {
  ROUVY_VIEWER=none run rouvy view
  [ "$output" = "Screen: http://127.0.0.1:8006/" ]
  refute_called "google-chrome"
}

@test "view: a custom viewer command gets the screen address" {
  ROUVY_VIEWER='echo "$ROUVY_SCREEN_URL" >"$STUB_STATE/viewer"' run rouvy view
  [ "$status" -eq 0 ]
  wait_for 5 test -s "$STUB_STATE/viewer"
  [ "$(cat "$STUB_STATE/viewer")" = "http://127.0.0.1:8006/" ]
}

@test "stop shuts Windows down, ends the watcher and reports who owns Bluetooth" {
  intel_adapter
  vm_built
  run rouvy start --no-view
  wait_for 5 test -s "$RUN_DIR/watch.pid"
  run rouvy stop
  [ "$status" -eq 0 ]
  assert_called "docker stop rouvy-windows"
  [[ $output == *"Intel Corp. AX211 Bluetooth (8087:0033) belongs to Linux"* ]]
  wait_for 5 test ! -e "$RUN_DIR/watch.pid"
}

@test "stop on a stopped VM is harmless" {
  vm_built
  vm_stopped
  run rouvy stop
  [ "$status" -eq 0 ]
  [[ $output == *"The VM is not running"* ]]
  refute_called "docker stop"
}

@test "status: nothing built yet" {
  run rouvy status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "VM:         not built yet (rouvy build)" ]
  [ "${lines[1]}" = "Bluetooth:  no USB adapter found" ]
}

@test "status: a stopped VM" {
  intel_adapter
  vm_built
  vm_stopped
  ROUVY_BT=off run rouvy status
  [ "${lines[0]}" = "VM:         stopped" ]
  [ "${lines[1]}" = "Bluetooth:  switched off (ROUVY_BT=off)" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "status: a ride in progress" {
  intel_adapter usbfs
  vm_built
  vm_running
  rouvy_is_up
  viewers 2
  run rouvy status
  [ "${lines[0]}" = "VM:         running (Up 5 seconds)" ]
  [ "${lines[1]}" = "Bluetooth:  Intel Corp. AX211 Bluetooth (8087:0033) belongs to the VM" ]
  [ "${lines[2]}" = "Rouvy:      4.8.4.253, running" ]
  [ "${lines[3]}" = "Viewers:    2 on http://127.0.0.1:8006/" ]
  [[ ${lines[4]} == "Screen:     normal blanking"* ]]
}

@test "status: Windows is still booting, or Rouvy is missing" {
  vm_built
  vm_running
  run rouvy status
  [[ $output == *"Rouvy:      unknown (Windows is not answering yet)"* ]]
  [[ $output == *"Viewers:    unknown"* ]]
  probe ROUVY=0 RDP=0 VERSION=
  run rouvy status
  [[ $output == *"Rouvy:      not installed, not running"* ]]
}

@test "screenshot stores a PNG under screenshots/ and prints its path" {
  vm_running
  run rouvy screenshot
  [ "$status" -eq 0 ]
  [[ $output == "$REPO/screenshots/"*.png ]]
  [ -f "$output" ]
  assert_called "python3 - screendump /tmp/screen.png"
  assert_called "docker cp rouvy-windows:/tmp/screen.png $REPO/screenshots/"
}

@test "screenshot needs a running VM" {
  vm_stopped
  run rouvy screenshot
  [ "$status" -eq 1 ]
  [[ $output == *"the VM is not running"* ]]
}

@test "monitor passes its arguments to the QEMU monitor" {
  vm_running
  run rouvy monitor info status
  [ "$output" = "reply to: info status" ]
  run rouvy monitor
  [ "$status" -eq 1 ]
}

@test "ssh runs the given command in the VM" {
  run rouvy ssh 'Get-Process Rouvy'
  [ "$output" = "ran: Get-Process Rouvy" ]
}

@test "build prepares the key, the settings for Windows and the installer, then waits for provisioning" {
  provisioning_succeeds
  ROUVY_TIMEZONE="Central European Standard Time" run rouvy build
  [ "$status" -eq 0 ]
  [ -f "$REPO/ssh/id_ed25519" ]
  [ "$(cat "$REPO/shared/setup/authorized_keys")" = "ssh-ed25519 AAAAstub rouvy-vm" ]
  [ "$(cat "$REPO/shared/setup/provision.txt")" = "TIMEZONE=Central European Standard Time" ]
  [ -s "$REPO/shared/setup/rouvy/Rouvy_Installer.exe" ]
  assert_order "curl .*cdn\.rouvy\.com/update/Rouvy_Installer\.exe" "docker compose .* up -d" "docker stop rouvy-windows"
  [ ! -e "$REPO/shared/setup/.build-started" ]
  [[ $output == *"Rouvy 4.8.4.253 installed"* ]]
  [[ $output == *"Done. Start riding with: rouvy"* ]]
}

@test "build keeps an existing SSH key and forgets the old host key" {
  provisioning_succeeds
  mkdir -p "$REPO/ssh"
  echo "my key" >"$REPO/ssh/id_ed25519"
  echo "ssh-ed25519 MINE" >"$REPO/ssh/id_ed25519.pub"
  echo "[127.0.0.1]:2222 old" >"$REPO/ssh/known_hosts"
  run rouvy build
  [ "$status" -eq 0 ]
  refute_called "ssh-keygen"
  [ "$(cat "$REPO/shared/setup/authorized_keys")" = "ssh-ed25519 MINE" ]
  [ ! -e "$REPO/ssh/known_hosts" ]
}

@test "build needs KVM" {
  ROUVY_KVM_DEVICE=$SANDBOX/no-kvm run rouvy build
  [ "$status" -eq 1 ]
  [[ $output == *"/dev/kvm is missing"* ]]
  refute_called "compose"
}

@test "build refuses to overwrite an existing VM" {
  vm_built
  run rouvy build
  [ "$status" -eq 1 ]
  [[ $output == *"a Windows VM already exists"* ]]
  refute_called "compose"
}

@test "an interrupted build is picked up again" {
  provisioning_succeeds
  vm_built
  mkdir -p "$REPO/shared/setup"
  : >"$REPO/shared/setup/.build-started"
  run rouvy build
  [ "$status" -eq 0 ]
  [ ! -e "$REPO/shared/setup/.build-started" ]
}

@test "build stops waiting when the VM dies during the installation" {
  printf '#!/usr/bin/env bash\necho false >"%s/running"\n' "$STUB_STATE" >"$STUB_STATE/on-up"
  chmod +x "$STUB_STATE/on-up"
  run rouvy build
  [ "$status" -eq 1 ]
  [[ $output == *"the VM stopped during the installation"* ]]
  [ -e "$REPO/shared/setup/.build-started" ]
}

@test "build gives up when the Rouvy installer cannot be downloaded" {
  echo fail >"$STUB_STATE/curl"
  run rouvy build
  [ "$status" -eq 1 ]
  [[ $output == *"download failed: https://cdn.rouvy.com/update/Rouvy_Installer.exe"* ]]
  refute_called "compose"
  [ ! -e "$REPO/shared/setup/rouvy/Rouvy_Installer.exe.part" ]
}

@test "update on a stopped VM boots it without Bluetooth, installs and stops it again" {
  intel_adapter
  vm_built
  vm_stopped
  rouvy_is_down
  ps1_result rouvy-update.ps1 "Rouvy 4.8.5.1 installed (was 4.8.4.253)"
  run rouvy update
  [ "$status" -eq 0 ]
  [[ $output == *"Rouvy 4.8.5.1 installed (was 4.8.4.253)"* ]]
  assert_order "^curl " "docker compose .* up -d" "rouvy-update\.ps1" "docker stop rouvy-windows"
  refute_called "device_add"
  refute_called "rouvy-launch\.ps1"
}

@test "update skips the download when the local installer is current" {
  vm_built
  vm_running
  mkdir -p "$REPO/shared/setup/rouvy"
  echo "the copy we have" >"$REPO/shared/setup/rouvy/Rouvy_Installer.exe"
  echo notmodified >"$STUB_STATE/curl"
  run rouvy update
  [ "$status" -eq 0 ]
  assert_called "curl .* -z $REPO/shared/setup/rouvy/Rouvy_Installer.exe"
  [ "$(cat "$REPO/shared/setup/rouvy/Rouvy_Installer.exe")" = "the copy we have" ]
}

@test "update --force asks the Windows script to reinstall" {
  vm_built
  vm_running
  run rouvy update --force
  [ "$status" -eq 0 ]
  assert_called "rouvy-update\.ps1' -Force"
}

@test "update starts Rouvy again when the installation had to close it" {
  vm_built
  vm_running
  rouvy_is_up
  printf '#!/usr/bin/env bash\nprintf "ROUVY=0\\r\\nRDP=0\\r\\nVERSION=4.8.5.1\\r\\n" >"%s/probe"\n' "$STUB_STATE" >"$STUB_STATE/ps1/rouvy-update.ps1.hook"
  chmod +x "$STUB_STATE/ps1/rouvy-update.ps1.hook"
  run rouvy update
  [ "$status" -eq 0 ]
  assert_order "rouvy-update\.ps1" "rouvy-launch\.ps1"
  refute_called "docker stop"
}

@test "update leaves a running Rouvy alone when there was nothing to install" {
  vm_built
  vm_running
  rouvy_is_up
  ps1_result rouvy-update.ps1 "Rouvy 4.8.4.253 is up to date"
  run rouvy update
  [ "$status" -eq 0 ]
  refute_called "rouvy-launch\.ps1"
}

@test "update reports a failed installation" {
  vm_built
  vm_running
  ps1_result rouvy-update.ps1 "the installer failed with exit code 2" 1
  run rouvy update
  [ "$status" -eq 1 ]
  [[ $output == *"the installer failed with exit code 2"* ]]
}

@test "doctor names the adapter and the inhibitor it would use" {
  intel_adapter
  run rouvy doctor
  [[ $output == *"ok    docker daemon reachable"* ]]
  [[ $output == *"ok    Bluetooth: Intel Corp. AX211 Bluetooth (8087:0033), owned by Linux"* ]]
  [[ $output == *"ok    screen blanking inhibitor: gnome-session-inhibit"* ]]
}

@test "doctor fails without KVM" {
  ROUVY_KVM_DEVICE=$SANDBOX/no-kvm run rouvy doctor
  [ "$status" -eq 1 ]
  [[ $output == *"fail  /dev/kvm missing"* ]]
}

@test "doctor fails when docker is not usable" {
  echo down >"$STUB_STATE/docker"
  run rouvy doctor
  [ "$status" -eq 1 ]
  [[ $output == *"fail  docker daemon not reachable"* ]]
}
