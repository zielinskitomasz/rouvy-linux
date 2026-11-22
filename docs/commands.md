# Commands and settings

## Commands

`rouvy` without arguments is `rouvy start`.

| Command | What it does |
| --- | --- |
| `rouvy start` | Boots the VM, hands over Bluetooth, starts Rouvy, opens the screen. `--no-bt`, `--no-launch` and `--no-view` each skip one of those steps. |
| `rouvy stop` | Shuts Windows down cleanly. Bluetooth returns to Linux. |
| `rouvy status` | State of the VM, the Bluetooth adapter, Rouvy (with its version), the number of open screens and screen blanking. |
| `rouvy view` | Opens the VM screen again after you closed the window. |
| `rouvy build` | First-time setup: installs Windows and Rouvy. |
| `rouvy update` | Installs the latest Rouvy release inside the VM. `--force` reinstalls the current one. |
| `rouvy bt attach\|detach\|check\|driver` | Bluetooth housekeeping, see [bluetooth.md](bluetooth.md). |
| `rouvy ssh [command]` | Runs PowerShell inside the VM, for example `rouvy ssh 'Get-Process Rouvy'`. Without a command you get a shell. |
| `rouvy screenshot` | Saves a PNG of the VM screen to `screenshots/`. |
| `rouvy monitor <cmd>` | Sends a raw command to the QEMU monitor, for example `rouvy monitor info usb`. |
| `rouvy logs` | Follows the container log. |
| `rouvy doctor` | Checks that this machine can run the VM and says what is missing. |

The menu entry that `install.sh` adds runs `rouvy start` and has a "Stop Rouvy" action in its
context menu. Started from there, progress shows up as desktop notifications, if `notify-send` is
installed.

## Settings

Copy `rouvy.conf.example` to `rouvy.conf` and uncomment what you need. Environment variables
with the same names win over the file, which is handy for a one-off: `ROUVY_BT=off rouvy`.
CPU, memory, disk and audio settings apply from the next start after a `rouvy stop`.

| Setting | Default | Meaning |
| --- | --- | --- |
| `ROUVY_CPUS` | `8` | CPU threads for the VM. Rouvy renders on the CPU, so more is smoother. |
| `ROUVY_RAM` | `8G` | Memory for the VM. |
| `ROUVY_DISK` | `64G` | Size of the Windows disk. It is a sparse file and only takes what Windows really uses. Can be raised later, not lowered. |
| `ROUVY_AUDIO` | `Y` | Stream the VM's sound to the screen in the browser, `Y` or `N`. |
| `ROUVY_LANGUAGE`, `ROUVY_REGION`, `ROUVY_KEYBOARD` | `English`, `en-US`, `en-US` | Windows language, region and keyboard layout. Read by `rouvy build` only. |
| `ROUVY_TIMEZONE` | empty | Windows time zone name such as `Central European Standard Time` (list them with `rouvy ssh 'tzutil /l'`). Empty keeps what Windows picks for the region. Read by `rouvy build` only. |
| `ROUVY_BT` | `auto` | `auto` uses the only USB Bluetooth adapter, `off` never touches Bluetooth, `vendor:product` (from `lsusb`) picks one. |
| `ROUVY_BT_DRIVER_URL` | Intel 24.80.0 | Driver package fetched for Intel adapters when Windows has none. |
| `ROUVY_VIEWER` | `auto` | `auto` opens a Chromium-based browser in app mode or else the default browser, `none` only prints the address, anything else is run as a command with `ROUVY_SCREEN_URL` in its environment. |
| `ROUVY_INHIBIT` | `auto` | What keeps the screen awake during a ride, see below. `off` disables it. |
| `ROUVY_INSTALLER_URL` | Rouvy CDN | Where the Rouvy installer comes from. |
| `ROUVY_IMAGE` | `dockurr/windows:6.05` | Container image of the VM. |
| `ROUVY_NAME` | `rouvy` | Container name prefix, for a second VM from another checkout. Give that one its own three ports as well. |
| `ROUVY_WEB_PORT`, `ROUVY_RDP_PORT`, `ROUVY_SSH_PORT` | `8006`, `3389`, `2222` | Local ports of the screen, RDP and SSH. All listen on 127.0.0.1 only. |
| `ROUVY_BUILD_TIMEOUT` | `5400` | Seconds `rouvy build` waits before it gives up. |

## The screen and its sound

The screen is the noVNC page the container serves at http://127.0.0.1:8006. The panel on its left
edge has a full screen button and, under Settings, an Audio switch that turns on the sound of the
VM. Browsers only start audio after a click, so it is off until you flip it.

Closing the window stops nothing. `rouvy view` brings it back.

Any RDP client works as well: `127.0.0.1:3389`, user `rouvy`, password `rouvy`.

## Screen blanking and suspend

Nobody touches the keyboard during a ride, so the desktop would dim, lock and eventually suspend.
While Rouvy is running and its screen is open, in the browser or over RDP, `rouvy` holds an idle
inhibitor. As soon as you
close the window or quit Rouvy the desktop goes back to normal, so a VM you forgot about does not
keep the laptop awake all night. `rouvy status` shows which state you are in.

On GNOME this uses `gnome-session-inhibit`. Elsewhere it falls back to `systemd-inhibit`. KDE
Plasma's power manager follows that one too, going by its source code; I have only tried GNOME
myself. If your desktop ignores it, set `ROUVY_INHIBIT` to a command that holds an inhibitor for
as long as it runs. With KDE's own tool that would be:

```
ROUVY_INHIBIT="kde-inhibit --power --screenSaver sleep infinity"
```

Windows inside the VM never blanks its display.
