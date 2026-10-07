## Context

See `proposal.md` for the user problem and `specs/keyboard-handoff/spec.md` for the retry contract. `OwnershipController` currently uses a fixed delay array for all automatic claim failures. It already serializes operations, cancels retries when the desired ownership changes, and resets retry state after local signal transitions. A full claim removes the local pairing when needed and starts a Bluetooth pairing operation, so retries must remain bounded.

## Goals / Non-Goals

**Goals:**

- Make a keyboard that becomes available shortly after a hub transition more likely to be claimed without user intervention.
- Preserve single-flight claim behavior and the existing response to monitor, hub, sleep, Bluetooth, and manual signals.
- Keep a finite slow retry tail after the fast window.

**Non-Goals:**

- Change keyboard pairing or release semantics.
- Add keyboard power-state detection, new menu controls, or changes to manual Get Keyboard behavior.
- Change automatic release retry timing.

## Decisions

### Use a two-minute elapsed-time fast phase for automatic claims

Start the phase when the first automatic claim begins after the local ownership condition becomes eligible. If a claim fails during that phase, begin the next claim as soon as the previous operation finishes. Preserve a five-second minimum start-to-start interval for failures that return unusually quickly, so an immediate API error cannot create a tight loop. A normal pairing attempt lasts long enough that this guard adds no delay.

An elapsed-time window is preferable to a fixed number of rapid retries because pairing operations can take different amounts of time. It keeps the fast recovery period near two minutes whether a particular attempt fails quickly or spends time in the pairing flow.

### Back off through three bounded delays, then stop

After the fast phase expires, wait 15 seconds, 30 seconds, and 60 seconds after successive failures. Stop after those three slow retries. This adds recovery chances without allowing automatic pairing work to continue indefinitely.

### Reset the cycle only when the automatic claim context changes

Start a fresh fast phase when the automatic claim condition becomes eligible after a local monitor or USB-hub transition, startup, wake, or a failed Try Now attempt that returns to an eligible automatic target. Keep the current cancellation and reconciliation behavior when signals make the condition ineligible. Preserve Bluetooth availability gating and leave manual-target retry behavior unchanged.

### Keep the retry state in the ownership controller

Track the fast-phase start time and slow-retry position alongside the existing automatic retry task. Continue scheduling only after `finishOperation` records a failure; the existing `operationInProgress` guard ensures claims never overlap. Keep the menu's existing retrying status and Try Now action.

## Risks / Trade-offs

- **Repeated pairing requests may add Bluetooth activity and may not help while the keyboard is asleep** → bound the continuous phase to two minutes, enforce the five-second start-to-start floor for very fast failures, and retain a finite slow tail.
- **An attempt can occupy much of the two-minute window** → define the phase by elapsed time and start a new attempt immediately after each ordinary failure, rather than promising a fixed number of attempts.
- **Signal transitions during an operation can race with the timer** → retain single-flight state checks and re-evaluate the latest desired state before every scheduled retry.

## Migration Plan

No settings migration is required. The retry policy is in-memory and restarts from current local signals whenever the app launches. No rollback data is needed; reverting the change restores the previous delay schedule.
