## Why

Display-only sleep can cause the monitor to switch to the other laptop. GetKbd observes the USB handover but does not explicitly reconcile the main display when the laptop screen wakes, leaving the external monitor primary.

## What Changes

- Observe screen wake separately from system wake and force a settled primary-display reconciliation using refreshed USB state.
- Keep keyboard ownership and macOS window placement unchanged during screen-only wake.
- Add regression coverage and document screen-wake recovery.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `keyboard-handoff`: Extend sleep recovery to screen-only wake, even when display topology and USB presence do not change.

## Impact

SleepMonitor, AppDelegate, DisplayMonitor, focused XCTest coverage, and README. No new dependencies or permissions.
