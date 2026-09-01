# getkbd

Move one Apple Magic Keyboard between two Macs using an external monitor, a monitor KVM,
or a manual shortcut. getkbd watches display and USB connection state; it does not read
keyboard or mouse input and does not use the network.

## Requirements

- Two Macs running macOS 26 or later
- Apple Magic Keyboard
- External monitor
- Xcode Command Line Tools on each Mac

For KVM USB switching, the monitor must expose a USB hub that appears on only the active Mac.

The default build is ad-hoc signed and does not require an Apple Developer account.

## Install

Run these commands on each Mac:

```sh
git clone https://github.com/davegarvey/getkbd.git
cd getkbd
./scripts/build-app.sh release
open .build/release/getkbd.app
```

You can drag `.build/release/getkbd.app` into `/Applications` after building.

If macOS blocks the app, Control-click it, choose **Open**, and confirm.

## Setup

1. Open **System Settings > Bluetooth** and pair the keyboard with each Mac.
2. Launch getkbd on both Macs.
3. Open **Settings** and select the same keyboard on both Macs.
4. Select the external display used by the desk.
5. Choose an automatic source:
   - **Monitor connection** when the display cable is connected to only one Mac at a time.
   - **KVM USB hub connection** when the monitor is connected to both Macs and its USB hub
     appears only on the active Mac.
   - **Manual only** to switch from the menu bar or shortcut.
6. For KVM USB hub connection, switch the KVM to the Mac being configured, click **Identify KVM Hub**,
   and switch the KVM away and back. Confirm the hub that changes connection state.
7. Repeat the settings on the other Mac. Use **Refresh Keyboard, Monitor, and USB Hub Lists**
   whenever a device is missing.

## Use

For monitor switching, leave getkbd running on both Macs. Disconnecting the configured monitor
releases the keyboard; connecting it to the other Mac claims the keyboard there.

For monitor switching:

1. Connect the display cable to the Mac you want to use.
2. getkbd claims the keyboard when the selected display appears and releases it when the display disappears.

For KVM USB hub switching:

1. Connect the monitor's USB upstream ports to both Macs.
2. Select **KVM USB hub connection** on both Macs.
3. Leave getkbd running on both Macs.
4. Switch the KVM. The Mac where the selected USB hub appears claims the keyboard; the Mac where
   it disappears releases it.

The selected monitor is a safety condition in KVM mode. If either the monitor or selected hub is
absent, getkbd releases the selected keyboard. If both Macs see the selected hub at the same time,
the KVM does not expose a unique active-host signal and automatic switching is unsafe.

getkbd does not change macOS display arrangement or mirroring. The KVM handles the external display;
configure mirroring separately in **System Settings > Displays** if needed.

For manual switching:

1. Choose **Release Keyboard** on the Mac currently using the keyboard.
2. Choose **Get Keyboard** on the other Mac.

Keep the keyboard awake during pairing. If getkbd shows a passkey, type it on the keyboard and press
Return.

## Controls

- **Get Keyboard**: claim the selected keyboard.
- **Release Keyboard**: release the selected keyboard.
- **Settings**: change the keyboard, monitor, USB hub, automatic source, behaviour, and shortcut.
- **Refresh Keyboard, Monitor, and USB Hub Lists**: reload available devices.

## Troubleshooting

- Pair the keyboard with both Macs before using getkbd.
- Wake or power-cycle the keyboard if pairing fails.
- Both Macs must be running getkbd for independent monitor/USB state handling.
- In KVM mode, select the physical USB hub that appears only when that Mac is active, not a
  virtual HID device that remains connected on both Macs.
- The built-in **Launch getkbd at login** option requires a signed build and will not work with the default ad-hoc signature.
