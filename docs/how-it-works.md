# How it works

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
  container. Besides Docker the host only needs `ssh` and `curl`.
- The whole USB Bluetooth controller is passed through to the VM, so Rouvy uses the real Windows
  Bluetooth stack. Details in [bluetooth.md](bluetooth.md).
- The host drives the VM over SSH (start Rouvy, update it, check on it) and through the QEMU
  monitor (USB hand-over, screenshots, counting viewers).

## What `rouvy build` does

1. Creates an SSH key pair in `ssh/` that is only good for this VM.
2. Downloads the Rouvy installer from the Rouvy CDN on the host.
3. Starts the container. dockur downloads Windows 11 from Microsoft and installs it unattended.
4. At the end of the unattended setup, `oem/install.bat` fetches `shared/setup/setup.ps1` from
   the shared folder and runs it. That script sets the power plan and the clock, installs an
   OpenSSH server with your key, checks the Rouvy installer's signature and installs Rouvy
   silently.
5. Shuts Windows down. From here on `rouvy` only boots that disk.

Windows is installed without a product key. Licensing it is your responsibility, see the
[dockur/windows FAQ](https://github.com/dockur/windows#faq).

## Where things live

The VM and your settings stay inside the checkout, and git tracks none of these paths. Outside it
there are only the container and its image in Docker, the `rouvy` link in `~/.local/bin`, the
menu entry and, while the VM runs, the watcher's state and log in `$XDG_RUNTIME_DIR/rouvy-rouvy/`.

| Path | What |
| --- | --- |
| `storage/` | The Windows disk (`data.img`, a sparse file) and the VM's firmware state. Your Rouvy login and downloaded routes are in here. |
| `ssh/` | The key pair for this VM. |
| `shared/` | The folder Windows sees as `\\host.lan\Data`: downloaded installers, drivers, the setup log. Only the scripts in `shared/setup/*.ps1` belong to the repository. |
| `rouvy.conf` | Your settings. |
| `screenshots/` | What `rouvy screenshot` saved. |

## What an update touches

| You run | It changes | It keeps |
| --- | --- | --- |
| `rouvy update` | The Rouvy app inside Windows. | Login, routes, settings, everything else. |
| `git pull` | The launcher and its scripts. The `rouvy` command is a link into the checkout, so there is nothing to reinstall. | The VM, completely. |
| delete `storage/`, then `rouvy build` | Everything: a brand new Windows. | Nothing on the Windows side. You log in to Rouvy again. |

Windows keeps itself up to date through Windows Update, like on any PC.

## Security notes

- The screen, RDP and SSH ports listen on 127.0.0.1 only. The Windows account is `rouvy` with the
  password `rouvy`, which is fine for that and nothing else: do not expose those ports.
- The container gets `/dev/kvm`, `/dev/net/tun`, `NET_ADMIN` and all of `/dev/bus/usb`, with a
  cgroup rule that allows every USB device. That is how dockur/windows does USB passthrough, and
  it lets an adapter that re-enumerates stay visible. QEMU only takes the one device `rouvy`
  hands over, but the container could open any of them.
- On SELinux systems the container stays confined. `storage/`, `shared/` and `oem/` are relabelled
  for it when it starts (the `:Z` in `compose.yaml`), and USB devices only reach it after you
  switch on `container_use_devices` yourself.
- The Rouvy installer is checked for a valid signature of VirtualTraining s.r.o. before it runs.

## Why a VM and not Wine?

As of November 2026 stock Wine cannot scan for Bluetooth LE devices, so Rouvy cannot find a
trainer there. Three projects get around that with Bluetooth code of their own:

- [evanjt/rouvy-linux](https://github.com/evanjt/rouvy-linux): a patched Wine build with an
  installer and launcher
- [jelmer/rouvy-wine](https://github.com/jelmer/rouvy-wine): patched Wine in a Podman image
- [liesai/rouvy-linux-wine](https://github.com/liesai/rouvy-linux-wine): replacement DLLs and a
  BlueZ bridge for an unpatched Wine

If one of them works with your trainer, it is the lighter way. Rouvy renders on your GPU, there
is no Windows to download or to license, and Bluetooth stays with Linux.

This project makes the opposite trade. It runs the unmodified app on a real Windows with the real
Windows Bluetooth stack. Nothing is re-implemented, so it does not depend on a particular Rouvy
or Wine version. You pay for that with a CPU-rendered picture, a Windows disk of 15 GB that grows
with every Windows update (mine reached 25 GB in two months), 8 GB of RAM while riding, and a
Bluetooth adapter that is gone from Linux for the length of the ride.

| | This project | The Wine projects |
| --- | --- | --- |
| Graphics | CPU only | your GPU |
| Disk and memory | 15 GB and up, 8 GB RAM for the VM | a Wine build and the app |
| Bluetooth during a ride | belongs to the VM | stays with Linux |
| Bluetooth code | Windows' own | re-implemented on top of BlueZ |
| A new Rouvy release | runs like on any Windows PC | may need a new build or a reinstall of the shims |
| Windows licence | your responsibility | not needed |
