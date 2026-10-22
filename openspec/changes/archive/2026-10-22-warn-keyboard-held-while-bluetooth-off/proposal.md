## Why

Turning Bluetooth off on the Mac that holds the keyboard leaves the keyboard paired there. getkbd cannot release it until Bluetooth is back, so the other Mac cannot claim it either. The menu says only "Bluetooth is off", which does not tell the user that the keyboard is now stuck on this Mac. On 2026-10-22 this went unnoticed until the keyboard failed to move.

## What Changes

- When Bluetooth is off and the selected keyboard is still paired to this Mac, the menu says "Bluetooth is off, so the keyboard can’t be released" instead of "Bluetooth is off". The warning badge and the Turn Bluetooth On action are unchanged.
- getkbd does not turn Bluetooth on by itself; the user decides.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `device-detection`: the Bluetooth-off state names the stuck keyboard when it is still paired locally.

## Impact

- `OwnershipSnapshot` carries whether the keyboard is paired locally; `MenuStatus` chooses the title.
- Builds on the local pairing tracking added by `release-paired-keyboard`.
