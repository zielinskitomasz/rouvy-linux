# Troubleshooting

Start with these two, they answer most questions:

```bash
rouvy doctor     # is this machine able to run the VM at all?
rouvy status     # what are the VM, Bluetooth and Rouvy doing right now?
```

The VM screen is always at http://127.0.0.1:8006, also during the build. When something hangs,
look there first: Windows usually says what it is waiting for.

## The trainer does not show up in Rouvy

1. `rouvy status`: the adapter must belong to the VM.
2. `rouvy bt check`: the adapter must be listed as OK with its radio on, and you should see some
   BLE devices in range.
3. Wake the trainer up by pedalling.
4. Make sure nothing else holds it: a phone app, a bike computer, or Linux itself if it was ever
   paired there (`bluetoothctl remove <MAC>`).

More background in [bluetooth.md](bluetooth.md).

## "SELinux blocks USB devices for containers"

Fedora, openSUSE and other SELinux systems do not let a container open device nodes unless you
allow it. The VM still runs, but it never gets the Bluetooth adapter. Allow it once:

```bash
sudo setsebool -P container_use_devices on
rouvy stop && rouvy
```

## "QEMU cannot see the adapter any more"

The adapter changed owner since the VM started, for example after `rouvy bt detach`. Restart the
VM: `rouvy stop && rouvy`.

## "NSIS Error: Error writing temporary file" when Rouvy updates itself

Close the error and run `rouvy update`.

Why it happens: Rouvy downloads its installer into `AppData\LocalLow`, a folder with a Low
integrity label. UAC is switched off in the VM, so nothing elevates the installer. It starts at
Low integrity and cannot write to any temp folder. `rouvy build` and every `rouvy update`
relabel Rouvy's download folder to prevent this, and `rouvy update` itself does not go through
that folder at all.

## Rouvy does not log in, or complains about the time

Restart the VM once: `rouvy stop && rouvy`. Rouvy refuses to log in when the clock is wrong.
Windows reads the VM's clock correctly (as UTC) only from the boot after setup, which is why
`rouvy build` ends by shutting Windows down. A build that was cut short before that leaves the
first start with the wrong time. `rouvy ssh Get-Date` shows what Windows thinks the time is.

## "Windows did not come up"

Look at the screen at http://127.0.0.1:8006 and at `rouvy logs`. Most of the time Windows is
installing updates and just needs a few more minutes. Run `rouvy` again afterwards.

## "docker daemon not reachable" in `rouvy doctor`

Either Docker is not running (`sudo systemctl enable --now docker`) or your user is not in the
`docker` group yet (`sudo usermod -aG docker $USER`, then log out and in again).

On Arch, a `pacman -Syu` that brought a new kernel leaves Docker unable to start until you
reboot.

## The picture stutters

The VM has no GPU. Windows falls back to its software renderer and Rouvy draws on the CPU.
What helps:

- give the VM as many threads as you can spare (`ROUVY_CPUS` in `rouvy.conf`)
- set the video quality in Rouvy's settings to the lowest level
- keep the laptop on mains power

Real GPU acceleration would need GPU passthrough (a second GPU with VFIO, or Intel SR-IOV). That
is outside what this project does. If smooth graphics matter more to you than anything else,
have a look at [the Wine-based projects](how-it-works.md#why-a-vm-and-not-wine).

## The screen still blanks during a ride

`rouvy status` tells you whether blanking is inhibited right now. It only is while Rouvy runs
and its screen is open. If it says inhibited and the screen blanks anyway, your desktop ignores
the inhibitor: see [Screen blanking and suspend](commands.md#screen-blanking-and-suspend). The
watcher writes every change of state to `$XDG_RUNTIME_DIR/rouvy-rouvy/watch.log`.

## Still stuck

Open an [issue](https://github.com/zielinskitomasz/rouvy-linux/issues) and paste the output of
`rouvy doctor` and `rouvy status`. If the VM screen shows something odd, a `rouvy screenshot`
helps a lot, but look at it first: it may show your Rouvy account.

## Starting over

To reinstall Windows from scratch: `rouvy stop`, delete the `storage/` directory, `rouvy build`.
Your Rouvy login and downloaded routes live on that disk, so they go with it.

To remove everything:

```bash
rouvy stop
docker rm rouvy-windows
docker network rm rouvy_default
docker rmi dockurr/windows:6.05
./install.sh --uninstall
```

Then delete the checkout. If you changed `ROUVY_NAME` or `ROUVY_IMAGE`, the container, network
and image carry those names instead.
