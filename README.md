# Rouvy on Linux

[![CI](https://github.com/zieludev/rouvy-linux/actions/workflows/ci.yml/badge.svg)](https://github.com/zieludev/rouvy-linux/actions/workflows/ci.yml)

[ROUVY](https://rouvy.com) has no Linux app. This runs the Windows one in a Windows 11 virtual
machine and lends that VM your Bluetooth adapter, so the trainer pairs just like on a Windows PC.
Setting it up takes about half an hour, once. After that it is one command:

```bash
rouvy
```

It boots the VM, hands over Bluetooth, starts Rouvy, opens its window and keeps your screen from
blanking while you ride. `rouvy stop` shuts it all down and gives Bluetooth back to Linux.

This is an unofficial hobby project, not affiliated with ROUVY or VirtualTraining s.r.o. You
need your own Rouvy account.

## Install and build

Get Docker and KVM working first, see [What you need](#what-you-need). Clone this somewhere it
can stay, on a disk with 40 GB free: the Windows VM lives inside the checkout.

```bash
git clone https://github.com/zieludev/rouvy-linux.git
cd rouvy-linux
./install.sh     # links `rouvy` into ~/.local/bin and adds a menu entry
rouvy doctor     # tells you what this machine is missing, if anything
rouvy build      # installs Windows 11 and Rouvy, unattended
```

`rouvy build` runs once and needs no babysitting. It downloads Windows 11 from Microsoft (8.5 GB)
and the Rouvy installer from Rouvy, installs both and switches the VM off again. On a fast line
that is about half an hour, most of it download. You can watch at http://127.0.0.1:8006, and if
it gets interrupted, running it again picks up where it stopped.

If `~/.local/bin` is not on your PATH, `install.sh` says so. `./rouvy` from the checkout works
either way.

## Ride

```bash
rouvy          # start everything
rouvy stop     # shut Windows down, Bluetooth is back in Linux
```

On the first start, log in to Rouvy (it remembers you) and pair the trainer inside Rouvy, not in
the Windows settings. Closing the window does not stop anything, `rouvy view` brings it back.
There is also a Rouvy icon in your application menu that does the same as `rouvy`.

Trainer not showing up? [Start here](docs/troubleshooting.md#the-trainer-does-not-show-up-in-rouvy).

## Update

```bash
rouvy update     # Rouvy has a new version
git pull         # this project has a new version (run it inside the checkout)
```

`rouvy update` fetches the current installer from Rouvy, checks its signature and installs it in
the VM, whether the VM is running or not. Your login and your routes stay. Prefer it to the
Update button inside the app, which has failed in the VM before. After a `git pull` there is nothing to reinstall, the `rouvy`
command is a link into the checkout.

## What you need

- x86-64 Linux with KVM (`/dev/kvm`)
- Docker with the Compose plugin, plus `ssh` and `curl`
- 16 GB of RAM and a CPU with threads to spare: the VM has no GPU, Rouvy renders on the CPU
- 40 GB of free disk
- a USB Bluetooth adapter (the built-in one of most laptops is exactly that)
- ideally a Chromium-based browser, it gives the nicest window

Docker, for the distributions I tried it on:

```bash
sudo apt install docker.io docker-compose-v2            # Ubuntu 24.04 and newer
sudo apt install docker.io docker-compose               # Debian 13
sudo pacman -S docker docker-compose                    # Arch
sudo dnf install moby-engine docker-cli docker-compose  # Fedora
sudo zypper install docker docker-compose               # openSUSE Tumbleweed
```

Debian 12 packages a Compose that is too old, so take Docker from
[docker.com](https://docs.docker.com/engine/install/debian/) there.

Then `sudo systemctl enable --now docker`, `sudo usermod -aG docker $USER`, and log out and in
again. Fedora and openSUSE need one more thing, or SELinux keeps the Bluetooth adapter out of the
VM: `sudo setsebool -P container_use_devices on`. `rouvy doctor` checks all of it.

## Three things to know before the first ride

Bluetooth leaves Linux while you ride. The VM takes the whole adapter, so headphones, mice and
keyboards connected through it drop off until `rouvy stop`. Switch Bluetooth headphones off
beforehand, or give the VM a cheap dongle of its own. [More about Bluetooth](docs/bluetooth.md).

The picture is drawn by the CPU. It works, but it is no match for a real GPU: give the VM plenty
of threads and set Rouvy's video quality to the lowest level.

Windows is installed without a product key. Licensing it is yours to sort out, see the
[dockur/windows FAQ](https://github.com/dockur/windows#faq).

## Tested on

| Linux | What ran there |
| --- | --- |
| Ubuntu 26.04, GNOME on Wayland | Everything, on the laptop this was built on: the build, Bluetooth with an Intel AX211, the screen-blanking inhibitor. |
| Debian 13 | A fresh install: `rouvy build` from scratch, then the end-to-end test (start, Bluetooth hand-over, Rouvy running, stop). |
| Debian 12, Ubuntu 24.04, Arch | Fresh installs: the same end-to-end test. |
| Fedora 45, openSUSE Tumbleweed | Fresh installs with SELinux enforcing: the same end-to-end test. |

The fresh installs were virtual machines without a desktop, and an emulated USB device stood in
for the Bluetooth adapter. Rouvy was 4.8.4 on Windows 11 25H2. The unit tests also run for every
pull request on ten distributions and releases, from Ubuntu 20.04 to Arch and Tumbleweed.
[The details](docs/testing.md).

Does it work for you on something else? Open an issue and tell me, with your trainer and
adapter, and I will add it here.

## More documentation

- [Commands and settings](docs/commands.md): every `rouvy` command, `rouvy.conf`, the screen and
  its sound, how screen blanking is handled
- [Bluetooth](docs/bluetooth.md): what happens to your adapter, drivers, using a second dongle
- [Troubleshooting](docs/troubleshooting.md): the trainer does not show up, update errors,
  stuttering, starting over
- [How it works](docs/how-it-works.md): what is inside, where files live, security notes
- [Tests and contributing](docs/testing.md): how this is tested, on what, and how to send a
  change

## Other ways to run Rouvy on Linux

There are projects that run Rouvy under Wine with their own Bluetooth code:
[evanjt/rouvy-linux](https://github.com/evanjt/rouvy-linux),
[jelmer/rouvy-wine](https://github.com/jelmer/rouvy-wine) and
[liesai/rouvy-linux-wine](https://github.com/liesai/rouvy-linux-wine). When one of them works
with your trainer it is the lighter choice: Rouvy uses your GPU, there is no Windows involved and
Bluetooth stays with Linux.

This project trades all that for running the unmodified app on a real Windows. Nothing about
Bluetooth is re-implemented and nothing is tied to a particular Rouvy version. The longer
comparison is in [How it works](docs/how-it-works.md#why-a-vm-and-not-wine).

## Licence

[MIT](LICENSE). What this builds on is listed in [3rdparty_licenses.md](3rdparty_licenses.md),
first of all [dockur/windows](https://github.com/dockur/windows). The idea of a one-command
launcher comes from [netbrain/zwift](https://github.com/netbrain/zwift), which does the same for
Zwift.

ROUVY is a trademark of VirtualTraining s.r.o. Windows is a trademark of Microsoft.
