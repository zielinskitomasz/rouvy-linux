# Shared by the bats suites. Every test gets a private copy of the repository, fake commands on
# PATH (tests/stubs) and a fake USB tree, so nothing here touches Docker, the VM or Bluetooth.
#
# The fakes are driven by files in $STUB_STATE:
#   calls         every fake command line, in order
#   running       "true" or "false": is the VM container up (missing: there is no container)
#   probe         what Windows answers to the launcher's state probe (missing: no answer)
#   viewers       how many viewers the QEMU monitor reports (missing: the monitor fails)
#   ps1/<name>.out, .rc, .hook   output, exit codes (one per call) and side effect of a
#                 PowerShell script run in the VM
#   bluetooth     paired devices of the host, see the bluetoothctl stub
#   selinux/      a fake /sys/fs/selinux, see selinux_enforcing (missing: no SELinux)
#   attach, curl, docker, gnome, ssh   failure switches, see the stubs

setup_sandbox() {
  local source_root var
  source_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  # bats older than 1.4 has no per-test directory of its own.
  SANDBOX=${BATS_TEST_TMPDIR:-$(mktemp -d)}
  REPO=$SANDBOX/repo
  export STUB_STATE=$SANDBOX/state
  mkdir -p "$REPO/shared/setup" "$STUB_STATE/ps1" "$STUB_STATE/sys" "$SANDBOX/run" "$SANDBOX/home"
  cp -r "$source_root"/{rouvy,install.sh,compose.yaml,lib,assets,oem} "$REPO/"
  cp "$source_root"/shared/setup/*.ps1 "$REPO/shared/setup/"
  : >"$STUB_STATE/calls"

  # Nothing from the developer's own shell may leak into the launcher.
  for var in $(compgen -e | grep '^ROUVY_'); do unset "$var"; done
  export PATH=$BATS_TEST_DIRNAME/stubs:$PATH
  export HOME=$SANDBOX/home
  export XDG_RUNTIME_DIR=$SANDBOX/run
  export ROUVY_USB_SYSFS=$STUB_STATE/sys
  export ROUVY_KVM_DEVICE=/dev/null
  export ROUVY_TUN_DEVICE=/dev/null
  export ROUVY_SELINUX_FS=$STUB_STATE/selinux
  export ROUVY_WATCH_INTERVAL=1
  # shellcheck disable=SC2034  # read by the suites
  RUN_DIR=$XDG_RUNTIME_DIR/rouvy-rouvy
}

teardown_sandbox() {
  local pid
  # `rouvy start` launches its watcher detached, so it is found by command line, not by a pid
  # file it may not have written yet. It leads its own process group unless a test started it.
  for pid in $(pgrep -f "$REPO/rouvy _watch"); do
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  done
  wait_for 5 no_watcher || true
  # bats 1.4 and newer remove their per-test directory themselves.
  if [[ -z ${BATS_TEST_TMPDIR:-} ]]; then rm -rf "$SANDBOX" || true; fi
}

no_watcher() { ! pgrep -f "$REPO/rouvy _watch" >/dev/null; }

# fd 3 belongs to bats; a watcher that inherited it would keep the test from ever finishing.
rouvy() { "$REPO/rouvy" "$@" 3>&-; }

# Runs a snippet with the launcher's functions loaded and its shell options in force.
rouvy_sh() { bash -c "source '$REPO/rouvy'; $1" 3>&-; }

# Like rouvy_sh, with every wait_until cut down to one attempt so failure paths do not sleep.
rouvy_once() { rouvy_sh "wait_until() { shift; \"\$@\"; }; $1"; }

# add_usb_device <port> <vendor> <product> <bluetooth|other> [driver]
add_usb_device() {
  local dev=$STUB_STATE/sys/$1 intf=$STUB_STATE/sys/$1/$1:1.0
  mkdir -p "$intf"
  echo "$2" >"$dev/idVendor"
  echo "$3" >"$dev/idProduct"
  if [[ $4 == bluetooth ]]; then
    echo e0 >"$intf/bInterfaceClass"
    echo 01 >"$intf/bInterfaceSubClass"
    echo 01 >"$intf/bInterfaceProtocol"
  else
    echo ff >"$intf/bInterfaceClass"
    echo 00 >"$intf/bInterfaceSubClass"
    echo 00 >"$intf/bInterfaceProtocol"
  fi
  ln -sfn "../../drivers/${5:-btusb}" "$intf/driver"
}

intel_adapter() { add_usb_device 3-4 8087 0033 bluetooth "${1:-btusb}"; }

# selinux_enforcing <0|1>: SELinux is enforcing, with this value of container_use_devices
selinux_enforcing() {
  mkdir -p "$STUB_STATE/selinux/booleans"
  echo 1 >"$STUB_STATE/selinux/enforce"
  echo "$1 $1" >"$STUB_STATE/selinux/booleans/container_use_devices"
}

vm_built() {
  mkdir -p "$REPO/storage" "$REPO/ssh"
  : >"$REPO/storage/windows.boot"
}
vm_running() { echo true >"$STUB_STATE/running"; }
vm_stopped() { echo false >"$STUB_STATE/running"; }
viewers() { echo "$1" >"$STUB_STATE/viewers"; }

# probe ROUVY=1 RDP=0 VERSION=4.8.4.253 (Windows answers with CRLF line endings)
probe() { printf '%s\r\n' "$@" >"$STUB_STATE/probe"; }

# ps1_result <script> <output> [exit code per call...]
ps1_result() {
  local script=$1 output=$2
  shift 2
  printf '%s\r\n' "$output" >"$STUB_STATE/ps1/$script.out"
  if (($#)); then printf '%s\n' "$@" >"$STUB_STATE/ps1/$script.rc"; fi
}

assert_called() {
  grep -qE -- "$1" "$STUB_STATE/calls" || {
    echo "expected a call matching: $1"
    echo "calls were:"
    cat "$STUB_STATE/calls"
    return 1
  }
}

refute_called() {
  if grep -qE -- "$1" "$STUB_STATE/calls"; then
    echo "unexpected call matching: $1"
    grep -E -- "$1" "$STUB_STATE/calls"
    return 1
  fi
}

# assert_order <pattern>...: the first matches appear in this order.
assert_order() {
  local pattern line last=0
  for pattern in "$@"; do
    line=$(grep -nE -m1 -- "$pattern" "$STUB_STATE/calls" | cut -d: -f1)
    if [[ -z $line ]] || ((line <= last)); then
      echo "expected '$pattern' after line $last, found at line ${line:-none}:"
      cat -n "$STUB_STATE/calls"
      return 1
    fi
    last=$line
  done
}

# wait_for <seconds> <command...>: succeeds as soon as the command does.
wait_for() {
  local deadline=$((SECONDS + $1))
  shift
  until "$@" 2>/dev/null; do
    ((SECONDS < deadline)) || return 1
    sleep 0.2
  done
}
