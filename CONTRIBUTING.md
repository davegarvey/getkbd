# Contributing to getkbd

Thanks for helping improve getkbd. It is a macOS menu bar app that coordinates a keyboard handoff using local USB, Bluetooth, display, and system state. Changes should preserve that local-only design and avoid reading keyboard or mouse input.

## Requirements

- macOS 26 or later
- Xcode or Command Line Tools with a compatible Swift 6.2 toolchain

The package uses the Swift toolchain selected by `xcrun`.

## Build and check

Run the focused checks, the Swift package tests, and a release app build before opening a pull request:

```sh
./scripts/run-checks.sh
xcrun swift test
./scripts/build-app.sh release
```

The app bundle is written to `.build/release/getkbd.app`. `scripts/install-app.sh` installs it locally if you need to exercise the installed app.

## Where things live

- `Sources/GetKbd/` contains the app and its controllers for keyboard ownership, USB, Bluetooth, displays, sleep, and monitor input.
- `Tests/GetKbdTests/` contains Swift package tests.
- `Checks/GetKbdChecks/` contains the focused checks run by `scripts/run-checks.sh`.

Keep changes focused, and add or update tests when changing behavior that can be tested without the hardware.

## Hardware-dependent changes

For changes to keyboard handoff, USB hub detection, or monitor switching, describe what hardware you tested and what remains untested. The README explains the expected two-Mac and KVM setup. Include relevant macOS unified logs when reporting a failure, and remove any personal information before sharing them.

## Pull requests

Explain the problem and the behavior your change introduces. Include the checks you ran, hardware details for hardware-dependent changes, and screenshots for visible UI changes. Keep unrelated cleanup in a separate change.
