# getkbd

Move one Apple Magic Keyboard between two Macs using the USB signal from a monitor KVM.
getkbd watches local display, USB, Bluetooth, and system state, and can switch the monitor's input
over the display cable. It does not read keyboard or mouse input and does not use the network.

## Requirements

- Two Macs running macOS 26 or later
- Apple Magic Keyboard paired with both Macs
- A monitor with a KVM and a USB hub that appears only on the selected Mac
- A way to change the monitor input: its controls, compatible input-switching software, or, on
  Apple Silicon Macs with a monitor that supports DDC/CI, the getkbd menu
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
2. Launch getkbd on both Macs. Settings opens automatically the first time.
3. Choose the shared keyboard and monitor. getkbd selects them for you when there is only one of
   each.
4. Under **Teach getkbd your monitor**, click **Start**, switch the monitor to your other Mac, then
   switch it back. getkbd detects the USB connection that follows the monitor input.
5. Repeat the setup on the other Mac.

No pairing, network connection, or coordination between the two getkbd instances is required.

## Use

1. Leave getkbd running on both Macs.
2. Change the monitor input with the monitor controls, compatible input-switching software, or
   **Switch Monitor to Other Mac** / **Switch Monitor to This Mac** in the getkbd menu.
3. The Mac the monitor switches to claims the keyboard.
4. The Mac the monitor switches away from releases the keyboard and, when its built-in display is
   active, makes that display the main display.

The selected display is a safety condition. If it is physically absent, getkbd releases the
keyboard and will not automatically claim it. If both Macs see the monitor's USB hub, the hardware
does not expose a unique active-host signal and automatic switching is not safe.

## Display behavior

When setup is complete and **Switch the main display with the monitor** is on (the default),
getkbd follows the monitor input while keeping both displays extended:

- When the monitor is showing this Mac, the external monitor is primary.
- When the monitor is showing the other Mac and the laptop display is active, the built-in
  display is primary, so the menu bar and new windows stay on a screen you can see.
- When the monitor is showing the other Mac while the laptop is in clamshell mode, getkbd leaves
  the active external display as macOS has configured it.

When the setting is off, getkbd does not change the main display.

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

## Menu

The menu shows where the keyboard is and, when one applies, a single keyboard action:

- **Release Keyboard**: shown when this Mac has the keyboard.
- **Get Keyboard**: shown when the monitor is showing this Mac but the keyboard is not connected,
  or when the monitor is not connected.
- **Try Again**: shown after a claim or release fails.

It can also show one monitor action:

- **Switch Monitor to Other Mac**: shown on the Mac the monitor is showing.
- **Switch Monitor to This Mac**: shown on the Mac the monitor is not showing.

Choosing one changes the monitor input over the display cable; getkbd then moves the keyboard as it
does when you press the monitor's input button. getkbd learns which input belongs to each Mac by
reading the monitor after each switch, so the actions appear after you have switched the monitor
away from and back to a Mac once. They need an Apple Silicon Mac and a monitor that accepts DDC/CI
input commands on that connection; otherwise they are not shown.

Keep the keyboard awake during pairing. If getkbd shows a passkey, type it on the keyboard and
press Return.

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
- If monitor switching setup does not detect the switch, make sure the monitor's USB upstream
  cable is connected to this Mac, then click **Try Again**.
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
