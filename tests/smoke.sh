#!/usr/bin/env bash
# Smoke test against the real VM, for everything the fakes in the bats suites cannot show:
# Windows, the Bluetooth hand-over, Rouvy itself and the desktop's idle inhibitor.
#
# It needs a built VM (rouvy build) that is stopped, takes about a minute, and borrows the
# Bluetooth adapter for that time. The VM is stopped again at the end.
#
# The adapter is left alone when something is connected to it on the Linux side: a headset that
# tries to reconnect while Windows answers under the same address can lose its pairing.
# SMOKE_BT=force takes the adapter anyway.

# shellcheck source-path=SCRIPTDIR source=../rouvy
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../rouvy"

failures=0
started=0
screenshot=""

check() { # check <description> <command...>
  local what=$1 output
  shift
  if output=$("$@" 2>&1); then
    echo "ok    $what"
  else
    echo "FAIL  $what"
    if [[ -n $output ]]; then echo "      ${output//$'\n'/$'\n'      }"; fi
    failures=$((failures + 1))
  fi
}

cleanup() {
  docker exec "$CONTAINER" touch /tmp/rouvy-smoke-stop 2>/dev/null || true
  if [[ -n $screenshot ]]; then rm -f "$screenshot"; fi
  if ((started)) && container_running; then "$ROOT/rouvy" stop >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

# A viewer as QEMU sees one: a client that completes the VNC handshake and stays connected.
fake_viewer() {
  docker exec "$CONTAINER" rm -f /tmp/rouvy-smoke-stop
  docker exec -d "$CONTAINER" python3 -c '
import os, socket, time
viewer = socket.create_connection(("127.0.0.1", 5900))
viewer.recv(12)
viewer.sendall(b"RFB 003.008\n")
deadline = time.time() + 300
while time.time() < deadline and not os.path.exists("/tmp/rouvy-smoke-stop"):
    time.sleep(1)'
}

rouvy_runs() { [[ $(vm_probe) == *ROUVY=1* ]]; }
vm_is_down() { ! container_running; }
viewer_connected() { [[ $(monitor vnc-clients) -ge 1 ]]; }
screen_released() { ! screen_inhibited; }
gnome_idle_inhibited() {
  [[ $(gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager \
    --method org.gnome.SessionManager.IsInhibited 8) == "(true,)" ]]
}
windows_parses_the_scripts() {
  local errors
  # shellcheck disable=SC2016  # the dollar signs belong to PowerShell
  errors=$(vm_ssh 'Get-ChildItem \\host.lan\Data\setup\*.ps1 | ForEach-Object { $e = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e); if ($e) { $_.Name } }') || return 1
  [[ -z ${errors//[[:space:]]/} ]]
}
clocks_agree() {
  local vm host
  vm=$(vm_ssh '[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()' | tr -dc 0-9)
  host=$(date +%s)
  ((vm - host < 5 && host - vm < 5))
}
is_png() { [[ $(head -c 4 "$1" | tail -c 3) == PNG ]]; }

vm_installed || die "there is no VM to test, run: rouvy build"
if container_running; then die "stop the VM first (rouvy stop): this test boots it and shuts it down"; fi

start_options=(--no-view)
test_bluetooth=1
in_use=$(bt_host_connections | cut -d' ' -f2- | paste -sd, -)
if ! bt_select; then
  test_bluetooth=0
  echo "skip  Bluetooth (no adapter selected)"
elif [[ -n $in_use && ${SMOKE_BT:-} != force ]]; then
  test_bluetooth=0
  start_options+=(--no-bt)
  echo "skip  Bluetooth ($in_use is connected to Linux; SMOKE_BT=force takes the adapter anyway)"
fi

started=1
check "rouvy start boots the VM and returns successfully" "$ROOT/rouvy" start "${start_options[@]}"
check "the VM container is running" container_running
check "Windows parses every PowerShell script" windows_parses_the_scripts
check "the Windows clock agrees with the host" clocks_agree
check "Rouvy is running on the VM desktop" rouvy_runs

if ((test_bluetooth)); then
  check "the VM owns the Bluetooth adapter" bt_owned_by usbfs
  check "Windows has a working driver for the adapter" bt_driver
fi

if [[ $ROUVY_INHIBIT == off ]]; then
  echo "skip  idle inhibitor (ROUVY_INHIBIT=off)"
else
  check "nothing is inhibited while nobody watches" screen_released
  fake_viewer
  check "the QEMU monitor counts the viewer" wait_until 15 viewer_connected
  check "a viewer makes the watcher inhibit screen blanking" wait_until 90 screen_inhibited
  if [[ $(cat "$RUN_DIR/inhibited" 2>/dev/null) == gnome ]]; then
    check "GNOME confirms the idle inhibitor" gnome_idle_inhibited
  fi
  docker exec "$CONTAINER" touch /tmp/rouvy-smoke-stop
  check "the inhibitor is released once the viewer is gone" wait_until 90 screen_released
fi

screenshot=$("$ROOT/rouvy" screenshot) || screenshot=""
check "rouvy screenshot writes a PNG" is_png "$screenshot"

check "rouvy stop shuts the VM down" "$ROOT/rouvy" stop
check "the VM container is stopped" vm_is_down
check "the watcher is gone" test ! -e "$RUN_DIR/watch.pid"
if ((test_bluetooth)); then check "Bluetooth is back with Linux" bt_with_linux; fi

if ((failures)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
