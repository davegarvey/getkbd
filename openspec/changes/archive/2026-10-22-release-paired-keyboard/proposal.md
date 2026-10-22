## Why

On 2026-10-22 Bluetooth was turned off on the Mac holding the keyboard. The keyboard stayed paired to that Mac but disconnected. When the monitor switched to the other Mac, getkbd on the first Mac did not release the keyboard: it only releases a keyboard that is connected, and with Bluetooth off it could not release one anyway. The keyboard, still bonded to the first Mac, ignored every claim from the second Mac for over an hour until it was power-cycled and claimed by hand.

## What Changes

- When the monitor is not showing this Mac, release the selected keyboard if it is paired to this Mac, whether or not it is connected.
- Re-check when Bluetooth comes back on, so that a pairing left behind while Bluetooth was off is removed as soon as it can be.
- When the keyboard selection changes, release the previous keyboard if it is paired, not only if it is connected.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `keyboard-handoff`: releasing applies to a paired keyboard, connected or not, including after Bluetooth returns and on a keyboard selection change.

## Impact

- `KeyboardController` exposes whether the selected keyboard is paired locally; `OwnershipController` uses it for release decisions.
- No change to claiming, retries or menu wording. A Mac whose Bluetooth stays off still cannot release the keyboard; this change frees it once Bluetooth is back.
