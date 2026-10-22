## Why

On 2026-10-22 the Mac the monitor switched to could not claim the keyboard: it was still paired to the other Mac, whose Bluetooth had been turned off. getkbd retried for about five minutes and then stopped for good, so even once the other Mac could release the keyboard, nothing would have claimed it. The menu said only that the keyboard was not responding, without saying what would help. The keyboard was recovered by switching it off and on and choosing Get Keyboard.

## What Changes

- After the existing fast recovery window and 15, 30 and 60 second backoff, keep retrying an eligible automatic claim every five minutes instead of stopping.
- While an automatic claim is failing, the menu says "Keyboard isn’t answering. Switch it off and on, then choose Try Now." and offers Try Now. It does not name a cause, since this Mac cannot tell why the keyboard does not answer.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `keyboard-handoff`: automatic claims continue at a five-minute interval after backoff.
- `configuration-and-controls`: the retrying menu state tells the user to power-cycle the keyboard and choose Try Now.

## Impact

- `AutomaticClaimRetryPolicy` gains a persistent interval; `OwnershipController` uses it once the backoff delays are exhausted. `MenuStatus` changes one title.
- A failed claim keeps the radio paging for about 16 seconds, so the five-minute interval keeps that to about 5% of the time while the keyboard is unreachable, limiting disruption to Bluetooth audio.
