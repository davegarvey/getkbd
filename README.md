# getkbd

`getkbd` is a native macOS menu-bar utility that moves one paired Apple Magic Keyboard to the Mac currently connected to a configured desk monitor.

It targets the latest macOS SDK (macOS 26 or later) and is intentionally optimized for a single two-Mac setup rather than older-system compatibility.

## Current MVP

- Claims the selected Bluetooth keyboard after a stable configured-display connection by clearing
  the local stale pairing, pairing again, and verifying the connection.
- Releases monitor-owned keyboards after a stable display disconnect by removing the local pairing,
  which prevents macOS from immediately reconnecting the old host.
- Makes a best-effort release before macOS sleep.
- Provides `Get Keyboard` and `Release Keyboard` menu commands.
- Registers a configurable global shortcut, defaulting to `Ctrl+Opt+Cmd+K`.
- Stores keyboard, monitor, automatic-behaviour, shortcut, and login-item settings.
- Uses display UUIDs rather than display names for the configured monitor.
- Keeps all Bluetooth operations serialized and verifies the resulting connection state.

Peer discovery and LAN coordination are intentionally not part of this first slice. A peer is an
optimization; direct local release and claim are the core workflow. For the automatic two-Mac
workflow, run getkbd on both Macs so the old Mac can remove its pairing before the new Mac pairs.

## Build

The repository uses Swift Package Manager:

```sh
swift build
swift test
./scripts/build-app.sh
```

The executable must run as an app bundle for menu-bar behavior, login-item registration, and the Bluetooth privacy prompt to work correctly. `Sources/GetKbd/Resources/Info.plist` contains the bundle metadata used by packaging scripts or an Xcode wrapper.

For login-item registration, build the app with a local Apple Development or Developer ID signing identity:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh
```

Without `CODESIGN_IDENTITY`, the script creates an ad-hoc signed app suitable for local UI/Bluetooth experiments, but macOS will not approve it as a login item.

The first launch opens Settings when no keyboard or desk monitor has been selected. Pair the
keyboard with each Mac once before testing so both installations can identify it. After setup,
getkbd removes and recreates the local pairing as part of each handoff.

## Platform notes

Bluetooth handoff uses the public `IOBluetoothDevicePair` pairing API and synchronous connection APIs.
macOS does not expose a public unpair API, so release uses the undocumented
`IOBluetoothDevice.remove` selector used by tools such as blueutil, MagicDock, and monnect. This
is intentional for this personal macOS 26 utility and may break in a future macOS release.

The handoff is:

1. The old Mac removes its local pairing when its monitor disconnects.
2. The new Mac removes any stale local record, pairs the keyboard, connects, and verifies it.

The keyboard may need to be awake during pairing. Tap a key or power-cycle it if a claim fails.
If the previous Mac is already asleep, shut down, or has getkbd stopped before removing its local
pairing, this MVP cannot remotely preempt that host; peer coordination is the next hardening step.

Display changes use `NSApplication.didChangeScreenParametersNotification` with a 1.5 second stability debounce. Sleep events use `NSWorkspace.shared.notificationCenter`.
