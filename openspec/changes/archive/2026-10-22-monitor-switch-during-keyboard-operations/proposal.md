## Why

The menu hides Switch Monitor while a keyboard claim or release is in progress. With continuous retries during the two-minute fast recovery window and five-minute retries afterwards, an unanswered keyboard can hide the monitor switch for long stretches, which is when the user is most likely to want to switch the monitor away. Monitor switching does not depend on Bluetooth, and switching during a claim is already safe: the hub group leaves, the claim finishes, and ownership reconciles towards release.

## What Changes

- Offer the monitor action regardless of keyboard operations. Its other conditions are unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `configuration-and-controls`: keyboard operations no longer hide the monitor action.

## Impact

- `MenuStatus.monitorAction` drops its keyboard-operation conditions. No change to ownership or monitor control.
