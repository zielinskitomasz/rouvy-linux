# Rouvy on Linux

[![CI](https://github.com/zielinskitomasz/rouvy-linux/actions/workflows/ci.yml/badge.svg)](https://github.com/zielinskitomasz/rouvy-linux/actions/workflows/ci.yml)

[ROUVY](https://rouvy.com) has no Linux version. This project runs the Windows app in a Windows 11
virtual machine and hands that VM your Bluetooth adapter, so Rouvy talks to the smart trainer the
same way it does on a real Windows PC. One command starts everything:

```bash
rouvy
```

It boots the VM, moves the Bluetooth adapter into it, starts Rouvy, opens its screen in a window
and keeps your desktop from blanking the screen or going to sleep while you ride. `rouvy stop`
shuts it down and gives Bluetooth back to Linux.

This is an unofficial hobby project. It is not affiliated with or endorsed by ROUVY or
VirtualTraining s.r.o., and you need your own Rouvy account.

## How it works

```
 Linux host                               Windows 11 VM (QEMU/KVM in a container)
+------------------------------+         +----------------------------------------+
| rouvy (this repository)      |  start  |                                        |
|   docker compose, QEMU, SSH -+-------->|  Rouvy.exe                             |
| browser window  <------------+---------+- screen and sound (noVNC)              |
| USB Bluetooth adapter -------+-------->|  Windows Bluetooth stack ---> trainer  |
+------------------------------+  USB    +----------------------------------------+
```

- The VM is [dockur/windows](https://github.com/dockur/windows): QEMU/KVM inside a Docker
  container. Nothing is installed on the host besides Docker.
- Bluetooth under Wine cannot reach BLE trainers, which is why this uses a real Windows with a
  real Bluetooth stack. The whole USB Bluetooth controller is passed through to the VM.
- Windows is installed unattended by `rouvy build`; a provisioning script then installs an SSH
  server (the host drives the VM through it) and Rouvy.

## Requirements

- x86-64 Linux with KVM (`/dev/kvm`), Docker Engine and the Compose v2 plugin
- 16 GB RAM or more and a CPU with plenty of threads: the VM has no GPU, Rouvy renders on the CPU
- about 40 GB of free disk space
- a USB Bluetooth adapter (the built-in adapter of most laptops is a USB device too)
- `ssh`, `curl` and, for the nicest window, a Chromium-based browser

`rouvy doctor` checks all of this.

## Install

```bash
git clone https://github.com/zielinskitomasz/rouvy-linux.git
cd rouvy-linux
./install.sh      # puts `rouvy` into ~/.local/bin and adds a "Rouvy" launcher to the desktop
rouvy doctor
rouvy build
```

`rouvy build` runs once. It downloads Windows 11 from Microsoft (about 8.5 GB) and the Rouvy
installer from the Rouvy CDN, installs both without any interaction and shuts the VM down when it
is done. Expect about half an hour on a fast connection, most of it the Windows download; the VM
then takes about 15 GB of disk. You can watch the installation at http://127.0.0.1:8006, and an
interrupted build continues when you run `rouvy build` again.

Windows is installed without a product key. Licensing it is your responsibility, see the
[dockur/windows FAQ](https://github.com/dockur/windows#faq).

## Riding

```bash
rouvy          # start everything
rouvy stop     # shut Windows down, Bluetooth returns to Linux
```

The first start takes a little longer because Windows still has to find a driver for the
Bluetooth adapter (see below). Log in to Rouvy once; it remembers the account. Pair the trainer inside Rouvy, not in the
Windows settings.

Closing the window does not stop anything, `rouvy view` opens the screen again. The launcher added
by `install.sh` runs `rouvy` and has a "Stop Rouvy" action in its context menu.

## Commands

| Command | What it does |
| --- | --- |
| `rouvy` or `rouvy start` | Boot the VM, hand over Bluetooth, start Rouvy, open the screen. `--no-bt`, `--no-launch` and `--no-view` skip a step. |
| `rouvy stop` | Shut Windows down cleanly. Bluetooth returns to Linux. |
| `rouvy status` | State of the VM, the Bluetooth adapter, Rouvy and screen blanking. |
| `rouvy view` | Open the VM screen again. |
| `rouvy build` | First-time setup: install Windows and Rouvy. |
| `rouvy update` | Install the latest Rouvy release inside the VM. `--force` reinstalls. |
| `rouvy bt attach\|detach\|check\|driver` | Move the adapter, list what Windows sees and which BLE devices are in range, install the adapter's driver. |
| `rouvy ssh [command]` | Run PowerShell inside the VM, e.g. `rouvy ssh 'Get-Process Rouvy'`. |
| `rouvy screenshot` | Save a PNG of the VM screen to `screenshots/`. |
| `rouvy monitor <cmd>` | Raw QEMU monitor command, e.g. `rouvy monitor info usb`. |
| `rouvy logs` | Follow the container log. |
| `rouvy doctor` | Check that this host can run the VM. |

## Settings

Copy `rouvy.conf.example` to `rouvy.conf` and uncomment what you need. Environment variables with
the same names win over the file.

| Setting | Default | Meaning |
| --- | --- | --- |
| `ROUVY_CPUS` | `8` | CPU threads for the VM. More is smoother. |
| `ROUVY_RAM` | `8G` | Memory for the VM. |
| `ROUVY_DISK` | `64G` | Size of the Windows disk (a sparse file). Can be raised later, not lowered. |
| `ROUVY_AUDIO` | `Y` | Stream the VM's sound to the browser screen. |
| `ROUVY_LANGUAGE`, `ROUVY_REGION`, `ROUVY_KEYBOARD` | `English`, `en-US`, `en-US` | Windows language, region and keyboard layout. Read by `rouvy build` only. |
| `ROUVY_TIMEZONE` | empty | Windows time zone name such as `Central European Standard Time`. Empty keeps what Windows picks for the region. Read by `rouvy build` only. |
| `ROUVY_BT` | `auto` | `auto` uses the only USB Bluetooth adapter, `off` never touches Bluetooth, `vendor:product` (from `lsusb`) picks one. |
| `ROUVY_BT_DRIVER_URL` | Intel 24.80.0 | Driver package fetched for Intel adapters when Windows has none. |
| `ROUVY_VIEWER` | `auto` | `auto` opens a Chromium-based browser in app mode or the default browser, `none` only prints the address, anything else is run as a command with `ROUVY_SCREEN_URL` set. |
| `ROUVY_INHIBIT` | `auto` | What keeps the screen awake, see below. `off` disables it. |
| `ROUVY_INSTALLER_URL` | Rouvy CDN | Where the Rouvy installer comes from. |
| `ROUVY_IMAGE` | `dockurr/windows:6.05` | Container image of the VM. |
| `ROUVY_NAME` | `rouvy` | Container name prefix, for a second VM from another checkout. |
| `ROUVY_WEB_PORT`, `ROUVY_RDP_PORT`, `ROUVY_SSH_PORT` | `8006`, `3389`, `2222` | Local ports of the screen, RDP and SSH. All listen on 127.0.0.1 only. |

## Bluetooth

- While the VM owns the adapter, Linux has no Bluetooth: mice, keyboards and headphones connected
  through it drop off until `rouvy stop` (or `rouvy bt detach`).
- A device that loses its link abruptly keeps calling the adapter. Windows then answers under the
  same Bluetooth address but without the device's keys, and some devices react by dropping the
  pairing, so they have to be paired with Linux again (seen with a headset). To make that less
  likely `rouvy` disconnects everything from Linux cleanly before the hand-over; switching such
  devices off before a ride, or giving the VM a dongle of its own (see below), is the safe choice.
- QEMU only sees USB devices that existed when the VM started, and the adapter re-enumerates
  every time it changes owner. So after `rouvy bt detach` it can only be attached again by
  restarting the VM: `rouvy stop && rouvy`.
- A BLE trainer talks to one central at a time. If it was ever paired with Linux, remove it there
  first (`bluetoothctl remove <MAC>`).
- Windows normally fetches a driver for the adapter from Windows Update by itself, within a
  minute of the first hand-over. If the adapter still does not work, `rouvy` downloads Intel's
  driver package from intel.com for Intel adapters and installs it in the VM. For another vendor,
  put its installer into `shared/setup/drivers/` (it is run with `/quiet /norestart`) and run
  `rouvy bt driver`.
  `rouvy bt driver --force` reinstalls a driver that is already there.
- If you need Bluetooth on Linux during a ride, plug in a second, cheap USB dongle and give that
  one to the VM with `ROUVY_BT=vendor:product`.
- `rouvy bt check` shows the adapter as Windows sees it and lists the BLE devices in range.

## Screen blanking and suspend

Nobody touches the keyboard during a ride, so the desktop would dim, lock and eventually suspend.
While Rouvy is running and its screen is open, `rouvy` holds an idle inhibitor. As soon as you
close the window or quit Rouvy the desktop goes back to its normal behaviour, so a VM you forgot
about does not keep the laptop awake.

On GNOME this uses `gnome-session-inhibit`. Elsewhere it falls back to `systemd-inhibit`, which
not every desktop honours; in that case set `ROUVY_INHIBIT` to a command that holds an inhibitor
for as long as it runs, for example on KDE:

```bash
ROUVY_INHIBIT="kde-inhibit --power --screenSaver sleep infinity"
```

Windows inside the VM never blanks its display.

## Screen and sound

The screen is the noVNC page served by the container at http://127.0.0.1:8006. The panel on its
left edge has a full screen button and, under Settings, an Audio switch that turns on the sound of
the VM (browsers only start audio after a click). Any RDP client works as well: `127.0.0.1:3389`,
user `rouvy`, password `rouvy`.

## Updating Rouvy

When Rouvy asks for an update, run `rouvy update`. It downloads the current installer on the host,
checks its signature inside the VM and installs it silently. Rouvy's own "Update" button should
work too; if it ends in an NSIS error, see Troubleshooting.

## Performance

The VM has no GPU acceleration, Windows falls back to its software renderer and Rouvy draws on
the CPU. What helps:

- give the VM as many threads as you can spare (`ROUVY_CPUS`)
- set the video quality in Rouvy's settings to the lowest level
- keep the laptop on mains power

Real GPU acceleration would need GPU passthrough (a second GPU with VFIO, or Intel SR-IOV), which
is outside the scope of this project.

## Troubleshooting

**"NSIS Error: Error writing temporary file" when Rouvy updates itself.** Rouvy downloads its
installer into `AppData\LocalLow`, a folder with a Low integrity label. UAC is switched off in the
VM, so nothing elevates the installer: it starts at Low integrity and cannot write to any temp
folder. The provisioning script relabels Rouvy's download folder to prevent this. If it still
happens, close the error and run `rouvy update`.

**Rouvy does not log in, or says the time is wrong.** The clock setting made by `rouvy build` only
applies after a restart of the VM: `rouvy stop && rouvy`.

**The trainer does not show up in Rouvy.** Check `rouvy status` (the adapter must belong to the
VM) and `rouvy bt check` (the adapter must be listed as OK with its radio on, and some BLE devices
should be visible). Wake the trainer up by pedalling, and make sure no phone app is connected to it.

**"QEMU cannot see the adapter any more".** The adapter changed owner since the VM started.
Restart the VM: `rouvy stop && rouvy`.

**"Windows did not come up".** Look at the screen at http://127.0.0.1:8006 and at `rouvy logs`.
Windows may be installing updates.

## Tests

```bash
bats tests                              # launcher and installer against fake docker, ssh and USB devices
python3 -m unittest discover -s tests   # QEMU monitor client against a fake monitor
tests/smoke.sh                          # the real VM: Windows, Bluetooth, Rouvy and the idle inhibitor
```

The first two need only bats (1.2 or newer) and Python 3. They never touch Docker, the VM or
Bluetooth, and CI runs them on Ubuntu 20.04, 22.04, 24.04, 26.04 and the latest release, because
bash, coreutils and util-linux differ between those.

`tests/smoke.sh` is for your own machine. It needs a built VM that is stopped, takes about a
minute and borrows the Bluetooth adapter, unless something is connected to the adapter on the
Linux side. The PowerShell scripts only run on Windows: CI just parses them, the smoke test is
what really exercises them.

## Rebuilding and removing

To reinstall Windows from scratch, run `rouvy stop`, delete the `storage/` directory and run
`rouvy build` again.

To remove everything: `rouvy stop`, `./install.sh --uninstall`, delete this directory and remove
the image with `docker rmi dockurr/windows:6.05`.

## Security notes

- The screen, RDP and SSH ports listen on 127.0.0.1 only. The Windows account is `rouvy` with the
  password `rouvy`.
- `rouvy build` creates an SSH key pair in `ssh/` that is valid for this VM only.
- The container needs `/dev/kvm`, `NET_ADMIN` and access to USB devices, as dockur/windows does
  for USB passthrough.

## Tested with

The machine that runs the VM is an Intel Core Ultra 7 155H laptop with Ubuntu 26.04 (GNOME on
Wayland), Docker 29 and the built-in Intel AX211 Bluetooth adapter; the VM is Windows 11 Pro 25H2
with Rouvy 4.8.4.

The launcher has also driven that same VM from Ubuntu 20.04, 22.04, 24.04, 25.10 and 26.10
userlands, with their own bash, coreutils, docker client (26 to 29), Compose (2.27 to 2.40) and
OpenSSH (8.2 to 10.5). Other desktops, Bluetooth adapters and viewers should work but have not
been tried.

## Licence and credits

The scripts in this repository are released under the [MIT licence](LICENSE).
[3rdparty_licenses.md](3rdparty_licenses.md) lists what they build on, first of all
[dockur/windows](https://github.com/dockur/windows). The idea of a one-command launcher comes
from [netbrain/zwift](https://github.com/netbrain/zwift), which does the same for Zwift.

ROUVY is a trademark of VirtualTraining s.r.o. Windows is a trademark of Microsoft.
