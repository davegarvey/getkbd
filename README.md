# getkbd

`getkbd` is a native macOS menu-bar utility that moves one paired Apple Magic Keyboard to the Mac currently connected to a configured desk monitor.

It targets the latest macOS SDK (macOS 26 or later) and is intentionally optimized for a single two-Mac setup rather than older-system compatibility.

## Current MVP

- Claims the selected paired Bluetooth keyboard after a stable configured-display connection.
- Releases monitor-owned keyboard connections after a stable display disconnect.
- Makes a best-effort release before macOS sleep.
- Provides `Get Keyboard` and `Release Keyboard` menu commands.
- Registers a configurable global shortcut, defaulting to `Ctrl+Opt+Cmd+K`.
- Stores keyboard, monitor, automatic-behaviour, shortcut, and login-item settings.
- Uses display UUIDs rather than display names for the configured monitor.
- Keeps all Bluetooth operations serialized and verifies the resulting connection state.

Peer discovery and LAN coordination are intentionally not part of this first slice. A peer is an optimization; direct local release and claim are the core workflow.

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

The first launch opens Settings when no keyboard or desk monitor has been selected. Both Macs must have the keyboard paired in macOS Bluetooth settings.

## Platform notes

Bluetooth control uses the public synchronous `IOBluetoothDevice.openConnection()` and `closeConnection()` APIs. macOS does not expose a general-purpose public API for asking another Mac to release a keyboard, so the MVP intentionally relies on each Mac releasing its own connection before leaving or sleeping.

Display changes use `NSApplication.didChangeScreenParametersNotification` with a 1.5 second stability debounce. Sleep events use `NSWorkspace.shared.notificationCenter`.
