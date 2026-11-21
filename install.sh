#!/usr/bin/env bash
# Put `rouvy` on the PATH and add a desktop launcher. `./install.sh --uninstall` removes both.
set -euo pipefail

ROOT=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
BIN=${XDG_BIN_HOME:-$HOME/.local/bin}
APPS=${XDG_DATA_HOME:-$HOME/.local/share}/applications

if [[ ${1:-} == --uninstall ]]; then
  rm -f "$BIN/rouvy" "$APPS/rouvy-linux.desktop"
  echo "Removed the rouvy command and its launcher. The VM in $ROOT is untouched."
  exit 0
fi

mkdir -p "$BIN" "$APPS"
ln -sfn "$ROOT/rouvy" "$BIN/rouvy"
cat >"$APPS/rouvy-linux.desktop" <<DESKTOP
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
