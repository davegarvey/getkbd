## Context

See proposal.md for motivation. Relevant current state:

- `OwnershipController` runs one keyboard operation at a time. A failed automatic
  claim schedules a retry after 5, 15, 30, 60, 60 and 60 seconds while the
  monitor and USB hub remain on this Mac.
- `IOBluetoothKeyboardController.connect()` removes any old bond, waits one
  second, then runs `IOBluetoothDevicePair` on a serial queue for up to
  45 seconds. A sleeping keyboard never answers, so the attempt runs to the
  timeout. A keyboard power-cycled during the attempt is not picked up by it.
- `finishOperation` calls `keyboard.refreshState()` after clearing
  `operationInProgress`. The state change re-enters `keyboardStateChanged`, which
  reconciles before the failure is recorded and schedules the 0.75-second USB-hub
  claim. The log shows alternate failures retried after 0.8 seconds rather than
  on the schedule.
- A claim's failure state is overwritten by `refreshState()`, so between
  attempts the menu shows "Keyboard not connected" with Get Keyboard, and during
  an attempt "Connecting keyboard…" with no action.

## Goals / Non-Goals

**Goals:**

- Let the user start a claim at once after power-cycling the keyboard, whether
  getkbd is between attempts or part-way through one.
- Make the menu say plainly that getkbd is still trying.

**Non-Goals:**

- Detecting the keyboard's advertising and claiming automatically. This would
  remove the need for the action but needs Bluetooth discovery, which is a
  larger change.
- A power-cycle hint in the menu. The state line stays short; the README covers
  the recovery steps.
- Changing the retry delays or the pairing timeout.

## Decisions

### Try Now restarts the claim and keeps the current target

`OwnershipController.connectNow()` cancels any scheduled retry, resets the retry
count, and either starts a claim or, if a claim is in flight, asks the keyboard
controller to stop it and starts a new claim when it returns. It does not set a
manual target. An automatic loop therefore stays automatic: if the restarted
claim fails, retries resume from the 5-second delay, and a later loss of the USB
hub still releases the keyboard. A manual claim in flight stays manual.

Alternative considered: reuse `manualClaim()`. It would pin the target to
connected and stop automatic retries after one failure, which is worse when the
user is unsure whether the keyboard is awake yet.

### Pairing is cancelled cooperatively

`IOBluetoothKeyboardController` holds a lock-protected cancellation flag for the
claim in flight. `cancelConnect()` sets it. The pairing loop, which already polls
the run loop every 0.1 seconds, checks the flag and calls `pairer.stop()`, the
same call the 45-second timeout already makes before the next attempt. `connect()`
also checks the flag before pairing starts. Once pairing has succeeded the flag
is ignored, so a claim that is about to finish is not thrown away. A cancelled
claim returns `false`, logs `keyboard.claim.cancelled`, and leaves no error.

The next claim begins with the existing bond removal and one-second settle delay,
so the keyboard gets the same interval after `stop()` as it does after a timeout
today. The log from 5 October shows a claim succeeding about a second after a
timed-out one, which supports this.

### The snapshot reports a retry loop, not a counter

`OwnershipSnapshot` gains `isRetryingClaim`: the target is connected, the
keyboard is not connected, at least one automatic claim retry has been scheduled
since the last reset, and either a retry is scheduled or a claim is in flight.
`MenuStatus` uses it to choose "Keyboard isn’t responding" with Try Now. A claim
in flight outside a retry loop shows "Connecting keyboard…" with Try Now. A
release in flight keeps no action.

`publish()` runs after the retry is scheduled, so the snapshot never reports the
gap between a failure and its retry as idle.

### Record a failure before refreshing keyboard state

`finishOperation` refreshes the keyboard state while `operationInProgress` is
still set, so the re-entrant `keyboardStateChanged` only publishes. The function
then applies its own reconciliation once. A successful operation also cancels any
pending retry and resets the retry count.

## Risks / Trade-offs

- Stopping a pairing attempt may leave the controller briefly busy → the next
  claim's removal step and settle delay match the existing timeout path; verify
  with a power-cycle on the real keyboard.
- Fixing the 0.75-second re-claim makes automatic recovery slower than before on
  alternate failures → Try Now covers the case where the user knows the keyboard
  is ready, and the schedule now matches its stated design.
- Try Now appears briefly during every normal claim → claims usually take about
  three seconds, and the action is harmless if chosen.
