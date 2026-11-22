# Tests and contributing

## Running them

```bash
bats tests                              # launcher and installer against fake docker, ssh and USB devices
python3 -m unittest discover -s tests   # QEMU monitor client against a fake monitor, docs against the code
tests/smoke.sh                          # the real VM: Windows, Bluetooth, Rouvy and the idle inhibitor
```

The first two need only bats (1.2 or newer) and Python 3. They never touch Docker, the VM or
Bluetooth, so they are safe to run anywhere.

`tests/smoke.sh` is for your own machine. It needs a built VM that is stopped, takes about a
minute and borrows the Bluetooth adapter, unless something is connected to the adapter on the
Linux side. The PowerShell scripts only run on Windows: CI just parses them, the smoke test is
what really exercises them.

## What CI does

On every pull request and every push to `main`:

- lint: ShellCheck on the shell scripts, a compile check of the Python, a parse of the
  PowerShell scripts and `docker compose config` on the compose file
- the two unit suites in ten userlands, each with its own packages: Ubuntu 20.04, 22.04, 24.04,
  26.04 and the latest release, Debian 12 and 13, Arch, Fedora and openSUSE Tumbleweed

The second part is less paranoid than it looks. bash, coreutils and util-linux differ between
those more than you would expect (bash 5.0 to 5.3, bats 1.2 to 1.14, and most of Ubuntu's
coreutils have been the Rust rewrite since 25.10), and the launcher leans on all three.

## Where it has really run

### The laptop it was built on

Intel Core Ultra 7 155H, Ubuntu 26.04 LTS with GNOME on Wayland (kernel 7.0), Docker 29.9 with
Compose 5.7, the built-in Intel AX211 Bluetooth adapter. The VM is Windows 11 Pro 25H2 with
Rouvy 4.8.4.

Everything runs here, including the two things that need real hardware and a real desktop: the
hand-over of the Bluetooth adapter and the GNOME idle inhibitor. The smoke test has 17 checks on
a GNOME desktop and passes all of them; the extra one asks GNOME itself whether it sees the
inhibitor. A `rouvy build` from scratch takes 33 minutes on this machine, 18 of them downloading
Windows.

### Fresh installs of other distributions

Each of these is the distribution's own cloud image, booted as a KVM guest on that laptop, with
Docker installed from the packages listed in the [README](../README.md#what-you-need). The
Windows VM then runs nested inside it. That is slow, but otherwise the real thing: the
distribution's kernel, its Docker, and its AppArmor or SELinux where it has one.

| Distribution | Kernel | Docker, Compose | Result of `tests/smoke.sh` |
| --- | --- | --- | --- |
| Debian 13 | 6.12 | 26.1.5, 2.26.1 (Debian's) | all 16 checks, after a `rouvy build` from scratch on it |
| Debian 12 | 6.1 | 29.10.0, 5.8.0 (docker.com) | all 16 checks |
| Ubuntu 24.04 | 6.8 | 29.1.3, 2.40.3 (Ubuntu's) | all 16 checks |
| Arch Linux | 7.3 | 29.10.0, 5.8.0 (Arch's) | all 16 checks |
| Fedora 45, SELinux enforcing | 7.2 | 29.9.3, 5.7.1 (Fedora's) | all 16 checks, once `container_use_devices` is on |
| openSUSE Tumbleweed, SELinux enforcing | 7.3 | 29.9.2, 5.8.0 (openSUSE's) | all 16 checks, once `container_use_devices` is on |

Only Debian 13 went through the whole `rouvy build`. The others booted a copy of the Windows
disk that was built there.

Fedora and openSUSE are in this table because trying them found real bugs. The VM did not start
at all under SELinux, and on openSUSE the container could neither load the `tun` module nor set
up NAT, so the launcher could not reach Windows. The launcher now takes care of the SELinux
labels and of `tun`. NAT still does not come up on openSUSE, so the VM ends up on the user-mode
network of dockur/windows there, which is slower. Rouvy starts on it; I have not measured what it
means for a ride.

These guests lack two things, and here is what stood in for them:

- A Bluetooth adapter. An emulated USB device took its place (`ROUVY_BT=0627:0001`), so the
  smoke test still went through the whole hand-over: found in sysfs, given to QEMU, visible in
  Windows, back with Linux after `rouvy stop`. What Windows does with a real adapter does not
  depend on the Linux distribution.
- A desktop session. The watcher that inhibits screen blanking ran with a dummy command in
  place of a real inhibitor.

### Other Ubuntu releases

The launcher has also driven the laptop's own VM from Ubuntu 20.04, 22.04, 24.04, 25.10 and
26.10 userlands: containers with that release's bash, coreutils, Docker client, Compose and
OpenSSH, talking to the Docker daemon of the host.

### Not tried yet

- desktops other than GNOME (KDE should be fine, see
  [Screen blanking and suspend](commands.md#screen-blanking-and-suspend))
- Bluetooth adapters other than Intel's AX211
- AMD processors
- Podman in place of Docker

If you ride with this on something that is not listed, open an
[issue](https://github.com/zielinskitomasz/rouvy-linux/issues) and tell me the distribution, the
adapter and the trainer. I will add it here.

## Contributing

Bug reports and "it works on X" notes are welcome as issues.

For changes, please open an issue first and wait for a yes. I merge everything myself and would
rather agree on the idea before you put work into a pull request. When you do send one, run the
two unit suites; CI runs them again on all ten userlands.
