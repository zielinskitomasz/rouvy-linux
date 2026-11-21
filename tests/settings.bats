#!/usr/bin/env bats
# rouvy.conf handling and the command line surface.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "settings: values from rouvy.conf reach the launcher" {
  cat >"$REPO/rouvy.conf" <<'EOF'
# a comment
ROUVY_NAME=bike
ROUVY_TIMEZONE="Central European Standard Time"
ROUVY_VIEWER='firefox --kiosk'
ROUVY_SSH_PORT=2299   # trailing comment
  ROUVY_BT=0a12:0001
EOF
  run rouvy_sh 'echo "$ROUVY_NAME|$ROUVY_TIMEZONE|$ROUVY_VIEWER|$ROUVY_SSH_PORT|$ROUVY_BT|$CONTAINER"'
  [ "$status" -eq 0 ]
  [ "$output" = "bike|Central European Standard Time|firefox --kiosk|2299|0a12:0001|bike-windows" ]
}

@test "settings: the environment wins over rouvy.conf" {
  echo 'ROUVY_NAME=fromfile' >"$REPO/rouvy.conf"
  ROUVY_NAME=fromenv run rouvy_sh 'echo "$ROUVY_NAME"'
  [ "$output" = fromenv ]
}

@test "settings: rouvy.conf is read as data, never executed" {
  printf 'ROUVY_NAME=$(touch %s/pwned)\nROUVY_VIEWER=`touch %s/pwned`\n' "$SANDBOX" "$SANDBOX" >"$REPO/rouvy.conf"
  run rouvy_sh 'echo "$ROUVY_NAME"'
  [ "$status" -eq 0 ]
  [[ $output == '$(touch '* ]]
  [ ! -e "$SANDBOX/pwned" ]
}

@test "settings: Windows line endings in rouvy.conf are tolerated" {
  printf 'ROUVY_NAME=crlf\r\nROUVY_TIMEZONE="UTC"\r\n' >"$REPO/rouvy.conf"
  run rouvy_sh 'echo "[$ROUVY_NAME][$ROUVY_TIMEZONE]"'
  [ "$output" = "[crlf][UTC]" ]
}

@test "settings: defaults apply without a rouvy.conf" {
  run rouvy_sh 'echo "$ROUVY_NAME $ROUVY_WEB_PORT $ROUVY_SSH_PORT $ROUVY_BT $ROUVY_VIEWER $ROUVY_INHIBIT"'
  [ "$output" = "rouvy 8006 2222 auto auto auto" ]
}

@test "settings: compose is pointed at rouvy.conf" {
  echo 'ROUVY_RAM=6G' >"$REPO/rouvy.conf"
  vm_built
  run rouvy start --no-bt --no-launch --no-view
  [ "$status" -eq 0 ]
  assert_called "docker compose .*--env-file $REPO/rouvy.conf up -d"
}

@test "settings: without rouvy.conf compose reads no stray settings file" {
  vm_built
  run rouvy start --no-bt --no-launch --no-view
  [ "$status" -eq 0 ]
  assert_called "docker compose .*--env-file /dev/null up -d"
}

@test "settings: a custom name and custom ports are used everywhere" {
  printf 'ROUVY_NAME=bike\nROUVY_WEB_PORT=9000\nROUVY_SSH_PORT=2299\n' >"$REPO/rouvy.conf"
  vm_built
  run rouvy start --no-bt --no-launch
  [ "$status" -eq 0 ]
  assert_called "docker inspect .* bike-windows"
  wait_for 5 assert_called "google-chrome --app=http://127.0.0.1:9000/"
  run rouvy_sh 'echo "${SSH[*]}"'
  [[ $output == *"-p 2299 "* ]]
  RUN_DIR=$XDG_RUNTIME_DIR/rouvy-bike
}

@test "help lists every command and exits 0" {
  local cmd
  run rouvy help
  [ "$status" -eq 0 ]
  for cmd in start stop status view build update bt ssh screenshot monitor logs doctor; do
    [[ $output == *"  $cmd"* ]]
  done
}

@test "an unknown command prints the usage and exits 2" {
  run rouvy frobnicate
  [ "$status" -eq 2 ]
  [[ $output == *"Usage: rouvy"* ]]
}
