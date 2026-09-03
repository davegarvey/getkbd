## Why

When a monitor KVM switches away from a Mac, macOS can keep the shared monitor
connected and primary even though that Mac no longer receives the monitor's USB
hub signal. Its desktop and application windows then remain on a screen the user
cannot see. The existing hub signal already identifies which Mac is using the
monitor, so getkbd can correct only the primary-display role without changing
the physical display connection or keyboard handoff model.

## What Changes

- **BREAKING** Change the display behavior for configured KVM use so the stable
  selected USB-hub signal determines the preferred primary display: the selected
  external display when the hub is present, and the active built-in display when
  the hub is absent.
- Apply the primary-display change through public CoreGraphics display-origin
  configuration with application-only scope, translating the existing active
  display arrangement without changing display modes, enablement, mirroring, or
  relative positions.
- Re-evaluate the preferred primary display at startup, after stable hub
  transitions, after relevant display active-state changes such as opening or
  closing the laptop lid, and after wake.
- Preserve clamshell behavior: when the built-in display is inactive, do not try
  to make it primary; leave the active external display configuration alone.
- Keep primary-display handling independent from keyboard claim/release
  operations. A display-role failure SHALL not block or fail keyboard handoff.
- Rely on macOS for any resulting window relocation. Do not enumerate, move, or
  persist application windows.
- Do not add display mirroring, display parking, display disabling, mode
  restoration, peer communication, or a new window-management subsystem.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `keyboard-handoff`: replace the unconditional preservation of primary-display
  selection with a narrow hub-driven primary-display exception while preserving
  all other display configuration and local keyboard ownership behavior.

## Impact

- Affects the display configuration adapter and application wiring, most likely
  `Sources/GetKbd/DisplayMonitor.swift`, `Sources/GetKbd/AppDelegate.swift`, and
  focused display-role tests.
- Uses the existing CoreGraphics and USB-hub signals; no new framework or
  external dependency is required.
- Changes the user-visible primary display and may cause macOS to relocate
  windows as a consequence, but getkbd will not manipulate windows directly.
- Requires the current `keyboard-handoff` specification and display-related
  documentation to replace the display-neutral handoff contract.
