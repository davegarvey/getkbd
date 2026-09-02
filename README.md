# getkbd

Move one Apple Magic Keyboard between two Macs using the USB signal from a BenQ monitor KVM.
getkbd watches local display, USB, Bluetooth, and system state. It does not read keyboard or
mouse input and does not use the network.

## Requirements

- Two Macs running macOS 26 or later
- Apple Magic Keyboard paired with both Macs
- BenQ MA270S, or a monitor KVM with a USB hub that appears only on the selected Mac
- BenQ Display Pilot 2 installed on both Macs for software input switching
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
3. Open **Settings** and select the same keyboard and external BenQ display on both Macs.
4. Select the USB hub connected through the monitor KVM on each Mac.
5. If the hub is difficult to identify, click **Identify input signal**, change the BenQ input,
   and let getkbd select the hub whose connection changes.
6. Repeat the setup on the other Mac.

The selected hub must appear on only the Mac currently selected by the BenQ input. No pairing,
network connection, or coordination between the two getkbd instances is required.

## Use

1. Leave getkbd running on both Macs.
2. Change the BenQ input with Display Pilot 2 or the monitor controls.
3. The Mac where the selected USB hub appears claims the keyboard.
4. The Mac where the hub disappears releases the keyboard and parks its external display.

The selected display is a safety condition. If it is physically absent, getkbd releases the
keyboard and will not automatically claim it. If both Macs see the selected hub, the hardware
does not expose a unique active-host signal and automatic switching is not safe.

## Display behavior

The inactive Mac does not mirror its laptop display onto the shared monitor. Instead, getkbd keeps
the external display signal online and covers that display with a temporary black window. This
keeps the KVM input switchable and avoids forcing either display to use the other display's scaling
or resolution.

When the hub appears again, getkbd removes the cover, restores the saved extended layout and
display mode, and makes the external display primary. The display remains physically connected
and actively signaled while parked, so the KVM USB hub and monitor input controls remain available.

Normal display parking does not use private display-disable APIs.

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
- **Identify input signal**: locally detect the USB connection that follows the BenQ input.
- **Refresh device lists**: reload available keyboards, displays, and USB hubs.

## Troubleshooting

- Pair the keyboard with both Macs before using getkbd.
- Select the physical USB hub that appears only when that Mac is active, not a HID device that
  remains connected on both Macs.
- If the display is parked but cannot be restored, open **Display Settings** and re-enable it;
  then use **Retry Display Layout** from the getkbd menu.
- If an older build left the display disabled and the monitor input cannot be switched back,
  restart that Mac before launching this build.
- Wake or power-cycle the keyboard if pairing fails.
- Both Macs must be running getkbd for automatic local handoff.
- The built-in **Launch getkbd at login** option requires a signed build and will not work with
  the default ad-hoc signature.
