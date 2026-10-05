## Why

A Magic Keyboard left unpaired and idle eventually stops answering pairing
requests, and only a power cycle makes it pairable again. getkbd keeps retrying
the claim with increasing delays, but it cannot know when the user has power-cycled
the keyboard. By the time the user does so, getkbd may be waiting up to a minute
before its next attempt, or part-way through an attempt that will run to its
45-second pairing timeout without noticing that the keyboard is now available.

The log from 5 October 2026 shows the second case: an attempt started at
09:38:12, the keyboard was power-cycled during it, and the attempt still ran to
its timeout at 09:38:57. The next attempt, a second later, paired in two seconds.

The menu offers no way to cut this short. While a claim is in progress it shows
"Connecting keyboard…" with no action, and between attempts it shows "Keyboard
not connected" with Get Keyboard, which does not tell the user that getkbd is
still retrying.

## What Changes

- While a claim is in progress or an automatic retry is pending, the menu offers
  **Try Now**. It abandons any pairing attempt in progress and starts a new claim
  immediately.
- After an automatic claim has failed and getkbd is still retrying, the menu
  states "Keyboard isn’t responding" for the whole retry loop, instead of
  alternating between "Connecting keyboard…" and "Keyboard not connected".
- While a claim or release is in progress or a claim is being retried, the
  menu-bar icon shows a keyboard with an ellipsis badge. It currently shows the
  filled keyboard during an attempt, which reads as connected, and the outline
  keyboard between retries.
- A claim started by Try Now that fails restarts the automatic retry schedule
  from its first delay.
- Fix the retry schedule: a failed automatic claim is currently retried after
  0.75 seconds on alternate failures, because refreshing the keyboard state
  re-triggers the USB-hub claim before the failure is recorded. Each failure now
  waits for its scheduled delay.
- Bring the retry scenario in the spec in line with the current schedule (six
  claim retries, two release retries).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `keyboard-handoff`: retry scenario corrected; claims can be restarted on demand.
- `configuration-and-controls`: menu states and actions while a claim is in
  progress or being retried.

## Impact

- `OwnershipController`: tracks the operation in flight, adds `connectNow()`,
  publishes whether a claim is being retried, and records failures before
  refreshing keyboard state.
- `KeyboardControlling` and `IOBluetoothKeyboardController`: add
  `cancelConnect()`, which stops a pairing attempt that has not yet finished.
- `OwnershipSnapshot`, `MenuStatus` and `MenuBarController`: new state line,
  action and in-progress icon.
- README menu and troubleshooting sections.
