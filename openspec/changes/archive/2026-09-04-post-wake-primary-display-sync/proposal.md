## Why

macOS can restore a saved display layout after a laptop wakes and make the shared
monitor primary even though getkbd had previously made the built-in display
primary. getkbd currently waits for a USB-hub transition in this situation, so
the laptop can remain on the wrong primary display until the monitor input is
switched.

## What Changes

- Treat primary-display changes caused by display reconfiguration and wake
  restoration as reconciliation triggers, even when the set of active displays
  is unchanged.
- Defer wake-time primary-display synchronization until display state has settled
  and use the current stable local hub signal rather than synchronizing
  immediately from cached wake state.
- Keep the existing hub-driven target rules, extended display arrangement, and
  application-scoped CoreGraphics configuration unchanged.
- Add focused regression coverage and diagnostic logging for post-wake target
  selection and primary-display correction.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `keyboard-handoff`: require post-wake and display-reconfiguration reconciliation
  of the preferred primary display without waiting for a hub transition.

## Impact

- Affects `DisplayMonitor`, `USBHubMonitor`, wake/signal ordering in `AppDelegate`,
  and the focused display-primary tests.
- Uses the existing AppKit, CoreGraphics, USB-hub, and sleep/wake integrations;
  no new dependency or persisted setting is required.
- The behavior remains local and best-effort. Keyboard ownership remains
  independent of display-role failures.
