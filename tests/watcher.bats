#!/usr/bin/env bats
# The background watcher that keeps the screen awake during a ride.

load helper

setup() {
  setup_sandbox
  intel_adapter usbfs
  vm_built
  vm_running
}
teardown() { teardown_sandbox; }

start_watcher() {
  "$REPO/rouvy" _watch >>"$SANDBOX/watch.out" 2>&1 3>&- &
  wait_for 5 test -s "$RUN_DIR/watch.pid"
}

riding() {
  probe ROUVY=1 RDP=0 VERSION=4.8.4.253
  viewers 1
}

inhibited() { [[ -f $RUN_DIR/inhibited ]]; }
released() { [[ ! -f $RUN_DIR/inhibited ]]; }
holder_gone() { ! pgrep -f "tail --pid=$1 -f /dev/null" >/dev/null; }

@test "watcher: the screen is kept awake while Rouvy runs and its screen is open" {
  riding
  start_watcher
  wait_for 10 inhibited
  [ "$(cat "$RUN_DIR/inhibited")" = gnome ]
  assert_called "gnome-session-inhibit --app-id rouvy .*--inhibit idle --inhibit suspend tail --pid=$(cat "$RUN_DIR/watch.pid") "
}

@test "watcher: closing the screen releases the inhibitor" {
  riding
  start_watcher
  wait_for 10 inhibited
  viewers 0
  wait_for 10 released
  wait_for 5 holder_gone "$(cat "$RUN_DIR/watch.pid")"
}

@test "watcher: quitting Rouvy releases the inhibitor" {
  riding
  start_watcher
  wait_for 10 inhibited
  probe ROUVY=0 RDP=0 VERSION=4.8.4.253
  wait_for 10 released
}

@test "watcher: an RDP session counts as somebody watching" {
  probe ROUVY=1 RDP=1 VERSION=4.8.4.253
  viewers 0
  start_watcher
  wait_for 10 inhibited
}

@test "watcher: nothing is inhibited when nobody is watching" {
  probe ROUVY=1 RDP=0 VERSION=4.8.4.253
  viewers 0
  start_watcher
  sleep 3
  released
  refute_called "gnome-session-inhibit"
}

@test "watcher: a few unanswered probes keep the inhibitor, a long silence drops it" {
  riding
  start_watcher
  wait_for 10 inhibited
  rm "$STUB_STATE/probe"
  sleep 3
  inhibited
  wait_for 20 released
}

@test "watcher: falls back to systemd-inhibit when gnome-session-inhibit gives up" {
  echo fail >"$STUB_STATE/gnome"
  riding
  start_watcher
  wait_for 10 inhibited
  [ "$(cat "$RUN_DIR/inhibited")" = systemd ]
  assert_called "systemd-inhibit --what=idle:sleep --who=rouvy "
}

@test "watcher: a custom ROUVY_INHIBIT command is started and stopped" {
  export ROUVY_INHIBIT="sleep 4242"
  riding
  start_watcher
  wait_for 10 inhibited
  [ "$(cat "$RUN_DIR/inhibited")" = custom ]
  pgrep -f "sleep 4242" >/dev/null
  viewers 0
  wait_for 10 released
  ! pgrep -f "sleep 4242" >/dev/null
}

@test "watcher: ends when the VM stops and cleans up after itself" {
  local pid
  riding
  start_watcher
  wait_for 10 inhibited
  pid=$(cat "$RUN_DIR/watch.pid")
  vm_stopped
  wait_for 10 test ! -e "$RUN_DIR/watch.pid"
  released
  wait_for 5 holder_gone "$pid"
}

@test "watcher: the inhibitor does not outlive a watcher that is killed outright" {
  local pid
  riding
  start_watcher
  wait_for 10 inhibited
  pid=$(cat "$RUN_DIR/watch.pid")
  kill -9 "$pid"
  wait_for 5 holder_gone "$pid"
}

@test "watcher: a second one bows out while the first is running" {
  local first
  start_watcher
  first=$(cat "$RUN_DIR/watch.pid")
  run rouvy _watch
  [ "$status" -eq 0 ]
  [ "$(cat "$RUN_DIR/watch.pid")" = "$first" ]
  kill -0 "$first"
}

@test "watcher: stop followed at once by start gets a fresh watcher" {
  local first
  run rouvy start --no-bt --no-launch --no-view
  wait_for 5 test -s "$RUN_DIR/watch.pid"
  first=$(cat "$RUN_DIR/watch.pid")
  run rouvy stop
  run rouvy start --no-bt --no-launch --no-view
  wait_for 5 test -s "$RUN_DIR/watch.pid"
  [ "$(cat "$RUN_DIR/watch.pid")" != "$first" ]
  kill -0 "$(cat "$RUN_DIR/watch.pid")"
}
