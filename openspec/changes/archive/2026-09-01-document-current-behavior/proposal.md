## Why

The repository contains a working getkbd implementation but no main OpenSpec
specifications, so the documented contract cannot be validated or used to guide
future changes. This baseline records the behavior currently implemented at
HEAD, including the safety rules for automatic keyboard handoff.

## What Changes

- Document Bluetooth keyboard discovery, pairing, release, and failure behavior.
- Document monitor and KVM USB hub automation, manual overrides, ownership
  attribution, sleep handling, and operation reconciliation.
- Document settings persistence, device selection, menu-bar controls, shortcut
  registration, onboarding, and login-item behavior.
- Establish project context in `openspec/config.yaml` for future changes.

## Capabilities

### New Capabilities

- `keyboard-handoff`: Bluetooth keyboard control and local ownership state.
- `device-detection`: External display and KVM USB hub detection and keyboard
  discovery.
- `configuration-and-controls`: Persisted settings, menu-bar actions, settings
  UI, shortcuts, onboarding, and startup behavior.

### Modified Capabilities

None. The repository has no existing main capability specifications.

## Impact

- Adds the three main specifications under `openspec/specs/` through the normal
  OpenSpec sync flow.
- Updates only OpenSpec project context; implementation code and runtime
  behavior are unchanged.
- The specifications describe a macOS 26+ Swift/AppKit menu-bar application
  that uses local Bluetooth, display, USB, sleep, and login-item APIs without
  network coordination.
