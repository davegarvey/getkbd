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
./scripts/install-app.sh
```

The script builds the release app and copies it to `~/Applications/getkbd.app`, where Spotlight can find it.
Press **Command-Space**, type `getkbd`, and press Return. To install into another writable Applications
folder, pass it as an argument, for example:

```sh
./scripts/install-app.sh /Applications
```

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
4. The Mac where the hub disappears releases the keyboard and, when its built-in display is
   active, makes that display primary.

The selected display is a safety condition. If it is physically absent, getkbd releases the
keyboard and will not automatically claim it. If both Macs see the selected hub, the hardware
does not expose a unique active-host signal and automatic switching is not safe.

## Display behavior

When the selected monitor and USB hub are configured, getkbd follows the local hub signal while
keeping both displays extended:

- When the selected USB hub is present, the selected external monitor is primary.
- When the selected USB hub is absent and the laptop display is active, the built-in display is
  primary.
- When the selected USB hub is absent while the laptop is in clamshell mode, getkbd leaves the
  active external display as macOS has configured it.

getkbd changes only the primary-display role. It does not change display enablement, mirroring,
mode, or relative arrangement, and it does not move application windows directly. macOS remains
responsible for normal window relocation when the primary display changes.

Primary-display changes are application-scoped rather than permanent display preferences. When
getkbd quits, macOS restores the prior session configuration; launching getkbd evaluates the
current hub signal again.

The selected external display remains a safety condition for automatic keyboard claims. If it is
physically absent, getkbd releases the keyboard and will not automatically claim it. If a display
role change fails, keyboard handoff continues independently.

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

### Build errors

`scripts/build-app.sh` uses the Swift toolchain selected by Xcode or Command Line Tools via `xcrun`,
rather than whichever `swift` happens to appear first on `PATH`.

If the build reports errors such as `unknown argument: -target-arch-variant`, `no such module
'Combine'`, or that the SDK is unsupported by the compiler, check the selected developer tools and SDK:

```sh
xcode-select -p
xcrun swift --version
xcrun --show-sdk-version
```

The compiler and SDK must come from compatible Xcode/Command Line Tools releases. After a macOS
upgrade, check **System Settings > General > Software Update** for matching Command Line Tools. If
none are offered, install the compatible Command Line Tools package from [Apple Developer
Downloads](https://developer.apple.com/download/all/).

- Pair the keyboard with both Macs before using getkbd.
- Select the physical USB hub that appears only when that Mac is active, not a HID device that
  remains connected on both Macs.
- If the display is missing after reconnecting, open **Display Settings** and verify the cable and
  selected monitor input before retrying the switch.
- Wake or power-cycle the keyboard if pairing fails.
- Both Macs must be running getkbd for automatic local handoff.
- The built-in **Launch getkbd at login** option requires a signed build and will not work with
  the default ad-hoc signature.

### Logs

getkbd records USB hub, display, keyboard and sleep events in the macOS unified log. To see what
happened during a switch, run this on each Mac shortly afterwards:

```sh
log show --last 10m --predicate 'subsystem == "com.getkbd.app"' --style compact
```

To watch events as they happen, replace `show --last 10m` with `stream`.
