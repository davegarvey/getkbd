# getkbd

Move one Apple Magic Keyboard between two Macs using the USB signal from a monitor KVM.
getkbd watches local display, USB, Bluetooth, and system state. It does not read keyboard or
mouse input and does not use the network.

## Requirements

- Two Macs running macOS 26 or later
- Apple Magic Keyboard paired with both Macs
- A monitor with a KVM and a USB hub that appears only on the selected Mac
- Monitor controls or compatible input-switching software for changing the active monitor input
- Xcode Command Line Tools on each Mac

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

1. Pair the Apple Magic Keyboard with both Macs in **System Settings > Bluetooth**.
2. Launch getkbd on both Macs.
3. Open **Settings** and select the same keyboard and external monitor on both Macs.
4. Select the USB hub connected through the monitor KVM on each Mac.
5. If the hub is difficult to identify, click **Identify input signal**, change the monitor input,
   and let getkbd select the hub whose connection changes.
6. Repeat the setup on the other Mac.

The selected hub must appear on only the Mac currently selected by the monitor input. No pairing,
network connection, or coordination between the two getkbd instances is required.

## Use

1. Leave getkbd running on both Macs.
2. Change the monitor input with the monitor controls or compatible input-switching software.
3. The Mac where the selected USB hub appears claims the keyboard.
4. The Mac where the hub disappears releases the keyboard; its display configuration is unchanged.

The selected display is a safety condition. If it is physically absent, getkbd releases the
keyboard and will not automatically claim it. If both Macs see the selected hub, the hardware
does not expose a unique active-host signal and automatic switching is not safe.

## Display behavior

getkbd does not change display enablement, mirroring, mode, position, or primary-display selection
during keyboard handoff. The selected external display is only a safety condition for automatic
keyboard claims, so losing the USB hub or manually releasing the keyboard leaves the display alone.

Because the extended desktop layout remains unchanged, a laptop that is no longer using the monitor
may keep windows on the external display and make them appear hidden. To restore that laptop to its
built-in display, unplug the monitor cable from that laptop; macOS will make its built-in display
primary. After reconnecting the cable, wait for macOS to detect the display, then switch the monitor
to that Mac's input. getkbd will use the USB hub signal to claim the keyboard without changing the
display's native scaling.

Closed-lid use is supported when the external display is active. If the display cable is removed,
or the Mac sleeps, getkbd releases the keyboard and reevaluates all local signals after wake.

## Manual switching

- Choose **Release Keyboard** on the Mac currently using the keyboard.
- Choose **Get Keyboard** on the other Mac.
- Use the configured global shortcut to get the keyboard manually.

Keep the keyboard awake during pairing. If getkbd shows a passkey, type it on the keyboard and
press Return.

## Controls

- **Get Keyboard**: claim the selected keyboard.
- **Release Keyboard**: release the selected keyboard.
- **Settings**: change the selected keyboard, display, USB hub, shortcut, and launch-at-login
  preference.
- **Identify input signal**: locally detect the USB connection that follows the monitor input.
- **Refresh device lists**: reload available keyboards, displays, and USB hubs.

## Troubleshooting

- Pair the keyboard with both Macs before using getkbd.
- Select the physical USB hub that appears only when that Mac is active, not a HID device that
  remains connected on both Macs.
- If the display is missing after reconnecting, open **Display Settings** and verify the cable and
  selected monitor input before retrying the switch.
- Wake or power-cycle the keyboard if pairing fails.
- Both Macs must be running getkbd for automatic local handoff.
- The built-in **Launch getkbd at login** option requires a signed build and will not work with
  the default ad-hoc signature.
