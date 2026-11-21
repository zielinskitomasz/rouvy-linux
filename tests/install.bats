#!/usr/bin/env bats
# install.sh: the rouvy command on the PATH and the desktop launcher.

load helper

setup() {
  setup_sandbox
  export XDG_BIN_HOME=$SANDBOX/bin
  export XDG_DATA_HOME=$SANDBOX/share
  LAUNCHER=$XDG_DATA_HOME/applications/rouvy-linux.desktop
}
teardown() { teardown_sandbox; }

@test "install.sh links the command and writes a launcher" {
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$XDG_BIN_HOME/rouvy")" = "$REPO/rouvy" ]
  grep -qxF "Exec=\"$REPO/rouvy\" start" "$LAUNCHER"
  grep -qxF "Exec=\"$REPO/rouvy\" stop" "$LAUNCHER"
  grep -qxF "Icon=$REPO/assets/rouvy-linux.svg" "$LAUNCHER"
  [ -f "$REPO/assets/rouvy-linux.svg" ]
  [[ $output == *"rouvy build"* ]]
}

@test "the launcher file is a valid desktop entry" {
  command -v desktop-file-validate >/dev/null || skip "desktop-file-validate is not installed"
  run "$REPO/install.sh"
  run desktop-file-validate "$LAUNCHER"
  [ "$status" -eq 0 ]
}

@test "the linked command finds its own files" {
  run "$REPO/install.sh"
  run "$XDG_BIN_HOME/rouvy" status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "VM:         not built yet (rouvy build)" ]
}

@test "install.sh works from a directory with a space in its name" {
  mv "$REPO" "$SANDBOX/my repo"
  REPO="$SANDBOX/my repo"
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  grep -qxF "Exec=\"$REPO/rouvy\" start" "$LAUNCHER"
  run "$XDG_BIN_HOME/rouvy" help
  [ "$status" -eq 0 ]
}

@test "install.sh says so when its bin directory is not on the PATH" {
  run "$REPO/install.sh"
  [[ $output == *"$XDG_BIN_HOME is not on your PATH yet"* ]]
  PATH=$XDG_BIN_HOME:$PATH run "$REPO/install.sh"
  [[ $output != *"is not on your PATH"* ]]
}

@test "install.sh does not suggest a build when the VM exists" {
  vm_built
  run "$REPO/install.sh"
  [[ $output != *"rouvy build"* ]]
}

@test "install.sh --uninstall removes the command and the launcher, not the VM" {
  vm_built
  run "$REPO/install.sh"
  run "$REPO/install.sh" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_BIN_HOME/rouvy" ]
  [ ! -e "$LAUNCHER" ]
  [ -f "$REPO/storage/windows.boot" ]
}
