# Bluetooth

Rouvy reaches the trainer over Bluetooth LE, and it does that through Windows. So for the length
of a ride the VM gets the whole USB Bluetooth controller, the same one Linux normally uses. The
built-in adapter of most laptops is a USB device too, so no dongle is needed.

## What that means for you

While the VM has the adapter, Linux has no Bluetooth. Mice, keyboards and headphones connected
through it drop off until `rouvy stop` (or `rouvy bt detach`).

Switch Bluetooth headphones and the like off before a ride. A device that loses its link
abruptly keeps calling the adapter. Windows then answers under the same Bluetooth address but
without the device's keys, and some devices react by forgetting the pairing, so they have to be
paired with Linux again. I have seen a headset do exactly that. `rouvy` now disconnects
everything from Linux cleanly before it hands the adapter over, which should make this less
likely, but a device that is switched off cannot get confused at all.

Many BLE trainers talk to one device at a time. If yours was ever paired with Linux, remove it there
first (`bluetoothctl remove <MAC>`), and close any phone app that is connected to it. Then pair
it inside Rouvy, not in the Windows settings.

On Fedora, openSUSE and other SELinux systems the VM only gets the adapter after
`sudo setsebool -P container_use_devices on`. `rouvy doctor` tells you when that is missing.

## Keeping Bluetooth on Linux during a ride

Plug in a second, cheap USB dongle and give that one to the VM:

```bash
lsusb                      # find the dongle, e.g. "ID 0a12:0001"
```

```
# rouvy.conf
ROUVY_BT=0a12:0001
```

With more than one adapter present `rouvy` refuses to guess and asks for this setting.
`ROUVY_BT=off` never touches Bluetooth at all.

## ANT+

Not tried, but there is a way to try it. `ROUVY_BT=vendor:product` hands over any USB device,
not only Bluetooth adapters, so an ANT+ stick can take the adapter's place. Bluetooth then stays
with Linux. Expect `rouvy start` to warn that Bluetooth is not working inside Windows: that check
looks for a Bluetooth adapter and does not apply to a stick. I have none to test with: if you do,
tell me how it went.

## The driver inside Windows

Windows normally fetches a driver for the adapter from Windows Update by itself, within a minute
of the first hand-over. That is why the very first start takes a little longer.

If the adapter still does not work after that, `rouvy` installs a driver itself:

- For Intel adapters it downloads Intel's driver package from intel.com (the URL is
  `ROUVY_BT_DRIVER_URL`) and installs it in the VM.
- For any other vendor, put the vendor's installer into `shared/setup/drivers/` and run
  `rouvy bt driver`. It has to be a signed `.exe`: every one in that folder is started with
  `/quiet /norestart`, anything unsigned is skipped.

Nothing is installed while Windows already reports the adapter as working.
`rouvy bt driver --force` installs anyway.

## Commands

| Command | What it does |
| --- | --- |
| `rouvy bt check` | Shows the adapter as Windows sees it and lists the BLE devices in range. The first thing to run when the trainer does not show up. |
| `rouvy bt detach` | Gives the adapter back to Linux while the VM keeps running. |
| `rouvy bt attach` | Hands it to the VM. Only works if the adapter has not changed owner since the VM started, see below. |
| `rouvy bt driver` | Installs the adapter's driver in Windows if it has none. |

## Why attaching again needs a restart

QEMU only sees USB devices that existed when the VM started, and the adapter re-enumerates every
time it changes owner. So after `rouvy bt detach` it can only go back to the VM through a
restart: `rouvy stop && rouvy`.
