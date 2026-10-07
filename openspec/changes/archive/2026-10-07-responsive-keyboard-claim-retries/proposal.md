## Why

When the selected monitor and USB hub reconnect, the automatic claim starts promptly, but repeated pairing failures lead to increasingly long waits. If the user wakes or power-cycles the keyboard during one of those waits, GetKbd may not try again for up to a minute, making a manual claim feel necessary.

## What Changes

- Retry eligible automatic keyboard claims consecutively, with only one full Bluetooth claim operation in flight at a time, during a two-minute fast recovery window.
- After the fast window, back off through longer bounded waits and stop after the final retry.
- Restart the retry policy when the local ownership signals become eligible again; preserve immediate Try Now behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `keyboard-handoff`: define a two-minute sequential fast retry window followed by bounded backoff and a final stop for eligible automatic claims.

## Impact

- `OwnershipController` automatic claim retry scheduling and focused state-machine coverage.
- Existing `keyboard-handoff` behavior contract; no new dependencies, APIs, or UI controls.
