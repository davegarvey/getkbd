## Context

`IOBluetoothKeyboardController` reports `connectedLocal` only when the device is connected, and `OwnershipController` releases only from `connectedLocal`. A Magic Keyboard bonded to a Mac whose Bluetooth is off, or which is asleep, is paired but disconnected there, so no release happens and the bond outlives the hand-over.

## Decisions

- Add `isPaired` to `KeyboardControlling`, refreshed with the connection state and after claim and release. A change in pairing alone notifies ownership, as a state change does. The protocol extension defaults it to `state == .connectedLocal` so that existing fakes keep their behaviour.
- In `reconcile`, a `.disconnected` target releases when the keyboard is connected or paired. The same condition applies when releasing the previous keyboard during reconfiguration.
- Bluetooth returning already triggers a forced reconcile; refreshing the pairing before that callback makes the release happen then.

## Risks / Trade-offs

- A Mac that is not showing the monitor now removes a dormant pairing at launch or when Bluetooth returns. This is the intended invariant: only the Mac the monitor is showing should hold the keyboard. A manual Get Keyboard still overrides it, as before.
- Nothing can be released while Bluetooth is off. If it stays off, the other Mac still needs the keyboard power-cycled and claimed by hand, as today.
