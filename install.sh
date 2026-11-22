#!/usr/bin/env bash
# Put `rouvy` on the PATH and add a desktop launcher. `./install.sh --uninstall` removes both.
set -euo pipefail

ROOT=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
BIN=${XDG_BIN_HOME:-$HOME/.local/bin}
APPS=${XDG_DATA_HOME:-$HOME/.local/share}/applications
COMMAND=$BIN/rouvy
LAUNCHER=$APPS/rouvy-linux.desktop

owns_command() { [[ -L $COMMAND && $(readlink "$COMMAND") == "$ROOT/rouvy" ]]; }
owns_launcher() {
  [[ ! -L $LAUNCHER && -f $LAUNCHER ]] && grep -Fxq "Exec=\"$ROOT/rouvy\" start" "$LAUNCHER"
}
# What a checkout that was moved or deleted left behind points at nothing and is nobody's.
stale_command() { [[ -L $COMMAND && ! -e $COMMAND && $(readlink "$COMMAND") == */rouvy ]]; }
stale_launcher() {
  local target
  [[ ! -L $LAUNCHER && -f $LAUNCHER ]] || return 1
  target=$(sed -n 's/^Exec="\(.*\/rouvy\)" start$/\1/p' "$LAUNCHER")
  [[ -n $target && ! -e $target ]]
}

if [[ ${1:-} == --uninstall ]]; then
  if owns_command || stale_command; then rm -- "$COMMAND"; fi
  if owns_launcher || stale_launcher; then rm -- "$LAUNCHER"; fi
  for left in "$COMMAND" "$LAUNCHER"; do
    if [[ -e $left || -L $left ]]; then echo "Left alone, it does not belong to $ROOT: $left"; fi
  done
  echo "Uninstall complete for $ROOT. The VM is untouched."
  exit 0
fi

if [[ -e $LAUNCHER || -L $LAUNCHER ]] && ! owns_launcher && ! stale_launcher; then
  echo "error: $LAUNCHER already exists and belongs to another installation" >&2
  exit 1
fi
mkdir -p "$BIN" "$APPS"
if stale_command; then rm -- "$COMMAND"; fi
if ! owns_command; then
  ln -sT -- "$ROOT/rouvy" "$COMMAND" || {
    echo "error: could not install $COMMAND" >&2
    exit 1
  }
fi
cat >"$LAUNCHER" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Rouvy
Comment=Indoor cycling in a Windows VM with Bluetooth passthrough
Exec="$ROOT/rouvy" start
Icon=$ROOT/assets/rouvy-linux.svg
Terminal=false
Categories=Game;SportsGame;
Actions=stop;

[Desktop Action stop]
Name=Stop Rouvy
Exec="$ROOT/rouvy" stop
DESKTOP

echo "Installed: $BIN/rouvy and the Rouvy launcher."
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "Note: $BIN is not on your PATH yet." ;;
esac
if [[ ! -f $ROOT/storage/windows.boot ]]; then
  echo "Next: rouvy doctor, then rouvy build"
fi
